# Psst content guide

This is the handbook for adding places to Psst. It is written for a Claude Code session (or a person) who has been asked to "research an area and add it." Read it all before you start. The facts are the product, so the bar is high.

## The short version

1. Pick an area and draw a bounding box around it.
2. Research spots on the web. Keep only the ones with something genuinely surprising to say.
3. Get every coordinate from Wikidata or OpenStreetMap. Never guess or estimate one.
4. Write each fact twice: a short whisper and a longer story. Cite real sources.
5. Mark every fact as `fact`, `legend`, or `disputed`, honestly.
6. Save the area as `Content/areas/<area-id>.json`. That folder is ignored by git: content is kept and licensed separately from the app, so never commit area files to the app repository.
7. Run `python3 scripts/validate_content.py --online` and fix everything it reports.
8. Hand the file over to wherever the content is kept, and copy it into `Content/areas/` to build it into the app.

## What Psst is for

Psst is a friend leaning over to tell you something about the place you are standing in. Not the guidebook paragraph. The thing that makes you look at an ordinary building differently: the roundabout with a second, secret roundabout underneath it; the station named after a pub that closed a century ago; the hotel whose lobby used to be a banana warehouse.

People browse it like a feed. Every card has to earn the next swipe.

## What makes a good spot

A spot is one specific, findable, physical thing with its own pin: a single building, a bridge, a station entrance, a statue, a hotel, a roundabout, a street corner, a staircase, a lamppost, a pub, a bollard, a plaque, a dock wall. Someone should be able to walk up to it and point.

An area is only how the research is split up. It is never a spot. Never write one entry for a whole district, neighborhood, estate, or street network ("Canary Wharf", "the Bund", "Xintiandi"). If a street is the spot, it must be one short, specific street or alley with its own story, and its pin goes on that street. If a big complex has several good stories, split it into its parts (the station entrance, the clock tower, the gate) and give each its own pin.

Good spots:

- **Ordinary places with a secret.** A bus stop, a car park, a chain hotel, a footbridge. These are the heart of the app. Aim for at least half of an area's spots to be places a tourist would never look up.
- **Famous places with a detail nobody knows.** Big Ben is fine, but only with something better than "it is the bell, not the tower." Skip the fact everyone already knows and lead with the one they don't.
- **Things you can still see.** Prefer spots where the surprising thing is visible or at least the place still exists. A spot whose building was demolished can work if something on the ground still marks it (a street name, a plaque, a kink in the road).

Leave a spot out if:

- The best you can say is that it is old, tall, popular, or designed by someone famous.
- The only interesting thing is a generic superlative ("one of the busiest stations in Europe").
- You cannot find a solid source for the surprising part.
- It is private in a way that would send people somewhere they should not go (a private home, a restricted site). Public exteriors of private buildings are fine.

Aim for 20 to 40 spots per area, each with 2 to 4 facts, and make at least half of them ordinary places rather than famous landmarks. Quality beats count: 20 great spots are better than 40 thin ones. One excellent fact is enough for a spot to exist.

## What makes a good fact

A good fact is **specific, surprising, and true.**

- **Specific.** Names, numbers, years, and physical details. "The stones came from the old London Bridge" beats "the stones have an interesting history."
- **Surprising.** It should change how someone sees the place. Ask: would a friend say "wait, really?"
- **True, and sourced.** If you cannot back it up, it does not go in. If it is a good story that cannot be backed up, it can go in as a legend, clearly labeled.

Categories (pick the one that fits best):

| category | use it for |
| --- | --- |
| `name` | where a name came from, especially odd or misleading names |
| `hidden` | something physically there that people miss: a buried structure, a secret room, a detail on a facade |
| `history` | what used to happen here, what it replaced, who was here |
| `design` | architecture, deliberate design choices, art, signage |
| `engineering` | how it was built, how it works, what holds it up |
| `people` | a person whose story is tied to this exact spot |
| `quirk` | odd rules, strange laws, unusual customs, records, coincidences |

### Fact, legend, or disputed

Every fact has a `status`. This is the most important field in the file. Legends are fun, but they must never pass as facts.

- `fact`: well documented by reliable sources. You would bet on it.
- `legend`: a story people tell that is unproven or known to be false. Write it so it is obviously a story ("The story goes that...", "Locals like to say...") and, in the long version, say what the evidence actually shows. The app also labels it as a legend.
- `disputed`: reliable sources disagree, or the popular version is contested. Say what the disagreement is in the long version.

If you are not sure whether something is a fact, it is not a `fact`.

### The two versions

- `headline`: a few plain words naming the secret. Up to 60 characters. Not a pun, not clickbait, no question marks. Example: "A second roundabout underneath".
- `short`: the whisper. One or two sentences, up to 220 characters. It must stand on its own, because it is what shows by default. Lead with the surprising part.
- `long`: the story for people who want more. Roughly 300 to 1,200 characters. Add the context, the how and why, the names and dates, and, for legends and disputes, what the evidence says. Do not just repeat the short version with more adjectives.

### Voice

Write like a well-read friend talking, not like a brochure or an encyclopedia.

- Plain words. Concrete nouns. Active verbs.
- Confident but not breathless. No exclamation marks.
- No "Did you know", "fun fact", "hidden gem", "psst", or "little-known".
- Do not address the reader constantly. An occasional "look up at the corner" is fine when it helps them find the thing.
- US English spelling and punctuation everywhere ("color", "center", "theater", "meter", "gray"). Proper names keep their own spelling: "Southbank Centre" and "National Theatre" stay as they are.
- Never use em dashes or en dashes. Use a period, a comma, a colon, parentheses, or the word "to" for ranges ("1840 to 1852").
- Avoid the words and phrases that make writing sound machine-made: "nestled", "boasts", "testament to", "rich tapestry", "vibrant", "delve", "bustling", "iconic", "stands as", "a must-see", "steeped in history", "whispers of the past", "not just X, but Y". The validator rejects the worst of these.

Example, good:

> **headline:** A second roundabout underneath
> **short:** The roundabout outside the station sits on top of another one. Delivery trucks circle the lower level so they never have to stop on the street.

Example, bad:

> **short:** This iconic roundabout boasts a fascinating hidden history that most people never notice!

## Coordinates

Coordinates must come from a real source. Never estimate from memory, from a map you are looking at, or from a street address.

1. **Wikidata first.** If the spot has a Wikidata item with a coordinate (property P625), use it. Fetch it with:
   ```
   curl -s -A "PsstContent/1.0" "https://www.wikidata.org/wiki/Special:EntityData/Q12345.json" | python3 -c "import json,sys; d=json.load(sys.stdin); c=list(d['entities'].values())[0]['claims']['P625'][0]['mainsnak']['datavalue']['value']; print(c['latitude'], c['longitude'])"
   ```
   To find an item, search `https://www.wikidata.org/w/api.php?action=wbsearchentities&search=NAME&language=en&format=json`.
2. **OpenStreetMap otherwise.** Find the node, way, or relation for the spot. For a node use its position; for a way or relation use the center that Overpass computes:
   ```
   curl -s -A "PsstContent/1.0" --data-urlencode 'data=[out:json];way(123456);out center;' https://overpass-api.de/api/interpreter
   ```
   To search by name near an area: `[out:json];nwr["name"~"Cutty Sark"](51.47,-0.02,51.49,0.0);out center;`
   Never put an email address or other personal information in a User-Agent or anywhere else in a request; a plain string like `PsstContent/1.0` is enough. Overpass is shared and rate limited. If you get a 429 or 504, wait a few seconds and retry, and batch lookups where you can (`(way(1);way(2);node(3););out center;`).
   If Overpass is down, the main OSM API works for single elements: `https://api.openstreetmap.org/api/0.6/node/123.json` for a node, or `.../way/123/full.json` for a way, where the coordinate to use is the middle of the bounding box of its nodes (that is exactly what Overpass `out center` returns). If the Wikidata API answers 429, the query service at `https://query.wikidata.org/sparql` is limited separately. The validator falls back to both automatically.
3. **Check the precision.** Some Wikidata coordinates are rounded to 3 decimal places or fewer, which can be 100 meters out. If a Wikidata coordinate has fewer than 4 decimal places, use the OSM element instead.
4. **Check it makes sense.** The Wikidata point for a large thing (a park, a long bridge) is sometimes far from where people stand. If the Wikidata point is clearly wrong for what the spot describes, use the OSM element instead. If neither source has the spot, leave the spot out.

Record where the coordinate came from in `coordinateSource`. Copy the numbers exactly as the source gives them; do not round them or add digits.

**Always store WGS-84, even in China.** Wikidata and OpenStreetMap both use WGS-84. Apple Maps in mainland China draws its map in the shifted GCJ-02 system, and the app converts coordinates at display time. Never convert or "fix" coordinates by hand in the data files, or pins in Shanghai will end up hundreds of meters off.

## Sources

Every fact needs at least one real source with a working URL, and at least one of its sources must be something other than Wikipedia. Wikipedia is a good place to find leads, but cite what it cites.

Good sources, roughly in order:

- Official listings and records (Historic England, UK Parliament, Survey of London, national heritage boards, city archives).
- The owner or operator (Transport for London, the Canal & River Trust, the building's own history page).
- Museums, universities, and academic publications.
- Reputable newspapers and magazines, and long-running specialist sites with a track record (for London: Londonist, Ian Visits, London Historians; for Shanghai: the Shanghai local gazetteers (上海地方志, shtong.gov.cn), Shanghai municipal and district government sites, the Shanghai Archives, The Paper (澎湃), SHINE, Sixth Tone; for Kuala Lumpur: The Star, New Straits Times, Malay Mail, Badan Warisan Malaysia).

Do not rely only on English sources outside English-speaking places. For Shanghai, Chinese Wikipedia and the district gazetteers (区志) and specialist gazetteers (专志) on shtong.gov.cn usually have far more detail about individual buildings, bridges, and streets than anything in English; read them, then cite the gazetteer or other primary source. The same goes for Malay and Chinese sources in Kuala Lumpur.

Avoid content farms, AI-written listicles, and travel sites that do not cite anything. For legends, cite a source that tells the story and, ideally, one that examines it.

## The file format

One JSON file per area, in `Content/areas/`. The filename is the area `id` plus `.json`. UTF-8, two-space indentation.

```json
{
  "schemaVersion": 1,
  "id": "london-greenwich",
  "name": "Greenwich",
  "city": "London",
  "countryCode": "GB",
  "summary": "Ships, stars, and the line the whole world sets its clocks by.",
  "researchedOn": "2026-09-28",
  "bounds": { "south": 51.4680, "west": -0.0250, "north": 51.4900, "east": 0.0100 },
  "spots": [
    {
      "id": "greenwich-foot-tunnel",
      "name": "Greenwich Foot Tunnel",
      "localName": null,
      "kind": "crossing",
      "size": "medium",
      "coordinate": { "latitude": 51.4833, "longitude": -0.0102 },
      "coordinateSource": { "type": "wikidata", "id": "Q935104" },
      "facts": [
        {
          "id": "built-for-dockers",
          "category": "history",
          "status": "fact",
          "headline": "Built so dockers could get to work",
          "short": "One or two sentences.",
          "long": "The longer story.",
          "sources": [
            { "title": "Greenwich Foot Tunnel", "publisher": "Royal Borough of Greenwich", "url": "https://www.royalgreenwich.gov.uk/..." }
          ]
        }
      ]
    }
  ]
}
```

### Area fields

| field | rules |
| --- | --- |
| `schemaVersion` | Always `1` for now. |
| `id` | `city-area` in lowercase kebab case, e.g. `london-greenwich`, `shanghai-the-bund`. Never change it once published. |
| `name` | The area's everyday name. |
| `city` | The city. Areas with the same `city` are grouped together in the app. |
| `countryCode` | ISO 3166-1 alpha-2, e.g. `GB`, `MY`, `CN`. |
| `summary` | One sentence, up to 120 characters, in the app's voice. Shown in the area picker. |
| `researchedOn` | The date you did the research, `YYYY-MM-DD`. |
| `bounds` | A box around the area in WGS-84. Every spot must be inside it. Keep it tight: the app uses it to frame the area on the map. |
| `spots` | The list of spots. The order does not matter; the app sorts and shuffles. |

### Spot fields

| field | rules |
| --- | --- |
| `id` | Lowercase kebab case, unique within the area. The app stores saved spots as `areaId/spotId`, so never change or reuse an id once published. |
| `name` | The name people use on the ground, in English. |
| `localName` | Optional. The name in the local script or language if it differs, e.g. `和平饭店` for the Peace Hotel. Use `null` or leave it out otherwise. |
| `kind` | One of the kinds below. It sets the pin color and icon. |
| `size` | `small` (a statue, a door, a bollard), `medium` (a building, a station, a square), or `large` (a skyscraper, a long bridge, a park). It sets how far back the 3D view sits. Defaults to `medium`. |
| `coordinate` | `latitude` and `longitude` in WGS-84, from `coordinateSource`. |
| `coordinateSource` | `{ "type": "wikidata", "id": "Q..." }` or `{ "type": "osm", "id": "node/123" }` (also `way/123` or `relation/123`). |
| `facts` | At least one fact. Put the best one first: it is the one shown on the feed card. |

Kinds:

| kind | for |
| --- | --- |
| `transit` | stations, stops, piers, depots, anything you board |
| `crossing` | bridges, tunnels, footbridges, subways |
| `street` | streets, alleys, roundabouts, junctions, steps, street furniture |
| `building` | offices, homes, hotels, shops, pubs, banks, towers |
| `worship` | churches, temples, mosques, synagogues, shrines |
| `memorial` | statues, monuments, plaques, markers, boundary stones |
| `green` | parks, gardens, squares, cemeteries, trees |
| `water` | docks, basins, rivers, canals, fountains, wells |
| `culture` | museums, theaters, galleries, venues, markets, stadiums |

### Fact fields

| field | rules |
| --- | --- |
| `id` | Lowercase kebab case, unique within the spot. Never change it once published. |
| `category` | One of `name`, `hidden`, `history`, `design`, `engineering`, `people`, `quirk`. |
| `status` | `fact`, `legend`, or `disputed`. See above. |
| `headline` | Up to 60 characters. |
| `short` | Up to 220 characters, one or two sentences. |
| `long` | 300 to 1,200 characters. |
| `sources` | At least one. Each has `title`, `publisher`, and an `https` `url`. At least one per fact must not be Wikipedia. |

## Avoiding overlap

Before you add a spot, search the other files in `Content/areas/` for it. A spot belongs to exactly one area. Bridges and landmarks on a border go to whichever area already has them; if neither does, pick the area whose bounding box contains the coordinate.

## Checking your work

Run the validator from the repo root:

```
python3 scripts/validate_content.py            # structure, rules, and style
python3 scripts/validate_content.py --online   # also re-fetches every coordinate from Wikidata or OSM and compares
```

It fails on anything that would break the app or the rules above: missing fields, bad ids, duplicates, spots outside their bounds, text that is too long or too short, em dashes, British spellings, banned phrases, missing or Wikipedia-only sources, and coordinates that do not match their source. Fix every error. Read the warnings too.

Then do a human pass. The validator cannot tell whether something is true or interesting. For every fact, ask:

1. Does the source actually say this? Open it and check.
2. Is the status honest? Would a skeptical reader call this a legend?
3. Would a friend say "wait, really?" If not, cut it.
4. Does the short version make sense on its own, with no context?

Finally, build and run the app and look at a few of your spots on the map and in the feed. Check that the pins sit on the right building.
