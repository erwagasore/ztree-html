/// ztree-html — HTML renderer for ztree.
const std = @import("std");
const ztree = @import("ztree");
const Node = ztree.Node;
const Attr = ztree.Attr;

/// HTML5 void elements — must not have a closing tag.
const void_elements = std.StaticStringMap(void).initComptime(.{
    .{ "area", {} },
    .{ "base", {} },
    .{ "br", {} },
    .{ "col", {} },
    .{ "embed", {} },
    .{ "hr", {} },
    .{ "img", {} },
    .{ "input", {} },
    .{ "link", {} },
    .{ "meta", {} },
    .{ "source", {} },
    .{ "track", {} },
    .{ "wbr", {} },
});

/// Write HTML for a ztree Node to any writer.
pub fn render(node: Node, writer: anytype) !void {
    switch (node) {
        .text => |t| try writeEscapedText(writer, t),
        .raw => |r| try writer.writeAll(r),
        .fragment => |children| {
            for (children) |child| {
                try render(child, writer);
            }
        },
        .element => |e| {
            // Open tag
            try writer.writeAll("<");
            try writer.writeAll(e.tag);

            // Attributes
            for (e.attrs) |a| {
                try writer.writeAll(" ");
                try writer.writeAll(a.key);
                if (a.value) |v| {
                    try writer.writeAll("=\"");
                    try writeEscapedAttr(writer, v);
                    try writer.writeAll("\"");
                }
            }

            try writer.writeAll(">");

            // Void elements: no children, no closing tag.
            if (void_elements.has(e.tag)) return;

            // Children
            for (e.children) |child| {
                try render(child, writer);
            }

            // Close tag
            try writer.writeAll("</");
            try writer.writeAll(e.tag);
            try writer.writeAll(">");
        },
    }
}

/// Escape text content: & < >
fn writeEscapedText(writer: anytype, content: []const u8) !void {
    for (content) |c| {
        switch (c) {
            '&' => try writer.writeAll("&amp;"),
            '<' => try writer.writeAll("&lt;"),
            '>' => try writer.writeAll("&gt;"),
            else => try writer.writeByte(c),
        }
    }
}

/// Escape attribute values: & < > "
fn writeEscapedAttr(writer: anytype, content: []const u8) !void {
    for (content) |c| {
        switch (c) {
            '&' => try writer.writeAll("&amp;"),
            '<' => try writer.writeAll("&lt;"),
            '>' => try writer.writeAll("&gt;"),
            '"' => try writer.writeAll("&quot;"),
            else => try writer.writeByte(c),
        }
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;

fn renderToString(node: Node) ![]const u8 {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    try render(node, &aw.writer);
    var al = aw.toArrayList();
    return al.toOwnedSlice(testing.allocator);
}

// -- text --

test "text escaping — &, <, > replaced" {
    const html = try renderToString(ztree.text("a & b < c > d"));
    defer testing.allocator.free(html);
    try testing.expectEqualStrings("a &amp; b &lt; c &gt; d", html);
}

test "text — passthrough for plain content" {
    const html = try renderToString(ztree.text("hello world"));
    defer testing.allocator.free(html);
    try testing.expectEqualStrings("hello world", html);
}

test "text — empty string produces no output" {
    const html = try renderToString(ztree.text(""));
    defer testing.allocator.free(html);
    try testing.expectEqualStrings("", html);
}

test "text — quotes and unicode pass through" {
    const html = try renderToString(ztree.text("she said \"hi\" — it's café 🌍"));
    defer testing.allocator.free(html);
    try testing.expectEqualStrings("she said \"hi\" — it's café 🌍", html);
}

// -- raw --

test "raw — no escaping" {
    const html = try renderToString(ztree.raw("<svg>&<br></svg>"));
    defer testing.allocator.free(html);
    try testing.expectEqualStrings("<svg>&<br></svg>", html);
}

// -- attributes --

test "attribute value escaping — &, <, >, \" replaced" {
    const node = ztree.element("div", &.{ztree.attr("title", "a & b < c > d \"e\"")}, &.{});
    const html = try renderToString(node);
    defer testing.allocator.free(html);
    try testing.expectEqualStrings("<div title=\"a &amp; b &lt; c &gt; d &quot;e&quot;\"></div>", html);
}

test "boolean attribute — key with no value" {
    const node = ztree.closedElement("input", &.{
        ztree.attr("type", "checkbox"),
        ztree.attr("checked", null),
        ztree.attr("disabled", null),
    });
    const html = try renderToString(node);
    defer testing.allocator.free(html);
    try testing.expectEqualStrings("<input type=\"checkbox\" checked disabled>", html);
}

// -- void elements --

test "all 13 void elements — no closing tag" {
    const void_tags = [_][]const u8{
        "area", "base", "br", "col", "embed", "hr", "img",
        "input", "link", "meta", "source", "track", "wbr",
    };
    for (void_tags) |tag| {
        const html = try renderToString(ztree.closedElement(tag, &.{}));
        defer testing.allocator.free(html);
        // Must start with <tag> and have no closing tag
        try testing.expect(html.len > 2);
        try testing.expect(std.mem.indexOf(u8, html, "</") == null);
    }
}

test "void element ignores children" {
    const html = try renderToString(ztree.element("br", &.{}, &.{ztree.text("oops")}));
    defer testing.allocator.free(html);
    try testing.expectEqualStrings("<br>", html);
}

// -- non-void elements --

test "non-void empty element — always gets closing tag" {
    const html = try renderToString(ztree.element("div", &.{}, &.{}));
    defer testing.allocator.free(html);
    try testing.expectEqualStrings("<div></div>", html);
}

test "closedElement on non-void tag — still gets closing tag" {
    const html = try renderToString(ztree.closedElement("script", &.{ztree.attr("src", "app.js")}));
    defer testing.allocator.free(html);
    try testing.expectEqualStrings("<script src=\"app.js\"></script>", html);
}

test "element with attrs and children" {
    const node = ztree.element("div", &.{ztree.attr("class", "card")}, &.{ztree.text("hello")});
    const html = try renderToString(node);
    defer testing.allocator.free(html);
    try testing.expectEqualStrings("<div class=\"card\">hello</div>", html);
}

test "nested elements — correct open/close order" {
    const node = ztree.element("ul", &.{}, &.{
        ztree.element("li", &.{}, &.{ztree.text("one")}),
        ztree.element("li", &.{}, &.{ztree.text("two")}),
    });
    const html = try renderToString(node);
    defer testing.allocator.free(html);
    try testing.expectEqualStrings("<ul><li>one</li><li>two</li></ul>", html);
}

// -- fragment --

test "fragment — children rendered without wrapper" {
    const node = ztree.fragment(&.{
        ztree.text("a"),
        ztree.element("b", &.{}, &.{ztree.text("bold")}),
        ztree.text("c"),
    });
    const html = try renderToString(node);
    defer testing.allocator.free(html);
    try testing.expectEqualStrings("a<b>bold</b>c", html);
}

test "nested fragments — transparent" {
    const node = ztree.fragment(&.{
        ztree.fragment(&.{ztree.text("a")}),
        ztree.fragment(&.{ztree.text("b")}),
    });
    const html = try renderToString(node);
    defer testing.allocator.free(html);
    try testing.expectEqualStrings("ab", html);
}

test "none — produces no output" {
    const html = try renderToString(ztree.none());
    defer testing.allocator.free(html);
    try testing.expectEqualStrings("", html);
}

// -- mixed child types --

test "element with all four child node types" {
    const node = ztree.element("div", &.{}, &.{
        ztree.text("escaped &"),
        ztree.raw("<br>"),
        ztree.fragment(&.{ztree.text("frag")}),
        ztree.element("span", &.{}, &.{ztree.text("child")}),
    });
    const html = try renderToString(node);
    defer testing.allocator.free(html);
    try testing.expectEqualStrings("<div>escaped &amp;<br>frag<span>child</span></div>", html);
}

// -- framework attributes (htmx, alpine, stimulus, hyperscript, vue) --
// These all use the same attr rendering code path. One combined test
// proves arbitrary attr keys/values work — no per-framework tests needed.

test "framework attrs — hx-*, x-*, @, :, data-*, v-*, _" {
    const node = ztree.element("div", &.{
        ztree.attr("hx-post", "/api"),
        ztree.attr("hx-swap", "outerHTML"),
        ztree.attr("hx-vals", "{\"a\":\"b&c\"}"),
        ztree.attr("x-data", "{ open: false }"),
        ztree.attr("x-show", "open"),
        ztree.attr("x-transition", null),
        ztree.attr("@click", "open = !open"),
        ztree.attr(":class", "open && 'active'"),
        ztree.attr("data-controller", "hello"),
        ztree.attr("data-action", "click->hello#greet"),
        ztree.attr("v-if", "show"),
        ztree.attr("_", "on click toggle .on"),
    }, &.{});
    const html = try renderToString(node);
    defer testing.allocator.free(html);
    try testing.expectEqualStrings(
        "<div" ++
            " hx-post=\"/api\"" ++
            " hx-swap=\"outerHTML\"" ++
            " hx-vals=\"{&quot;a&quot;:&quot;b&amp;c&quot;}\"" ++
            " x-data=\"{ open: false }\"" ++
            " x-show=\"open\"" ++
            " x-transition" ++
            " @click=\"open = !open\"" ++
            " :class=\"open &amp;&amp; 'active'\"" ++
            " data-controller=\"hello\"" ++
            " data-action=\"click-&gt;hello#greet\"" ++
            " v-if=\"show\"" ++
            " _=\"on click toggle .on\"" ++
            "></div>",
        html,
    );
}

// -- full page render --

test "full page — doctype, head, body, mixed content" {
    const page = ztree.fragment(&.{
        ztree.raw("<!DOCTYPE html>"),
        ztree.element("html", &.{ztree.attr("lang", "en")}, &.{
            ztree.element("head", &.{}, &.{
                ztree.closedElement("meta", &.{ztree.attr("charset", "utf-8")}),
                ztree.element("title", &.{}, &.{ztree.text("Test")}),
                ztree.closedElement("link", &.{ ztree.attr("rel", "stylesheet"), ztree.attr("href", "s.css") }),
                ztree.element("script", &.{ztree.attr("src", "app.js")}, &.{}),
                ztree.element("style", &.{}, &.{ztree.raw("body{margin:0}")}),
            }),
            ztree.element("body", &.{}, &.{
                ztree.element("h1", &.{}, &.{ztree.text("A & B")}),
                ztree.closedElement("hr", &.{}),
                ztree.closedElement("img", &.{ ztree.attr("src", "pic.jpg"), ztree.attr("alt", "Photo") }),
                ztree.raw("<!-- comment -->"),
                ztree.element("script", &.{}, &.{ztree.raw("console.log('hi')")}),
            }),
        }),
    });
    const html = try renderToString(page);
    defer testing.allocator.free(html);
    try testing.expectEqualStrings(
        "<!DOCTYPE html>" ++
            "<html lang=\"en\">" ++
            "<head>" ++
            "<meta charset=\"utf-8\">" ++
            "<title>Test</title>" ++
            "<link rel=\"stylesheet\" href=\"s.css\">" ++
            "<script src=\"app.js\"></script>" ++
            "<style>body{margin:0}</style>" ++
            "</head>" ++
            "<body>" ++
            "<h1>A &amp; B</h1>" ++
            "<hr>" ++
            "<img src=\"pic.jpg\" alt=\"Photo\">" ++
            "<!-- comment -->" ++
            "<script>console.log('hi')</script>" ++
            "</body>" ++
            "</html>",
        html,
    );
}
