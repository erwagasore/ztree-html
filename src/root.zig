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
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const node = try ztree.element(a, "div", .{ .title = "a & b < c > d \"e\"" }, .{});
    const html = try renderToString(node);
    defer testing.allocator.free(html);
    try testing.expectEqualStrings("<div title=\"a &amp; b &lt; c &gt; d &quot;e&quot;\"></div>", html);
}

test "boolean attribute — key with no value" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const node = try ztree.closedElement(a, "input", .{ .type = "checkbox", .checked = {}, .disabled = {} });
    const html = try renderToString(node);
    defer testing.allocator.free(html);
    try testing.expectEqualStrings("<input type=\"checkbox\" checked disabled>", html);
}

// -- void elements --

test "all 13 void elements — no closing tag" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const void_tags = [_][]const u8{
        "area", "base", "br", "col", "embed", "hr", "img",
        "input", "link", "meta", "source", "track", "wbr",
    };
    for (void_tags) |tag| {
        const html = try renderToString(try ztree.closedElement(a, tag, .{}));
        defer testing.allocator.free(html);
        try testing.expect(html.len > 2);
        try testing.expect(std.mem.indexOf(u8, html, "</") == null);
    }
}

test "void element ignores children" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const html = try renderToString(try ztree.element(a, "br", .{}, .{ ztree.text("oops") }));
    defer testing.allocator.free(html);
    try testing.expectEqualStrings("<br>", html);
}

// -- non-void elements --

test "non-void empty element — always gets closing tag" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const html = try renderToString(try ztree.element(arena.allocator(), "div", .{}, .{}));
    defer testing.allocator.free(html);
    try testing.expectEqualStrings("<div></div>", html);
}

test "closedElement on non-void tag — still gets closing tag" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const html = try renderToString(try ztree.closedElement(arena.allocator(), "script", .{ .src = "app.js" }));
    defer testing.allocator.free(html);
    try testing.expectEqualStrings("<script src=\"app.js\"></script>", html);
}

test "element with attrs and children" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const node = try ztree.element(a, "div", .{ .class = "card" }, .{ ztree.text("hello") });
    const html = try renderToString(node);
    defer testing.allocator.free(html);
    try testing.expectEqualStrings("<div class=\"card\">hello</div>", html);
}

test "nested elements — correct open/close order" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const node = try ztree.element(a, "ul", .{}, .{
        try ztree.element(a, "li", .{}, .{ ztree.text("one") }),
        try ztree.element(a, "li", .{}, .{ ztree.text("two") }),
    });
    const html = try renderToString(node);
    defer testing.allocator.free(html);
    try testing.expectEqualStrings("<ul><li>one</li><li>two</li></ul>", html);
}

// -- fragment --

test "fragment — children rendered without wrapper" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const node = try ztree.fragment(a, .{
        ztree.text("a"),
        try ztree.element(a, "b", .{}, .{ ztree.text("bold") }),
        ztree.text("c"),
    });
    const html = try renderToString(node);
    defer testing.allocator.free(html);
    try testing.expectEqualStrings("a<b>bold</b>c", html);
}

test "nested fragments — transparent" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const node = try ztree.fragment(a, .{
        try ztree.fragment(a, .{ ztree.text("a") }),
        try ztree.fragment(a, .{ ztree.text("b") }),
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
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const node = try ztree.element(a, "div", .{}, .{
        ztree.text("escaped &"),
        ztree.raw("<br>"),
        try ztree.fragment(a, .{ ztree.text("frag") }),
        try ztree.element(a, "span", .{}, .{ ztree.text("child") }),
    });
    const html = try renderToString(node);
    defer testing.allocator.free(html);
    try testing.expectEqualStrings("<div>escaped &amp;<br>frag<span>child</span></div>", html);
}

// -- framework attributes (htmx, alpine, stimulus, hyperscript, vue) --
// These all use the same attr rendering code path. One combined test
// proves arbitrary attr keys/values work — no per-framework tests needed.

test "framework attrs — hx-*, x-*, @, :, data-*, v-*, _" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Build the attrs slice for keys that aren't valid identifiers
    const attrs = try a.alloc(Attr, 12);
    attrs[0]  = ztree.attr("hx-post",          "/api");
    attrs[1]  = ztree.attr("hx-swap",          "outerHTML");
    attrs[2]  = ztree.attr("hx-vals",          "{\"a\":\"b&c\"}");
    attrs[3]  = ztree.attr("x-data",           "{ open: false }");
    attrs[4]  = ztree.attr("x-show",           "open");
    attrs[5]  = ztree.attr("x-transition",     null);
    attrs[6]  = ztree.attr("@click",           "open = !open");
    attrs[7]  = ztree.attr(":class",           "open && 'active'");
    attrs[8]  = ztree.attr("data-controller",  "hello");
    attrs[9]  = ztree.attr("data-action",      "click->hello#greet");
    attrs[10] = ztree.attr("v-if",             "show");
    attrs[11] = ztree.attr("_",                "on click toggle .on");
    const node = try ztree.element(a, "div", attrs, .{});
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
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const page = try ztree.fragment(a, .{
        ztree.raw("<!DOCTYPE html>"),
        try ztree.element(a, "html", .{ .lang = "en" }, .{
            try ztree.element(a, "head", .{}, .{
                try ztree.closedElement(a, "meta", .{ .charset = "utf-8" }),
                try ztree.element(a, "title", .{}, .{ ztree.text("Test") }),
                try ztree.closedElement(a, "link", .{ .rel = "stylesheet", .href = "s.css" }),
                try ztree.element(a, "script", .{ .src = "app.js" }, .{}),
                try ztree.element(a, "style", .{}, .{ ztree.raw("body{margin:0}") }),
            }),
            try ztree.element(a, "body", .{}, .{
                try ztree.element(a, "h1", .{}, .{ ztree.text("A & B") }),
                try ztree.closedElement(a, "hr", .{}),
                try ztree.closedElement(a, "img", .{ .src = "pic.jpg", .alt = "Photo" }),
                ztree.raw("<!-- comment -->"),
                try ztree.element(a, "script", .{}, .{ ztree.raw("console.log('hi')") }),
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
