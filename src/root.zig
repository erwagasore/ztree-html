/// ztree-html — HTML renderer for ztree.
const std = @import("std");
const ztree = @import("ztree");
const Node = ztree.Node;
const Element = ztree.Element;

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

/// Renderer adapter — thin shim connecting renderWalk to the write functions.
fn HtmlRenderer(Writer: type) type {
    return struct {
        writer: Writer,
        pub fn elementOpen(self: *@This(), el: Element) !ztree.WalkAction { try writeOpenTag(self.writer, el); return .@"continue"; }
        pub fn elementClose(self: *@This(), el: Element) !void { try writeCloseTag(self.writer, el); }
        pub fn onText(self: *@This(), content: []const u8) !void { try writeEscaped(self.writer, content, false); }
        pub fn onRaw(self: *@This(), content: []const u8) !void { try self.writer.writeAll(content); }
    };
}

/// Write HTML for a ztree Node to any writer.
pub fn render(node: Node, writer: anytype) !void {
    var renderer: HtmlRenderer(@TypeOf(writer)) = .{ .writer = writer };
    try ztree.renderWalk(&renderer, node);
}

// ── Write functions (pure — data in, output out) ─────────────────────────────

fn writeOpenTag(writer: anytype, el: Element) !void {
    try writer.writeAll("<");
    try writer.writeAll(el.tag);
    for (el.attrs) |a| {
        try writer.writeAll(" ");
        try writer.writeAll(a.key);
        if (a.value) |v| {
            try writer.writeAll("=\"");
            try writeEscaped(writer, v, true);
            try writer.writeAll("\"");
        }
    }
    try writer.writeAll(">");
}

fn writeCloseTag(writer: anytype, el: Element) !void {
    if (void_elements.has(el.tag)) return;
    try writer.writeAll("</");
    try writer.writeAll(el.tag);
    try writer.writeAll(">");
}

fn writeEscaped(writer: anytype, content: []const u8, comptime esc_quot: bool) !void {
    for (content) |c| {
        switch (c) {
            '&' => try writer.writeAll("&amp;"),
            '<' => try writer.writeAll("&lt;"),
            '>' => try writer.writeAll("&gt;"),
            '"' => if (esc_quot) try writer.writeAll("&quot;") else try writer.writeByte(c),
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

// -- non-void elements --

test "non-void empty element — always gets closing tag" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const html = try renderToString(try ztree.element(arena.allocator(), "div", .{}, .{}));
    defer testing.allocator.free(html);
    try testing.expectEqualStrings("<div></div>", html);
}

test "closedElement on non-void tag — no closing tag (closed semantics)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const html = try renderToString(try ztree.closedElement(arena.allocator(), "script", .{ .src = "app.js" }));
    defer testing.allocator.free(html);
    try testing.expectEqualStrings("<script src=\"app.js\">", html);
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
    // Tuple attrs — runtime keys via ztree.attr(), no manual alloc needed
    const node = try ztree.element(a, "div", .{
        ztree.attr("hx-post",          "/api"),
        ztree.attr("hx-swap",          "outerHTML"),
        ztree.attr("hx-vals",          "{\"a\":\"b&c\"}"),
        ztree.attr("x-data",           "{ open: false }"),
        ztree.attr("x-show",           "open"),
        ztree.attr("x-transition",     null),
        ztree.attr("@click",           "open = !open"),
        ztree.attr(":class",           "open && 'active'"),
        ztree.attr("data-controller",  "hello"),
        ztree.attr("data-action",      "click->hello#greet"),
        ztree.attr("v-if",             "show"),
        ztree.attr("_",                "on click toggle .on"),
    }, .{});
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
