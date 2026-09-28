# Psst

A map of the surprising things about specific places: the station named after a pub, the roundabout with a second roundabout underneath it, the hotel that used to be a warehouse. Browse it on a map or swipe through it like a feed.

Native iOS (SwiftUI and MapKit), iOS 17 and later, iPhone and iPad. On the home screen the app is called "Psst".

## Running it

```
brew install xcodegen
xcodegen generate              # the Xcode project is generated, not committed
open PsstMap.xcodeproj
```

Put the area files in `Content/areas/` before building: from a checkout of `psst-content` next to this one, run `python3 scripts/publish.py` there. Without them the app builds and runs, but shows its "couldn't load places" screen, and the content tests skip.

Run the `PsstMap` scheme. Tests: `xcodebuild test -project PsstMap.xcodeproj -scheme PsstMap -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.

## How it's put together

- `Content/areas/`: where the area files go at build time. They are bundled into the app; there is no server. The files themselves live in the `psst-content` repository (see "Content" below).
- `PsstMap/Model`: the decoded content (`Area`, `Spot`, `Fact`) and the `Catalog` the app browses.
- `PsstMap/Services`: content loading, saved places, feed history, location, pictures (`SpotVisuals`), and China map handling (`ChinaCoordinates`, `MapDatum`).
- `PsstMap/Features`: the map, the feed, the place detail, saved places, about, and the welcome screen.
- `PsstMap/Design`: colors, badges, and shared components.

### Maps in mainland China

Content always stores WGS-84 coordinates, which is what Wikidata and OpenStreetMap use. When Apple Maps uses its China map provider (in practice, on devices in mainland China), it draws mainland China in GCJ-02, which is offset by a few hundred meters, so WGS-84 pins would land in the wrong place. Outside China, Apple Maps draws China in WGS-84.

There's no public API that says which one is active, so `MapDatum` asks MapKit to find a landmark whose true position is known (the Oriental Pearl Tower) and checks which system the answer comes back in. It does this at launch and whenever the app becomes active, and remembers the answer. Every coordinate that goes to MapKit goes through `Place.mapCoordinate`, which shifts mainland China coordinates only when needed. Hong Kong, Macau, and Taiwan are never shifted. Nothing in the app depends on services that are blocked in mainland China.

### Pictures

Each place gets a picture from Apple: a Look Around street view for small things (a statue, a door) and a pitched 3D map for anything larger, since Look Around tends to face a blank wall when pointed at a building. The place detail view is interactive and offers both where Look Around exists. Pictures are cached on disk. If none can be loaded, a designed placeholder in the place's color is shown.

### Room to grow

Notifications about nearby places aren't built yet. When they are, `Catalog.places(near:within:)` already finds places around a WGS-84 location, place ids (`areaId/spotId`) are stable by rule, and `LocationService` is isolated from the UI.

## Icon

`python3 scripts/make_icon.py` redraws the app icon (light, dark, and tinted variants). It needs Pillow.

## Content

The places and facts are a separate work with their own scope and license, kept in the `psst-content` repository: the area files, the content guide (format, research rules, checklist), the validator, and the research tools. `python3 scripts/publish.py` there validates everything and syncs it into this repository's `Content/areas/`, which git ignores. The app reads whatever files are there, so new content needs no code changes. The format's rules for compatibility (unknown categories and kinds, broken entries) are described in `PsstMap/Model/Content.swift`.
