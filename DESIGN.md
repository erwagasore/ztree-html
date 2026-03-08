# ztree-html — Design

HTML renderer for ztree. Delegates tree traversal to `ztree.renderWalk`
and implements HTML serialisation via callbacks.

---

## API

One function.

| Function | Signature | Description |
|----------|-----------|-------------|
| `render` | `(node: Node, writer: anytype) !void` | Write HTML to any writer. |

```zig
const ztree_html = @import("ztree-html");

// Write to any writer (file, buffer, socket):
try ztree_html.render(page, writer);
```

---

## Architecture

`render` creates an `HtmlRenderer` adapter and passes it to
`ztree.renderWalk`. The walk lives in ztree — it handles recursion,
fragment transparency, and child iteration. The adapter implements four
callbacks:

| Callback | Responsibility |
|----------|----------------|
| `elementOpen` | Write `<tag attrs>` via `writeOpenTag`, return `.@"continue"` |
| `elementClose` | Write `</tag>` via `writeCloseTag` (skipped for void elements) |
| `onText` | Write escaped text via `writeEscaped` |
| `onRaw` | Write content as-is |

The writing logic lives in pure standalone functions — the adapter is a
thin shim with one-liner delegations.

---

## Rendering rules

### Elements

- Open tag: `<tag attrs>`
- Close tag: `</tag>`
- Closed elements (`closedElement()`) get an open tag only — `renderWalk`
  skips children and never calls `elementClose`. Use for void elements
  and any element that should have no closing tag.
- Non-closed elements (`element()`) always get both open and close tags,
  even when children is empty: `<div></div>`.
- Void elements (`br`, `hr`, `img`, `meta`, etc.) are additionally guarded
  in `writeCloseTag` — if `element()` is used on a void tag,
  `elementClose` is called but the close tag is suppressed.

### Void elements (HTML5)

`area`, `base`, `br`, `col`, `embed`, `hr`, `img`, `input`, `link`,
`meta`, `source`, `track`, `wbr`

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

**`renderWalk` delegation.** Tree traversal is ztree's responsibility.
ztree-html only owns HTML serialisation — escaping, void elements,
open/close tags. The `HtmlRenderer` adapter is a thin shim connecting
the two.

**`anytype` writer.** Matches idiomatic Zig — `std.fmt.format`,
`std.json.stringify`, and most std serializers accept `anytype` writer.
Avoids forcing a specific writer type on callers.

**Void element awareness.** HTML has strict rules about void elements.
Emitting `<br></br>` is invalid. Since ztree v0.7.0, `renderWalk` skips
`elementClose` for closed elements — so properly constructed trees
(`closedElement("br", ...)`) never reach `writeCloseTag`. The void element
map remains as a safety net: if someone uses `element("br", ...)` instead,
`elementClose` is called but the close tag is suppressed.

**No pretty-printing.** Minified output only. Indentation is a presentation
concern — add it in a separate pass or a different renderer if needed. One
way to do a thing.

**No validation.** The renderer does not check whether tags or attributes
are valid HTML. ztree-html renders what it's given. Validation is a separate
concern.

---

## File structure

```
ztree-html/
├── build.zig
├── build.zig.zon
├── src/
│   └── root.zig     # render, escaping, void elements — single file
├── DESIGN.md
├── README.md
├── AGENTS.md
├── LICENSE
└── .gitignore
```

Single source file. The renderer is small — splitting it adds indirection
without value.
