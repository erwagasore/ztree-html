# Changelog

## [0.3.1] — 2026-03-08

### Other

- Upgrade ztree dependency to v1.0.0 — adapt `elementOpen` to return `WalkAction` (always `.@"continue"`).

## [0.3.0] — 2026-03-06

### Features

- Upgrade ztree dependency to v0.9.0 — adopt tuple attrs for ergonomic runtime/dynamic attribute construction and closed-element semantics from `renderWalk`.

### Other

- Upgrade ztree dependency to v0.5.0.
- Sync AGENTS.md repo-derived sections, add docs/index.md.

## [0.2.0] — 2026-03-05

### Breaking Changes

- Upgrade ztree dependency from v0.2.0 to v0.4.0 with new allocating API.
- Refactor `render()` to delegate tree traversal to `ztree.renderWalk`.

### Other

- Merge `writeEscapedText`/`writeEscapedAttr` into single `writeEscaped` with comptime flag.
- Deduplicate `build.zig` module definition — tests reuse `lib_mod`.
- Update README usage example for ztree v0.4 API.
- Update DESIGN.md to reflect renderWalk architecture.

## [0.1.0] — 2026-02-20

### Features

- HTML renderer for ztree: `render(node, writer)` walks a Node tree and writes minified HTML to any writer.
- Text escaping (`&`, `<`, `>`) and attribute value escaping (`&`, `<`, `>`, `"`).
- Boolean attribute support (null value renders key only).
- All 13 HTML5 void elements handled — no closing tag regardless of construction method.
- Fragment transparency and `none()` for conditional rendering.
