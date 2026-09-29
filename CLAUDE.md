# Notes for Claude Code

- Places and facts live in a database managed by the separate `psst-content` repository, with its own guide and tools. Never add or edit content here. `Content/v2/` holds the snapshot the app ships with; `uv run psst bundle` in `psst-content` fills it, and git ignores it.
- Never guess coordinates. Never convert coordinates to GCJ-02 in content; the app handles China at runtime (see README).
- The content format (version 2) is decoded in `PsstMap/Model/Content.swift`. Keep decoding forgiving: new optional fields only, unknown values fall back, broken entries are skipped. Anything incompatible is format 3, agreed with `psst-content` first.
- Writing rules for everything (UI text, code, comments, docs, content): US English, no em dashes or en dashes, no marketing or machine-sounding language.
- UI text goes through `Text("...")` or `String(localized:)` and needs a Simplified Chinese translation in `PsstMap/Resources/Localizable.xcstrings`. Story text is English; show it with `Text.story(_:)`.
- Commits: small and frequent, Conventional Commits without a scope (`feat: ...`, `fix: ...`). `style:` is only for formatting. No co-author lines.
- The Xcode project is generated and not committed. After changing `project.yml`, run `xcodegen generate`.
- Debug launch arguments for screenshots: `-onboarding.completed YES`, `-debug.tab map|feed|saved`, `-debug.place <place id>` (a `pl_...` id or an old `areaId/spotId`), `-debug.area <city or neighborhood id>`, `-debug.detail YES`, `-debug.sheet search|key|about`, `-debug.allPOI YES`. `-AppleLanguages "(zh-Hans)"` shows the Chinese interface.
