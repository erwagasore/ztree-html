# AGENTS — ztree-html

Operating rules for humans + AI.

## Workflow

- Never commit to `main`/`master`.
- Always start on a new branch.
- Only push after the user approves.
- Merge via PR.

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/).

- fix → patch
- feat → minor
- feat! / BREAKING CHANGE → major
- chore, docs, refactor, test, ci, style, perf → no version change

## Releases

- Semantic versioning.
- Versions derived from Conventional Commits.
- Release performed locally via `/create-release` (no CI required).
- Manifest (if present) is source of truth.
- Tags: vX.Y.Z

## Repo map

- `LICENSE` — MIT licence
- `.gitignore` — Zig build artefacts exclusions
- `build.zig` — Zig build configuration
- `build.zig.zon` — Zig package manifest (depends on ztree)
- `DESIGN.md` — renderer design and checklist
- `src/` — library source
  - `root.zig` — public API: `render(node, writer)`

## Merge strategy

- Prefer squash merge.
- PR title must be a valid Conventional Commit.

## Definition of done

- Works locally.
- Tests updated if behaviour changed.
- CHANGELOG updated when user-facing.
- No secrets committed.

## Orientation

- **Entry point**: `src/root.zig` — public API.
- **Domain**: HTML renderer for ztree. Walks a `Node` tree and writes HTML to any writer.
- **Language**: Zig (0.15.x). Depends on `ztree` and `std`.
