# Psst

A map of the surprising things about specific places: the station named after a pub, the roundabout with a second roundabout underneath it, the hotel that used to be a warehouse. Browse it on a map or swipe through it like a feed.

Native iOS (SwiftUI and MapKit), iOS 17 and later, iPhone and iPad. On the home screen the app is called "Psst".

## Running it

```
brew install xcodegen          # only needed if you change project.yml
xcodegen generate
open PsstMap.xcodeproj
```

Run the `PsstMap` scheme. Tests: `xcodebuild test -project PsstMap.xcodeproj -scheme PsstMap -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.

## How it's put together

- `Content/areas/*.json`: all the places and facts, one file per area, bundled with the app. There is no server. The format, the research rules, and the checklist are in [CONTENT_GUIDE.md](CONTENT_GUIDE.md).
- `scripts/validate_content.py`: checks the content files. Run it before every commit that touches content; `--online` also re-checks every coordinate against Wikidata or OpenStreetMap.
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
