# Psst

A map of the surprising things about specific places: the station named after a pub, the roundabout with a second roundabout underneath it, the hotel that used to be a warehouse. Browse it on a map or swipe through it like a feed.

Native iOS (SwiftUI and MapKit), iOS 17 and later, iPhone and iPad. On the home screen the app is called "Psst".

## Running it

```
brew install xcodegen
xcodegen generate              # the Xcode project is generated, not committed
open PsstMap.xcodeproj
```

Put a content snapshot in `Content/v2/` before building: from a checkout of `psst-content` next to this one, run `uv run psst bundle` there. It copies what production serves. Without it the app builds and runs, downloads content on first launch if it can, and the content tests skip.

Run the `PsstMap` scheme. Tests: `xcodebuild test -project PsstMap.xcodeproj -scheme PsstMap -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.

## How it's put together

- `Content/v2/`: the content snapshot bundled with the app (see "Content" below). Git ignores it.
- `PsstMap/Model`: the decoded content (`Spot`, `Fact`, `Tag`, cities and areas) and the `Catalog` the app browses, grouped by city and neighborhood.
- `PsstMap/Services`: loading and updating content (`ContentLibrary`, `ContentUpdater`), search (`SearchIndex`), story translation, problem reports, saved places, feed history, location, pictures (`SpotVisuals`) and photos (`PhotoLoader`), and China map handling (`ChinaCoordinates`, `MapDatum`).
- `PsstMap/Features`: the map, search, the feed, the place detail, threads (tags), saved places, settings, and the welcome screen.
- `PsstMap/Design`: colors, badges, and shared components.
- `Vendor/H3`: Uber's H3 library, compiled into the app, so it computes the same map cells as the server.
- `PsstMap/Resources`: assets, the String Catalogs (`Localizable.xcstrings`, `InfoPlist.xcstrings`), and the privacy manifest.

### Languages

Stories are written in English. Each one has a Translate button when the device language isn't English and Apple's on-device translation supports it; translations are cached on the device and never sent anywhere. Place names are shown in the local script and, when known, in the reader's language. Search matches names in any stored language, ignores accents and case, treats Traditional and Simplified Chinese alike, accepts pinyin, and translates the query to English on the device when nothing matches.

The interface is in String Catalogs, in English and Simplified Chinese. To add a language, add it to `Localizable.xcstrings` and `InfoPlist.xcstrings` in Xcode and translate every string; no code changes. Text shown in the UI must go through `Text("...")` or `String(localized:)` so it's extracted.

### Maps in mainland China

Content always stores WGS-84 coordinates, which is what Wikidata and OpenStreetMap use. When Apple Maps uses its China map provider (in practice, on devices in mainland China), it draws mainland China in GCJ-02, which is offset by a few hundred meters, so WGS-84 pins would land in the wrong place. Outside China, Apple Maps draws China in WGS-84.

There's no public API that says which one is active, so `MapDatum` asks MapKit to find a landmark whose true position is known (the Oriental Pearl Tower) and checks which system the answer comes back in. It does this at launch and whenever the app becomes active, and remembers the answer. Every coordinate that goes to MapKit goes through `Place.mapCoordinate`, which shifts mainland China coordinates only when needed. Hong Kong, Macau, and Taiwan are never shifted. Nothing in the app depends on services that are blocked in mainland China.

### Pictures

Each place gets a picture from Apple: a Look Around street view for small things (a statue, a door) and a pitched 3D map for anything larger, since Look Around tends to face a blank wall when pointed at a building. The place detail view is interactive and offers both where Look Around exists. Pictures are cached on disk. If none can be loaded, a designed placeholder in the place's color is shown.

Places with a reviewed photo show it instead: full width at the top of the place page (swipe for more, tap for full screen, with the map one tap away), and in the feed and thumbnails. Photos are freely licensed or the owner's own, hosted as resized copies on the Psst server under `/images/`, and cached on disk. Each one has a credit line that opens its source, alt text for VoiceOver, and a focus point the app keeps in view when it crops. Historic photos show their year. The content pipeline in `psst-content` finds, reviews, and publishes them (its guide, section 13).

### Room to grow

Notifications about nearby places aren't built yet. When they are, `Catalog.places(near:within:)` already finds places around a WGS-84 location, place ids (`pl_...`) are permanent, and `LocationService` is isolated from the UI.

## Icon

`python3 scripts/make_icon.py` redraws the app icon (light, dark, and tinted variants). It needs Pillow.

## Content

The places and facts are a separate work with their own scope and license. They live in a database managed by the `psst-content` repository, which publishes them as content format 2: a manifest and one pack per city, named by their hashes, at `https://psst.zigao.wang/content/production/v2/`.

- The app ships with a snapshot of production (`uv run psst bundle` in `psst-content`), so it works offline from the first launch.
- In the background it checks the manifest and downloads only packs that changed. Each pack is checked against its hash and decoded before the new set is switched in, and anything that fails keeps the last good version (`ContentUpdater`, `ContentLibrary`).
- Place ids are permanent. Saved places and feed history from before the move (`areaId/spotId`) are rewritten to them through the `legacyIds` map.
- Decoding is forgiving so newer content never breaks an older app; the rules are at the top of `PsstMap/Model/Content.swift`. An incompatible format would be published as `v3` beside `v2`.
- In debug builds, set the `debug.contentBaseURL` default to point the app at another server.

"Report a problem" on a story sends the story id, a reason, and an optional note to `https://psst.zigao.wang/api/v1/reports`, queued on the device until it's online. "Help choose new areas" (on by default, off in Settings) sends the rounded center of an empty map area. Both are described in the privacy policy and declared in `PrivacyInfo.xcprivacy`.

## Author

Made by [Zigao Wang](https://www.zigao.wang). Contact: [a@zigao.wang](mailto:a@zigao.wang).
