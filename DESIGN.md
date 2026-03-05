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
| `elementOpen` | Write `<tag attrs>` via `writeOpenTag` |
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
- Void elements (`br`, `hr`, `img`, `meta`, etc.) never get a closing tag,
  regardless of whether `element()` or `closedElement()` was used.
- Non-void elements always get a closing tag, even when children is empty:
  `<div></div>`, `<script src="app.js"></script>`.

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
Emitting `<br></br>` is invalid. The renderer knows the 13 HTML5 void
elements and handles them correctly regardless of how the node was
constructed. This is HTML-specific knowledge that belongs here, not in ztree
core.

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
