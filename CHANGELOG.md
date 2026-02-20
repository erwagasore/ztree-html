# Changelog

## [0.1.0] — 2026-02-20

### Features

- HTML renderer for ztree: `render(node, writer)` walks a Node tree and writes minified HTML to any writer.
- Text escaping (`&`, `<`, `>`) and attribute value escaping (`&`, `<`, `>`, `"`).
- Boolean attribute support (null value renders key only).
- All 13 HTML5 void elements handled — no closing tag regardless of construction method.
- Fragment transparency and `none()` for conditional rendering.
