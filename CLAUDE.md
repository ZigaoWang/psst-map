# Notes for Claude Code

- Adding or editing places: follow CONTENT_GUIDE.md exactly, then run `python3 scripts/validate_content.py --online` and fix every error. Area files live in `Content/areas/` but are never committed to this repository; content is kept and licensed separately.
- Never guess coordinates. Never convert coordinates to GCJ-02 in the data files; the app handles China at runtime (see README).
- Writing rules for everything (UI text, code, comments, docs, content): US English, no em dashes or en dashes, no marketing or machine-sounding language.
- Commits: small and frequent, Conventional Commits without a scope (`feat: ...`, `fix: ...`). `style:` is only for formatting. No co-author lines.
- The Xcode project is generated and not committed. After changing `project.yml`, run `xcodegen generate`.
- Debug launch arguments for screenshots: `-onboarding.completed YES`, `-debug.tab map|feed|saved`, `-debug.place <areaId/spotId>`, `-debug.area <areaId>`, `-debug.detail YES`, `-debug.allPOI YES`.
