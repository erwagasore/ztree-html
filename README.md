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
const element = ztree.element;
const closedElement = ztree.closedElement;
const text = ztree.text;
const attr = ztree.attr;

const page = element("html", &.{attr("lang", "en")}, &.{
    element("head", &.{}, &.{
        element("title", &.{}, &.{text("Hello")}),
        closedElement("meta", &.{attr("charset", "utf-8")}),
    }),
    element("body", &.{}, &.{
        element("h1", &.{}, &.{text("Hello, world!")}),
    }),
});

// Write to any writer (file, socket, buffer):
try ztree_html.render(page, writer);
```

Output:

```html
<html lang="en"><head><title>Hello</title><meta charset="utf-8"></head><body><h1>Hello, world!</h1></body></html>
```

## API

### `render`

```zig
fn render(node: ztree.Node, writer: anytype) !void
```

Writes HTML for the given node tree to `writer`. The writer can be any type
with `writeAll` and `writeByte` methods (`*std.Io.Writer`, buffered writer, etc.).

**Behaviour:**

- **Text nodes** — escaped: `&` → `&amp;`, `<` → `&lt;`, `>` → `&gt;`
- **Raw nodes** — written as-is, no escaping
- **Attributes** — values escaped: `&` `<` `>` `"`. Boolean attributes (null value) written as key only
- **Void elements** (`br`, `hr`, `img`, `meta`, etc.) — no closing tag, regardless of how the node was constructed
- **Non-void elements** — always get a closing tag, even when empty: `<div></div>`
- **Fragments** — transparent, children rendered directly

## License

MIT
