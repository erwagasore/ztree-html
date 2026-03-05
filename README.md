# ztree-html

HTML renderer for [ztree](https://github.com/erwagasore/ztree). One function — walks a tree, writes HTML.

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

// Write to any writer (file, socket, buffer):
try ztree_html.render(page, writer);
```

Output:

```html
<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><title>Hello</title></head><body><h1>Hello, world!</h1></body></html>
```
