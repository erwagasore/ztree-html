# ztree-html

HTML renderer for [ztree](https://github.com/erwagasore/ztree). Build HTML `ztree.Node` trees with an allocator-bound helper, then stream minified HTML to any Zig writer.

Requires Zig 0.16.0 or newer and ztree 2.x. Rendering streams directly to the caller's writer, does not allocate, and works with trees produced by `ztree.TreeBuilder`.

## Install

```bash
zig fetch --save git+https://github.com/erwagasore/ztree-html.git#main
```

In your `build.zig`:

```zig
const ztree_html_dep = b.dependency("ztree-html", .{
    .target = target,
    .optimize = optimize,
});
my_module.addImport("ztree-html", ztree_html_dep.module("ztree-html"));
```

## Usage

```zig
const std = @import("std");
const html = @import("ztree-html");
const ztree = html.ztree;

var arena = std.heap.ArenaAllocator.init(a);
defer arena.deinit();

const h = html.init(arena.allocator());
const page = try h.document(.{ .lang = "en" }, .{
    try h.el("head", .{}, .{
        try h.el("meta", .{ .charset = "utf-8" }, .{}),
        try h.el("title", .{}, .{ztree.text("Hello")}),
    }),
    try h.el("body", .{}, .{
        try h.el("h1", .{}, .{ztree.text("Hello, world!")}),
    }),
});

// Write to any Zig 0.16 std.Io.Writer (file, socket, buffer):
var out: std.Io.Writer.Allocating = .init(a);
defer out.deinit();

try html.render(page, &out.writer);
const html = try out.toOwnedSlice();
defer a.free(html);
```

Output:

```html
<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><title>Hello</title></head><body><h1>Hello, world!</h1></body></html>
```

`h.el` recognizes HTML void elements (`meta`, `br`, `img`, etc.) and creates closed nodes automatically. Pass `.{}` for their children; children passed to void elements are not rendered.

Builder allocations are caller-owned. Prefer an arena or request-scoped allocator for constructed trees, then free the whole region when the page/response is done. `render` itself does not allocate and does not flush the writer. If you pass a buffered file/socket writer, flush it after rendering when you need the bytes committed.

## Framework integration

The core API is writer-based, so framework adapters stay small and explicit:

```zig
const html = @import("ztree-html");
const ztree = html.ztree;

pub fn handler(req: *Request, res: *Response) !void {
    const h = html.init(req.arena);
    const page = try h.document(.{ .lang = "en" }, .{
        try h.el("head", .{}, .{
            try h.el("meta", .{ .charset = "utf-8" }, .{}),
            try h.el("title", .{}, .{ztree.text("Rwagasore")}),
        }),
        try h.el("body", .{}, .{
            try h.el("h1", .{}, .{ztree.text("Rwagasore")}),
        }),
    });

    res.content_type = .HTML;
    try html.render(page, &res.buffer.writer);
}
```

Use the content-type field or writer shape required by your framework; `ztree-html` only requires a `std.Io.Writer`.

## Safety

Text content and attribute values are escaped. Raw nodes, tag names, and attribute names are written as provided. Use trusted tag and attribute names; validation is outside this renderer's scope.
