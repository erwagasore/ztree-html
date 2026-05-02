# ztree-html

HTML renderer for [ztree](https://github.com/erwagasore/ztree). One function — walks a tree, writes HTML.

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
const ztree = @import("ztree");
const ztree_html = @import("ztree-html");

const page = try ztree.fragment(a, .{
    ztree.raw("<!DOCTYPE html>"),
    try ztree.element(a, "html", .{ .lang = "en" }, .{
        try ztree.element(a, "head", .{}, .{
            try ztree.closedElement(a, "meta", .{ .charset = "utf-8" }),
            try ztree.element(a, "title", .{}, .{ ztree.text("Hello") }),
        }),
        try ztree.element(a, "body", .{}, .{
            try ztree.element(a, "h1", .{}, .{ ztree.text("Hello, world!") }),
        }),
    }),
});

// Write to any Zig 0.16 std.Io.Writer (file, socket, buffer):
var out: std.Io.Writer.Allocating = .init(a);
defer out.deinit();

try ztree_html.render(page, &out.writer);
const html = try out.toOwnedSlice();
defer a.free(html);
```

`render` does not flush the writer. If you pass a buffered file/socket writer,
flush it after rendering when you need the bytes committed.

## Safety

Text content and attribute values are escaped. Raw nodes, tag names, and
attribute names are written as provided. Use trusted tag and attribute names;
validation is outside this renderer's scope.

Output:

```html
<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><title>Hello</title></head><body><h1>Hello, world!</h1></body></html>
```
