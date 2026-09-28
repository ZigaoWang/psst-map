# Notes for Claude Code

- Adding or editing places: follow CONTENT_GUIDE.md exactly, then run `python3 scripts/validate_content.py --online` and fix every error before committing.
- Never guess coordinates. Never convert coordinates to GCJ-02 in the data files; the app handles China at runtime (see README).
- Writing rules for everything (UI text, code, comments, docs, content): US English, no em dashes or en dashes, no marketing or machine-sounding language.
- Commits: small and frequent, Conventional Commits without a scope (`feat: ...`, `fix: ...`). `style:` is only for formatting. No co-author lines.
- After changing `project.yml`, run `xcodegen generate` and commit the regenerated project.
- Debug launch arguments for screenshots: `-onboarding.completed YES`, `-debug.tab map|feed|saved`, `-debug.place <areaId/spotId>`, `-debug.area <areaId>`, `-debug.detent large`, `-debug.allPOI YES`.
