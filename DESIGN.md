# ztree-html — Design

HTML renderer for ztree. Delegates tree traversal to `ztree.renderWalk`, implements HTML serialisation via callbacks, and provides a small allocator-bound builder for ergonomic HTML `ztree.Node` construction.

---

## API

| API | Signature | Description |
|-----|-----------|-------------|
| `init` | `(allocator: std.mem.Allocator) Html` | Create an allocator-bound HTML builder. |
| `render` | `(node: Node, writer: *std.Io.Writer) std.Io.Writer.Error!void` | Write HTML to a Zig 0.16 writer. |
| `doctype` | `Node` | Raw `<!DOCTYPE html>` node. |
| `ztree` | module | Re-exported ztree dependency used by ztree-html. |

`Html` methods:

| Method | Description |
|--------|-------------|
| `el(tag, attrs, children)` | Allocating element constructor using the bound allocator. HTML void elements are closed automatically. |
| `fragment(children)` | Allocating fragment constructor using the bound allocator. |
| `document(attrs, children)` | `doctype` plus `<html attrs>children</html>`. |

Requires Zig 0.16.0 or newer and ztree 2.x.

```zig
const html = @import("ztree-html");
const ztree = html.ztree;

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
try html.render(page, &writer);
```

The builder returns ordinary `ztree.Node` values from the re-exported `html.ztree` module. Builder allocations are caller-owned; use an arena or request-scoped allocator when building a page tree and release that region after rendering. Existing ztree APIs remain supported:

```zig
try html.render(ztree_node, &writer);
```

---

## Architecture

`render` creates an `HtmlRenderer` adapter and passes it to `ztree.renderWalk`. The walk lives in ztree — it handles recursion, fragment transparency, and child iteration. The adapter implements four callbacks:

| Callback | Responsibility |
|----------|----------------|
| `elementOpen` | Write `<tag attrs>` via `writeOpenTag`, return `.@"continue"` |
| `elementClose` | Write `</tag>` via `writeCloseTag` (skipped for void elements) |
| `onText` | Write escaped text via `writeEscaped` |
| `onRaw` | Write content as-is |

The `Html` builder is intentionally thin. It binds an allocator once and delegates to ztree constructors. `el` chooses `ztree.closedElement` for HTML void elements and `ztree.element` otherwise. `document` allocates a two-node fragment containing `doctype` and an `html` element.

The writing logic lives in pure standalone functions — the adapter is a thin shim with one-liner delegations. All output goes through Zig 0.16's `std.Io.Writer` interface.

---

## Rendering rules

### Elements

- Open tag: `<tag attrs>`
- Close tag: `</tag>`
- `Html.el` creates closed nodes automatically for HTML void elements (`meta`, `br`, `img`, etc.).
- Pass `.{}` as children for void elements; children passed to `Html.el` for void tags are not rendered.
- Non-void elements get both open and close tags, even when children is empty: `<div></div>`.
- Void elements are additionally guarded in `writeCloseTag` — if a void tag reaches `elementClose`, the close tag is suppressed.

### Void elements (HTML5)

`area`, `base`, `br`, `col`, `embed`, `hr`, `img`, `input`, `link`, `meta`, `source`, `track`, `wbr`

### Text

Escaped before writing. Characters replaced:

| Char | Replacement |
|------|-------------|
| `&`  | `&amp;`     |
| `<`  | `&lt;`      |
| `>`  | `&gt;`      |

### Raw

Written as-is. No escaping. User is responsible for safety.

### Attributes

Written as ` key="value"` after the tag name. Value characters replaced:

| Char | Replacement |
|------|-------------|
| `&`  | `&amp;`     |
| `<`  | `&lt;`      |
| `>`  | `&gt;`      |
| `"`  | `&quot;`    |

Boolean attributes (value is `null`) are written as ` key` with no value.

### Fragments

Transparent — children are rendered directly, no wrapping tag.

---

## Design decisions

**Allocator-bound builder instead of app-side helpers.** Zig cannot provide Maud's `html!` macro syntax. Binding the allocator once gives the practical ergonomic win while keeping construction honest: callers write `h.el(...)` instead of passing `allocator` into every ztree constructor.

**One element constructor.** `Html.el` is the only allocator-bound element constructor. HTML void-element knowledge belongs to ztree-html, so callers do not have to choose between `element` and `closed` for normal HTML authoring.

**Builder returns ztree nodes.** The builder does not create a second markup type. It produces ordinary `ztree.Node` values, so natural ztree component composition remains intact.

**Caller-owned tree allocations.** `Html` binds, but does not own, an allocator. Constructed nodes may contain allocator-owned slices. ztree-html provides no recursive node destructor; callers should use an arena/region allocator for page construction or otherwise free owned ztree slices according to ztree's ownership rules.

**Explicit fallibility.** `Html.el`, `fragment`, and `document` allocate, so they return `!Node`. The repeated `try` is the Zig cost of constructing real nodes eagerly rather than a separate no-allocation markup description.

**`renderWalk` delegation.** Tree traversal is ztree's responsibility. ztree-html only owns HTML serialisation — escaping, void elements, open/close tags. The `HtmlRenderer` adapter connects the two.

**Zig 0.16 `std.Io.Writer`.** The public renderer accepts `*std.Io.Writer` directly. Callers choose the sink — file, socket, fixed buffer, allocating writer — and pass its `std.Io.Writer` pointer.

**No renderer-owned allocations.** `render` streams directly to the caller's writer. Tree construction may allocate before rendering; rendering itself does not allocate and does not flush.

**No pretty-printing.** Minified output only. Indentation is a presentation concern — add it in a separate pass or a different renderer if needed.

**No validation.** The renderer does not check whether arbitrary tags, attributes, or children are valid HTML. ztree-html renders what it's given, with HTML void tags constructed as closed elements by `Html.el`. Validation is a separate concern.

---

## File structure

```
ztree-html/
├── build.zig
├── build.zig.zon
├── src/
│   └── root.zig     # builder, render, escaping, void elements — single file
├── DESIGN.md
├── README.md
├── AGENTS.md
├── LICENSE
└── .gitignore
```

Single source file. The renderer is small — splitting it adds indirection without value.
