# Notes for Claude Code

- Places and facts live in the separate `psst-content` repository, with their own guide, validator, and tools. Never add or edit area files here; `Content/areas/` is filled by `publish.py` from that repository and ignored by git.
- Never guess coordinates. Never convert coordinates to GCJ-02 in the data files; the app handles China at runtime (see README).
- Writing rules for everything (UI text, code, comments, docs, content): US English, no em dashes or en dashes, no marketing or machine-sounding language.
- Commits: small and frequent, Conventional Commits without a scope (`feat: ...`, `fix: ...`). `style:` is only for formatting. No co-author lines.
- The Xcode project is generated and not committed. After changing `project.yml`, run `xcodegen generate`.
- Debug launch arguments for screenshots: `-onboarding.completed YES`, `-debug.tab map|feed|saved`, `-debug.place <areaId/spotId>`, `-debug.area <areaId>`, `-debug.detail YES`, `-debug.allPOI YES`.
