/// ztree-html — HTML renderer for ztree.
///
/// Architecture:
///   init()       — allocator-bound helper for ergonomic ztree.Node creation.
///   render()     — public entry point, delegates traversal to ztree.renderWalk.
///   HtmlRenderer — struct implementing the renderWalk protocol:
///                    elementOpen / elementClose / onText / onRaw.
///   Leaf writers — pure helpers that serialize tags and escaped text to
///                    Zig 0.16's std.Io.Writer.
const std = @import("std");
pub const ztree = @import("ztree");
const Node = ztree.Node;
const Element = ztree.Element;
const WalkAction = ztree.WalkAction;
const Writer = std.Io.Writer;
const Allocator = std.mem.Allocator;

// ---------------------------------------------------------------------------
// Lookup tables
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// HTML document type declaration.
pub const doctype: Node = ztree.raw("<!DOCTYPE html>");

/// Create an allocator-bound HTML builder.
pub fn init(allocator: Allocator) Html {
    return .{ .allocator = allocator };
}

/// Allocator-bound helper for constructing ztree nodes for HTML output.
///
/// This keeps tree construction declarative while avoiding repeated allocator
/// plumbing. HTML void elements are recognized automatically by `el`.
pub const Html = struct {
    allocator: Allocator,

    /// Build an element node using this builder's allocator.
    ///
    /// HTML void elements (`meta`, `br`, `img`, etc.) are created as closed
    /// nodes automatically. Pass `.{}` for their children; children passed to
    /// void elements are not rendered.
    pub fn el(self: Html, tag: []const u8, attrs: anytype, children: anytype) !Node {
        if (void_elements.has(tag)) return ztree.closedElement(self.allocator, tag, attrs);
        return ztree.element(self.allocator, tag, attrs, children);
    }

    /// Build a fragment using this builder's allocator.
    pub fn fragment(self: Html, children: anytype) !Node {
        return ztree.fragment(self.allocator, children);
    }

    /// Build a complete HTML document: doctype plus `<html attrs>children</html>`.
    ///
    /// The two-root fragment slice (doctype, html) is allocated first with an
    /// errdefer, so if `el` fails partway the slice is freed — matching how
    /// ztree's own constructors stay allocation-failure safe.
    pub fn document(self: Html, attrs: anytype, children: anytype) !Node {
        const roots = try self.allocator.alloc(Node, 2);
        errdefer self.allocator.free(roots);

        roots[0] = doctype;
        roots[1] = try self.el("html", attrs, children);

        return .{ .fragment = roots };
    }
};

/// Write HTML for a ztree Node to a Zig 0.16 `std.Io.Writer`.
///
/// Rendering performs no heap allocation and does not flush. The caller owns
/// the writer and decides when buffered output should be flushed.
pub fn render(node: Node, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    var renderer: HtmlRenderer = .{ .writer = writer };
    try ztree.renderWalk(&renderer, node);
}

// ---------------------------------------------------------------------------
// Renderer — struct implementing the ztree renderWalk protocol
// ---------------------------------------------------------------------------

/// Renderer adapter — thin shim connecting renderWalk to the write functions.
const HtmlRenderer = struct {
    writer: *Writer,

    pub fn elementOpen(self: *HtmlRenderer, el: Element) Writer.Error!WalkAction {
        try writeOpenTag(self.writer, el);
        return .@"continue";
    }

    pub fn elementClose(self: *HtmlRenderer, el: Element) Writer.Error!void {
        try writeCloseTag(self.writer, el);
    }

    pub fn onText(self: *HtmlRenderer, content: []const u8) Writer.Error!void {
        try writeEscaped(self.writer, content, false);
    }

    pub fn onRaw(self: *HtmlRenderer, content: []const u8) Writer.Error!void {
        try self.writer.writeAll(content);
    }
};

// ---------------------------------------------------------------------------
// Leaf writers — write output, never recurse into the tree
// ---------------------------------------------------------------------------

fn writeOpenTag(writer: *Writer, el: Element) Writer.Error!void {
    var tag_open = [_][]const u8{ "<", el.tag };
    try writer.writeVecAll(&tag_open);

    for (el.attrs) |a| {
        if (a.value) |v| {
            var attr_open = [_][]const u8{ " ", a.key, "=\"" };
            try writer.writeVecAll(&attr_open);
            try writeEscaped(writer, v, true);
            try writer.writeAll("\"");
        } else {
            var attr = [_][]const u8{ " ", a.key };
            try writer.writeVecAll(&attr);
        }
    }

    try writer.writeAll(">");
}

fn writeCloseTag(writer: *Writer, el: Element) Writer.Error!void {
    if (void_elements.has(el.tag)) return;

    var tag_close = [_][]const u8{ "</", el.tag, ">" };
    try writer.writeVecAll(&tag_close);
}

fn writeEscaped(writer: *Writer, content: []const u8, comptime escape_quote: bool) Writer.Error!void {
    var unescaped_start: usize = 0;

    for (content, 0..) |c, i| {
        const replacement: []const u8 = switch (c) {
            '&' => "&amp;",
            '<' => "&lt;",
            '>' => "&gt;",
            '"' => if (escape_quote) "&quot;" else continue,
            else => continue,
        };

        if (unescaped_start < i) {
            var escaped = [_][]const u8{ content[unescaped_start..i], replacement };
            try writer.writeVecAll(&escaped);
        } else {
            try writer.writeAll(replacement);
        }
        unescaped_start = i + 1;
    }

    if (unescaped_start < content.len) {
        try writer.writeAll(content[unescaped_start..]);
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;
const TreeBuilder = ztree.TreeBuilder;

fn renderToString(node: Node) ![]const u8 {
    var aw: Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();

    try render(node, &aw.writer);
    return aw.toOwnedSlice();
}

// -- writer integration --

test "render — fixed writer streams without allocation" {
    var buffer: [64]u8 = undefined;
    var writer = Writer.fixed(&buffer);

    try render(ztree.text("a & b < c"), &writer);

    try testing.expectEqualStrings("a &amp; b &lt; c", writer.buffered());
}

test "render — fixed writer reports WriteFailed when full" {
    var buffer: [4]u8 = undefined;
    var writer = Writer.fixed(&buffer);

    try testing.expectError(error.WriteFailed, render(ztree.text("hello"), &writer));
}

// -- allocator-bound builder --

test "Html builder — document binds allocator once" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const h = init(arena.allocator());
    const page = try h.document(.{ .lang = "en" }, .{
        try h.el("head", .{}, .{
            try h.el("meta", .{ .charset = "utf-8" }, .{}),
            try h.el("meta", .{
                .name = "viewport",
                .content = "width=device-width, initial-scale=1",
            }, .{}),
            try h.el("title", .{}, .{ztree.text("Rwagasore")}),
        }),
        try h.el("body", .{}, .{
            try h.el("h1", .{}, .{ztree.text("Rwagasore")}),
            try h.el("p", .{}, .{ztree.text("Design studio taking on work of consequence.")}),
        }),
    });

    const html = try renderToString(page);
    defer testing.allocator.free(html);
    try testing.expectEqualStrings(
        "<!DOCTYPE html>" ++
            "<html lang=\"en\">" ++
            "<head>" ++
            "<meta charset=\"utf-8\">" ++
            "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">" ++
            "<title>Rwagasore</title>" ++
            "</head>" ++
            "<body>" ++
            "<h1>Rwagasore</h1>" ++
            "<p>Design studio taking on work of consequence.</p>" ++
            "</body>" ++
            "</html>",
        html,
    );
}

test "Html builder — fragment raw none and runtime attrs" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const h = init(arena.allocator());
    const show = false;
    const node = try h.fragment(.{
        ztree.raw("<!-- trusted -->"),
        try h.el("div", .{
            ztree.attr("hx-post", "/api"),
            if (show) ztree.attr("data-visible", "true") else null,
        }, .{
            ztree.text("A & B"),
            ztree.none(),
        }),
    });

    const html = try renderToString(node);
    defer testing.allocator.free(html);
    try testing.expectEqualStrings("<!-- trusted --><div hx-post=\"/api\">A &amp; B</div>", html);
}

// -- allocation-failure safety (parity with ztree's own constructors) --

test "document — no leak with testing.allocator" {
    const h = init(testing.allocator);
    const page = try h.document(.{ .lang = "en" }, .{ztree.text("body")});
    // Capture child pointers before freeing the roots slice that references them.
    const html_el = page.fragment[1].element;
    defer testing.allocator.free(html_el.children);
    defer testing.allocator.free(html_el.attrs);
    defer testing.allocator.free(page.fragment);
}

fn documentAllocFailureImpl(a: Allocator) !void {
    const h = init(a);
    // Non-allocating leaf child so the only allocations are document's own:
    // the two-root fragment slice, the html attrs, and the html children.
    const page = try h.document(.{ .lang = "en" }, .{ztree.text("body")});
    const html_el = page.fragment[1].element;
    defer a.free(html_el.children);
    defer a.free(html_el.attrs);
    defer a.free(page.fragment);
}

test "document handles allocation failures" {
    try testing.checkAllAllocationFailures(testing.allocator, documentAllocFailureImpl, .{});
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
        "area",  "base", "br",   "col",    "embed", "hr",  "img",
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
    const node = try ztree.element(a, "div", .{ .class = "card" }, .{ztree.text("hello")});
    const html = try renderToString(node);
    defer testing.allocator.free(html);
    try testing.expectEqualStrings("<div class=\"card\">hello</div>", html);
}

test "nested elements — correct open/close order" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const node = try ztree.element(a, "ul", .{}, .{
        try ztree.element(a, "li", .{}, .{ztree.text("one")}),
        try ztree.element(a, "li", .{}, .{ztree.text("two")}),
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
        try ztree.element(a, "b", .{}, .{ztree.text("bold")}),
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
        try ztree.fragment(a, .{ztree.text("a")}),
        try ztree.fragment(a, .{ztree.text("b")}),
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

// -- producer interop --

test "TreeBuilder interop — multiple text/raw events and closed elements" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var b = TreeBuilder.init(arena.allocator());
    try b.raw("<!DOCTYPE html>");
    try b.open("p", .{ .class = "intro" });
    try b.text("A & ");
    try b.text("<B>");
    try b.raw("<br>");
    try b.close();
    try b.closedElement("hr", .{});

    const html = try renderToString(try b.finish());
    defer testing.allocator.free(html);
    try testing.expectEqualStrings("<!DOCTYPE html><p class=\"intro\">A &amp; &lt;B&gt;<br></p><hr>", html);
}

// -- mixed child types --

test "element with all four child node types" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const node = try ztree.element(a, "div", .{}, .{
        ztree.text("escaped &"),
        ztree.raw("<br>"),
        try ztree.fragment(a, .{ztree.text("frag")}),
        try ztree.element(a, "span", .{}, .{ztree.text("child")}),
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
                try ztree.element(a, "title", .{}, .{ztree.text("Test")}),
                try ztree.closedElement(a, "link", .{ .rel = "stylesheet", .href = "s.css" }),
                try ztree.element(a, "script", .{ .src = "app.js" }, .{}),
                try ztree.element(a, "style", .{}, .{ztree.raw("body{margin:0}")}),
            }),
            try ztree.element(a, "body", .{}, .{
                try ztree.element(a, "h1", .{}, .{ztree.text("A & B")}),
                try ztree.closedElement(a, "hr", .{}),
                try ztree.closedElement(a, "img", .{ .src = "pic.jpg", .alt = "Photo" }),
                ztree.raw("<!-- comment -->"),
                try ztree.element(a, "script", .{}, .{ztree.raw("console.log('hi')")}),
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
