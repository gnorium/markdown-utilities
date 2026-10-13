# Repository guidance

This directory is its own Git repository. The parent Gnorium workspace is not a repository; run Git commands here and inspect sibling repositories separately.

- Preserve unrelated working changes. When renaming an internal API, update callers in sibling packages rather than leave obsolete aliases.
- Run focused checks for the changed behavior. Do not run full server/browser suites unless requested.
- Keep build caches and `.build` directories. Diagnose build/toolchain errors before rebuilding; do not wipe caches to troubleshoot.
- Batch related changes before building. Deployment requires an explicit user request; a local build or server restart is not deployment.
- If committing authorized work, omit attribution trailers and push normally after the commit; never force-push.

## Markdown contracts

Rendering is a view of the immutable source, not its replacement. Preserve source characters and line breaks; keep parsed/rendered output separate from edited Markdown.

Honor HTMLBuilder's escape-by-default contract through typed Markdown components. Do not pass rendered strings through text-builder paths or fix their escaping with raw HTML at call sites.
