#!/usr/bin/env python3
"""Validate the Psst content files in Content/areas.

Usage:
    python3 scripts/validate_content.py                 # offline checks
    python3 scripts/validate_content.py --online        # also verify coordinates against Wikidata and OSM
    python3 scripts/validate_content.py --check-links   # also request every source URL (slow, warnings only)
    python3 scripts/validate_content.py Content/areas/london-greenwich.json   # check specific files

Exits with status 1 if any error is found. See CONTENT_GUIDE.md for the rules.
Uses only the Python standard library.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import datetime
import json
import math
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from decimal import Decimal
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
AREAS_DIR = ROOT / "Content" / "areas"
USER_AGENT = "PsstContentValidator/1.0 (https://github.com/; content QA script)"

SCHEMA_VERSION = 1
KINDS = {"transit", "crossing", "street", "building", "worship", "memorial", "green", "water", "culture"}
SIZES = {"small", "medium", "large"}
CATEGORIES = {"name", "hidden", "history", "design", "engineering", "people", "quirk"}
STATUSES = {"fact", "legend", "disputed"}
SOURCE_TYPES = {"wikidata", "osm"}

AREA_KEYS = {"schemaVersion", "id", "name", "city", "countryCode", "summary", "researchedOn", "bounds", "spots"}
SPOT_KEYS = {"id", "name", "localName", "kind", "size", "coordinate", "coordinateSource", "facts"}
SPOT_REQUIRED = SPOT_KEYS - {"localName", "size"}
FACT_KEYS = {"id", "category", "status", "headline", "short", "long", "sources"}
SOURCE_KEYS = {"title", "publisher", "url"}

ID_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
AREA_ID_RE = re.compile(r"^[a-z]+(?:-[a-z0-9]+)+$")
QID_RE = re.compile(r"^Q[1-9][0-9]*$")
OSM_RE = re.compile(r"^(node|way|relation)/[1-9][0-9]*$")

HEADLINE_MAX = 60
SHORT_MAX = 220
LONG_MIN = 300
LONG_MAX = 1200
SUMMARY_MAX = 120
MAX_BOUNDS_SPAN_DEGREES = 0.2
COORDINATE_TOLERANCE_METERS = 30.0
DUPLICATE_DISTANCE_METERS = 15.0

# Phrases that make writing read as machine-made or as marketing. Errors.
BANNED_PHRASES = [
    "nestled", "boasts", "boasting", "testament to", "rich tapestry", "tapestry of", "vibrant", "delve",
    "bustling", "iconic", "a must-see", "must-see", "steeped in", "whispers of the past", "hidden gem",
    "fun fact", "did you know", "little-known", "little known fact", "psst", "stands as a", "stands as an",
    "it's worth noting", "it is worth noting", "interestingly,", "in conclusion", "a true gem",
    "treasure trove", "bucket list", "breathtaking", "awe-inspiring", "unforgettable", "embark on",
    "journey through time", "step back in time", "a feast for the eyes", "look no further",
]

# Phrases that are often a sign of padding. Warnings.
SOFT_PHRASES = [
    "fascinating", "remarkable", "stunning", "amazing", "incredible", "truly", "unique", "a nod to",
    "not just", "not only", "rich history", "storied", "charming", "quaint", "picturesque",
]

BRITISH_WORDS = {
    "colour": "color", "colours": "colors", "coloured": "colored", "colourful": "colorful",
    "favourite": "favorite", "favourites": "favorites", "flavour": "flavor", "honour": "honor",
    "honoured": "honored", "honours": "honors", "labour": "labor", "labourers": "laborers", "labourer": "laborer",
    "neighbour": "neighbor", "neighbours": "neighbors", "neighbouring": "neighboring", "neighbourhood": "neighborhood",
    "neighbourhoods": "neighborhoods", "harbour": "harbor", "harbours": "harbors", "behaviour": "behavior",
    "rumour": "rumor", "rumours": "rumors", "rumoured": "rumored", "humour": "humor", "vapour": "vapor",
    "armour": "armor", "armoured": "armored", "parlour": "parlor", "odour": "odor", "splendour": "splendor",
    "endeavour": "endeavor", "glamour": "glamor", "valour": "valor", "vigour": "vigor", "saviour": "savior",
    "centre": "center", "centres": "centers", "centred": "centered", "theatre": "theater", "theatres": "theaters",
    "metre": "meter", "metres": "meters", "kilometre": "kilometer", "kilometres": "kilometers",
    "centimetre": "centimeter", "centimetres": "centimeters", "millimetre": "millimeter", "millimetres": "millimeters",
    "litre": "liter", "litres": "liters", "fibre": "fiber", "sabre": "saber", "spectre": "specter",
    "calibre": "caliber", "lustre": "luster", "sombre": "somber", "meagre": "meager", "sepulchre": "sepulcher",
    "grey": "gray", "greying": "graying", "programme": "program", "programmes": "programs",
    "storey": "story", "storeys": "stories", "kerb": "curb", "kerbs": "curbs", "tyre": "tire", "tyres": "tires",
    "aluminium": "aluminum", "defence": "defense", "defences": "defenses", "offence": "offense", "offences": "offenses",
    "licence": "license", "licences": "licenses", "pretence": "pretense", "jewellery": "jewelry", "catalogue": "catalog",
    "analogue": "analog", "cheque": "check", "cheques": "checks", "plough": "plow", "ploughed": "plowed",
    "travelled": "traveled", "travelling": "traveling", "traveller": "traveler", "travellers": "travelers",
    "cancelled": "canceled", "cancelling": "canceling", "modelled": "modeled", "modelling": "modeling",
    "labelled": "labeled", "fuelled": "fueled", "levelled": "leveled", "signalling": "signaling", "signalled": "signaled",
    "marvellous": "marvelous", "channelled": "channeled", "tunnelled": "tunneled", "tunnelling": "tunneling",
    "counsellor": "counselor", "jeweller": "jeweler", "jewellers": "jewelers", "quarrelled": "quarreled",
    "whilst": "while", "amongst": "among", "learnt": "learned", "spelt": "spelled", "burnt": "burned",
    "manoeuvre": "maneuver", "manoeuvres": "maneuvers", "encyclopaedia": "encyclopedia", "mould": "mold",
    "moulded": "molded", "sceptic": "skeptic", "sceptical": "skeptical", "sulphur": "sulfur", "ageing": "aging",
    "draught": "draft", "gaol": "jail", "pyjamas": "pajamas", "moustache": "mustache", "cosy": "cozy",
    "annexe": "annex", "artefact": "artifact", "artefacts": "artifacts", "enrol": "enroll", "fulfil": "fulfill",
    "instalment": "installment", "judgement": "judgment", "mediaeval": "medieval", "oestrogen": "estrogen",
    "practise": "practice", "practised": "practiced",
}

# -ise/-yse verbs that US English writes as -ize/-yze. Matched as stem + ending.
BRITISH_ISE_STEMS = [
    "organ", "recogn", "real", "special", "urban", "modern", "standard", "civil", "colon", "commercial", "critic",
    "apolog", "author", "capital", "central", "character", "custom", "final", "formal", "harmon", "immortal",
    "industrial", "legal", "memorial", "minim", "mobil", "national", "neutral", "normal", "optim", "popular",
    "priorit", "public", "revolution", "romantic", "sanit", "stabil", "summar", "symbol", "sympath", "util",
    "visual", "weapon", "fantas", "glamor", "idol", "emphas", "hospital", "patron", "privat", "pedestrian",
    "rational", "regular", "scandal", "secular", "social", "subsid", "terror", "trivial", "vandal", "western",
    "agon", "energ", "equal", "familiar", "fertil", "galvan", "hypnot", "initial", "local", "magnet", "maxim",
    "memor", "mesmer", "monopol", "motor", "natural", "polar", "pressur", "random", "canon", "computer",
    "decentral", "demoral", "digit", "dramat", "econom", "epitom", "evangel", "fossil", "general", "human",
    "ideal", "immun", "italic", "jeopard", "legitim", "liberal", "material", "militar", "moral", "nation",
    "person", "politic", "radical", "rubber", "scrutin", "sensit", "signal", "spiritual",
    "steril", "stigmat", "synchron", "synthes", "theor", "traumat", "tyrann", "unional", "vapor", "victim",
    "vulcan",
]
BRITISH_ISE_RE = re.compile(
    r"\b(" + "|".join(sorted(set(BRITISH_ISE_STEMS), key=len, reverse=True)) + r")is(e|es|ed|ing|ation|ations)\b"
)
BRITISH_YSE_RE = re.compile(r"\b(analy|paraly|cataly|dialy)s(e|ed|ing)\b")  # not "analyses", a valid noun

WORD_RE = re.compile(r"[A-Za-z]+")


class Report:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def error(self, where: str, message: str) -> None:
        self.errors.append(f"{where}: {message}")

    def warn(self, where: str, message: str) -> None:
        self.warnings.append(f"{where}: {message}")


def haversine_meters(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 6_371_000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = p2 - p1
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def is_nonempty_string(value: object) -> bool:
    return isinstance(value, str) and value.strip() != "" and value == value.strip()


def check_keys(report: Report, where: str, obj: dict, allowed: set[str], required: set[str]) -> None:
    for key in obj:
        if key not in allowed:
            report.error(where, f"unknown field '{key}'")
    for key in sorted(required):
        if key not in obj:
            report.error(where, f"missing field '{key}'")


def check_prose(report: Report, where: str, field: str, text: str) -> None:
    """Style rules that apply to anything the app shows as our own writing."""
    loc = f"{where}.{field}"
    if "—" in text:
        report.error(loc, "contains an em dash; rewrite with a period, comma, colon, or parentheses")
    if "–" in text:
        report.error(loc, "contains an en dash; use 'to' for ranges or rewrite")
    if "--" in text:
        report.error(loc, "contains '--'; rewrite without a dash")
    if " - " in text:
        report.warn(loc, "contains a spaced hyphen used as a dash; rewrite")
    if "!" in text:
        report.error(loc, "contains an exclamation mark")
    if "  " in text:
        report.warn(loc, "contains a double space")
    lowered = text.lower()
    for phrase in BANNED_PHRASES:
        if re.search(r"(?<![a-z])" + re.escape(phrase) + r"(?![a-z])", lowered):
            report.error(loc, f"uses the phrase '{phrase}'")
    for phrase in SOFT_PHRASES:
        if re.search(r"(?<![a-z])" + re.escape(phrase) + r"(?![a-z])", lowered):
            report.warn(loc, f"uses '{phrase}'; is it earning its place?")
    for match in WORD_RE.finditer(text):
        word = match.group(0)
        if word[0].isupper():
            continue  # Proper names such as "Southbank Centre" keep their own spelling.
        suggestion = BRITISH_WORDS.get(word)
        if suggestion:
            report.error(loc, f"British spelling '{word}'; use '{suggestion}'")
    for regex in (BRITISH_ISE_RE, BRITISH_YSE_RE):
        for match in regex.finditer(text):
            word = match.group(0)
            if word[0].isupper():
                continue
            report.error(loc, f"British spelling '{word}'; use the -ize or -yze form")


def count_sentences(text: str) -> int:
    # Rough count: a terminator followed by whitespace and an uppercase letter or quote, plus the final one.
    boundaries = re.findall(r"[.?!][\"')”]?\s+(?=[A-Z0-9\"'“(])", text)
    return len(boundaries) + 1


def decimals_of(value: object) -> int:
    if isinstance(value, Decimal):
        exponent = value.as_tuple().exponent
        return -exponent if isinstance(exponent, int) and exponent < 0 else 0
    return 0


def validate_source(report: Report, where: str, source: object) -> str | None:
    if not isinstance(source, dict):
        report.error(where, "source must be an object")
        return None
    check_keys(report, where, source, SOURCE_KEYS, SOURCE_KEYS)
    for key in ("title", "publisher"):
        if key in source and not is_nonempty_string(source[key]):
            report.error(where, f"'{key}' must be a non-empty string without surrounding spaces")
    url = source.get("url")
    if not isinstance(url, str):
        return None
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme != "https" or not parsed.netloc:
        report.error(where, f"url must be a full https URL: {url}")
        return None
    if " " in url:
        report.error(where, f"url contains a space: {url}")
    if re.search(r"(google\.[a-z.]+/search|bing\.com/search|chatgpt|openai\.com|perplexity\.ai)", url):
        report.error(where, f"url is a search or AI result, not a source: {url}")
    return url


def validate_fact(report: Report, where: str, fact: object, fact_ids: set[str]) -> list[str]:
    urls: list[str] = []
    if not isinstance(fact, dict):
        report.error(where, "fact must be an object")
        return urls
    check_keys(report, where, fact, FACT_KEYS, FACT_KEYS)
    fid = fact.get("id")
    if isinstance(fid, str) and ID_RE.match(fid):
        if fid in fact_ids:
            report.error(where, f"duplicate fact id '{fid}'")
        fact_ids.add(fid)
        where = f"{where}[{fid}]"
    else:
        report.error(where, f"fact id must be lowercase kebab case, got {fid!r}")

    if fact.get("category") not in CATEGORIES:
        report.error(where, f"category must be one of {sorted(CATEGORIES)}, got {fact.get('category')!r}")
    if fact.get("status") not in STATUSES:
        report.error(where, f"status must be one of {sorted(STATUSES)}, got {fact.get('status')!r}")

    headline = fact.get("headline")
    short = fact.get("short")
    long = fact.get("long")
    if not is_nonempty_string(headline):
        report.error(where, "headline must be a non-empty string without surrounding spaces")
    else:
        if len(headline) > HEADLINE_MAX:
            report.error(where, f"headline is {len(headline)} characters; max {HEADLINE_MAX}")
        if "?" in headline:
            report.error(where, "headline must not be a question")
        if headline.endswith("."):
            report.warn(where, "headline ends with a period")
        check_prose(report, where, "headline", headline)
    if not is_nonempty_string(short):
        report.error(where, "short must be a non-empty string without surrounding spaces")
    else:
        if len(short) > SHORT_MAX:
            report.error(where, f"short is {len(short)} characters; max {SHORT_MAX}")
        if count_sentences(short) > 2:
            report.warn(where, "short looks like more than two sentences")
        if short[-1] not in ".\"'”)":
            report.warn(where, "short does not end with a period")
        check_prose(report, where, "short", short)
    if not is_nonempty_string(long):
        report.error(where, "long must be a non-empty string without surrounding spaces")
    else:
        if len(long) < LONG_MIN:
            report.error(where, f"long is {len(long)} characters; min {LONG_MIN}")
        if len(long) > LONG_MAX:
            report.error(where, f"long is {len(long)} characters; max {LONG_MAX}")
        if isinstance(short, str) and long.strip() == short.strip():
            report.error(where, "long repeats short")
        elif isinstance(short, str) and len(short) > 40 and long.startswith(short[:60]):
            report.warn(where, "long starts with the same words as short; add something new")
        check_prose(report, where, "long", long)
    if fact.get("status") == "legend" and isinstance(long, str):
        if not re.search(r"\b(no evidence|evidence|record|records|unproven|untrue|myth|legend|story|stories|claim|claims|probably|likely|unlikely|say|says|said|told|tell)\b", long, re.I):
            report.warn(where, "legend's long version should say what the evidence shows")

    sources = fact.get("sources")
    if not isinstance(sources, list) or not sources:
        report.error(where, "needs at least one source")
        return urls
    non_wikipedia = 0
    seen_urls: set[str] = set()
    for index, source in enumerate(sources):
        url = validate_source(report, f"{where}.sources[{index}]", source)
        if url:
            if url in seen_urls:
                report.error(where, f"duplicate source url {url}")
            seen_urls.add(url)
            urls.append(url)
            host = urllib.parse.urlparse(url).netloc.lower()
            if not (host.endswith("wikipedia.org") or host.endswith("wikidata.org") or host.endswith("wikimedia.org")):
                non_wikipedia += 1
    if non_wikipedia == 0:
        report.error(where, "every fact needs at least one source that is not Wikipedia or Wikidata")
    return urls


def validate_spot(report: Report, area_id: str, bounds: dict | None, spot: object, spot_ids: set[str],
                  spot_names: set[str]) -> dict | None:
    where = f"{area_id}/?"
    if not isinstance(spot, dict):
        report.error(where, "spot must be an object")
        return None
    sid = spot.get("id")
    if isinstance(sid, str) and ID_RE.match(sid):
        where = f"{area_id}/{sid}"
        if sid in spot_ids:
            report.error(where, "duplicate spot id")
        spot_ids.add(sid)
    else:
        report.error(where, f"spot id must be lowercase kebab case, got {sid!r}")
    check_keys(report, where, spot, SPOT_KEYS, SPOT_REQUIRED)

    name = spot.get("name")
    if not is_nonempty_string(name):
        report.error(where, "name must be a non-empty string without surrounding spaces")
    else:
        if name.lower() in spot_names:
            report.error(where, f"duplicate spot name '{name}' in this area")
        spot_names.add(name.lower())
        check_prose(report, where, "name", name)
    local_name = spot.get("localName")
    if local_name is not None and not is_nonempty_string(local_name):
        report.error(where, "localName must be null or a non-empty string")
    if spot.get("kind") not in KINDS:
        report.error(where, f"kind must be one of {sorted(KINDS)}, got {spot.get('kind')!r}")
    if "size" in spot and spot["size"] not in SIZES:
        report.error(where, f"size must be one of {sorted(SIZES)}, got {spot.get('size')!r}")

    lat = lon = None
    coordinate = spot.get("coordinate")
    if not isinstance(coordinate, dict):
        report.error(where, "coordinate must be an object with latitude and longitude")
    else:
        check_keys(report, f"{where}.coordinate", coordinate, {"latitude", "longitude"}, {"latitude", "longitude"})
        raw_lat, raw_lon = coordinate.get("latitude"), coordinate.get("longitude")
        if isinstance(raw_lat, (Decimal, int)) and not isinstance(raw_lat, bool) and isinstance(raw_lon, (Decimal, int)) and not isinstance(raw_lon, bool):
            lat, lon = float(raw_lat), float(raw_lon)
            if not (-90 <= lat <= 90 and -180 <= lon <= 180):
                report.error(where, f"coordinate out of range: {lat}, {lon}")
            if lat == 0 and lon == 0:
                report.error(where, "coordinate is 0, 0")
            if min(decimals_of(raw_lat), decimals_of(raw_lon)) < 4:
                report.error(where, "coordinate has fewer than 4 decimal places; use a more precise source")
            if bounds and not (bounds["south"] <= lat <= bounds["north"] and bounds["west"] <= lon <= bounds["east"]):
                report.error(where, f"coordinate {lat}, {lon} is outside the area bounds")
        else:
            report.error(where, "latitude and longitude must be numbers")

    source = spot.get("coordinateSource")
    source_ref = None
    if not isinstance(source, dict):
        report.error(where, "coordinateSource must be an object")
    else:
        check_keys(report, f"{where}.coordinateSource", source, {"type", "id"}, {"type", "id"})
        stype, sref = source.get("type"), source.get("id")
        if stype not in SOURCE_TYPES:
            report.error(where, f"coordinateSource.type must be one of {sorted(SOURCE_TYPES)}")
        elif stype == "wikidata" and not (isinstance(sref, str) and QID_RE.match(sref)):
            report.error(where, f"wikidata id must look like Q12345, got {sref!r}")
        elif stype == "osm" and not (isinstance(sref, str) and OSM_RE.match(sref)):
            report.error(where, f"osm id must look like node/123, way/123, or relation/123, got {sref!r}")
        else:
            source_ref = (stype, sref)

    facts = spot.get("facts")
    urls: list[str] = []
    if not isinstance(facts, list) or not facts:
        report.error(where, "needs at least one fact")
    else:
        fact_ids: set[str] = set()
        statuses = []
        for index, fact in enumerate(facts):
            urls += validate_fact(report, f"{where}.facts[{index}]", fact, fact_ids)
            if isinstance(fact, dict):
                statuses.append(fact.get("status"))
        if len(facts) > 6:
            report.warn(where, f"has {len(facts)} facts; keep the best four or five")
        if statuses and statuses[0] != "fact" and "fact" in statuses:
            report.warn(where, "lead fact (shown on the feed card) is not a plain fact; consider reordering")

    return {
        "where": where, "name": name if isinstance(name, str) else "", "lat": lat, "lon": lon,
        "source": source_ref, "urls": urls,
    }


def validate_area(report: Report, path: Path) -> list[dict]:
    where = path.name
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        report.error(where, "file is not valid UTF-8")
        return []
    try:
        data = json.loads(text, parse_float=Decimal)
    except json.JSONDecodeError as exc:
        report.error(where, f"invalid JSON: {exc}")
        return []
    if not isinstance(data, dict):
        report.error(where, "top level must be an object")
        return []
    check_keys(report, where, data, AREA_KEYS, AREA_KEYS)

    if data.get("schemaVersion") != SCHEMA_VERSION:
        report.error(where, f"schemaVersion must be {SCHEMA_VERSION}")
    area_id = data.get("id")
    if not (isinstance(area_id, str) and AREA_ID_RE.match(area_id)):
        report.error(where, f"area id must look like city-area in kebab case, got {area_id!r}")
        area_id = path.stem
    elif path.stem != area_id:
        report.error(where, f"filename must be '{area_id}.json'")
    for key in ("name", "city"):
        if not is_nonempty_string(data.get(key)):
            report.error(where, f"'{key}' must be a non-empty string")
    if isinstance(data.get("name"), str):
        check_prose(report, area_id, "name", data["name"])
    country = data.get("countryCode")
    if not (isinstance(country, str) and re.match(r"^[A-Z]{2}$", country)):
        report.error(where, "countryCode must be two uppercase letters")
    summary = data.get("summary")
    if not is_nonempty_string(summary):
        report.error(where, "summary must be a non-empty string")
    else:
        if len(summary) > SUMMARY_MAX:
            report.error(where, f"summary is {len(summary)} characters; max {SUMMARY_MAX}")
        check_prose(report, area_id, "summary", summary)
    researched = data.get("researchedOn")
    try:
        day = datetime.date.fromisoformat(researched) if isinstance(researched, str) else None
        if day is None:
            raise ValueError
        if day > datetime.date.today() + datetime.timedelta(days=1):
            report.error(where, "researchedOn is in the future")
    except ValueError:
        report.error(where, "researchedOn must be a YYYY-MM-DD date")

    bounds = data.get("bounds")
    valid_bounds = None
    if not isinstance(bounds, dict):
        report.error(where, "bounds must be an object")
    else:
        keys = {"south", "west", "north", "east"}
        check_keys(report, f"{where}.bounds", bounds, keys, keys)
        if all(isinstance(bounds.get(k), (Decimal, int)) for k in keys):
            b = {k: float(bounds[k]) for k in keys}
            if not (b["south"] < b["north"] and b["west"] < b["east"]):
                report.error(where, "bounds must have south < north and west < east")
            elif b["north"] - b["south"] > MAX_BOUNDS_SPAN_DEGREES or b["east"] - b["west"] > MAX_BOUNDS_SPAN_DEGREES:
                report.error(where, "bounds are too large; keep an area tight")
            else:
                valid_bounds = b
        else:
            report.error(where, "bounds values must be numbers")

    spots = data.get("spots")
    results: list[dict] = []
    if not isinstance(spots, list) or not spots:
        report.error(where, "spots must be a non-empty list")
        return results
    if len(spots) < 15:
        report.warn(where, f"only {len(spots)} spots; an area should have enough to browse")
    spot_ids: set[str] = set()
    spot_names: set[str] = set()
    for spot in spots:
        result = validate_spot(report, area_id, valid_bounds, spot, spot_ids, spot_names)
        if result:
            results.append(result)
    return results


def check_cross_file(report: Report, spots: list[dict]) -> None:
    by_source: dict[tuple, str] = {}
    for spot in spots:
        if spot["source"]:
            if spot["source"] in by_source:
                report.error(spot["where"], f"same coordinate source as {by_source[spot['source']]}")
            else:
                by_source[spot["source"]] = spot["where"]
    located = [s for s in spots if s["lat"] is not None]
    for i, a in enumerate(located):
        for b in located[i + 1:]:
            if abs(a["lat"] - b["lat"]) > 0.001 or abs(a["lon"] - b["lon"]) > 0.002:
                continue
            distance = haversine_meters(a["lat"], a["lon"], b["lat"], b["lon"])
            if distance < DUPLICATE_DISTANCE_METERS:
                report.warn(a["where"], f"only {distance:.0f} m from {b['where']}; is this the same place?")


def fetch_json(url: str, data: bytes | None = None, attempts: int = 5) -> object:
    last_error: Exception | None = None
    for attempt in range(attempts):
        request = urllib.request.Request(url, data=data, headers={"User-Agent": USER_AGENT})
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            last_error = exc
            if exc.code == 404:
                raise
            retry_after = exc.headers.get("Retry-After") if exc.headers else None
            delay = float(retry_after) if retry_after and retry_after.isdigit() else 3 * (attempt + 1)
            time.sleep(min(delay, 30))
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            last_error = exc
            time.sleep(3 * (attempt + 1))
    raise RuntimeError(f"request failed after {attempts} attempts: {url} ({last_error})")


def wikidata_coordinates(qids: list[str]) -> dict[str, list[tuple[float, float, float | None]]]:
    found: dict[str, list[tuple[float, float, float | None]]] = {}
    for start in range(0, len(qids), 50):
        batch = qids[start:start + 50]
        try:
            found.update(_wikidata_api(batch))
        except RuntimeError:
            # The API rate limits shared IPs hard; the query service is a separate pool.
            found.update(_wikidata_sparql(batch))
    return found


def _wikidata_api(batch: list[str]) -> dict[str, list[tuple[float, float, float | None]]]:
    found: dict[str, list[tuple[float, float, float | None]]] = {}
    url = "https://www.wikidata.org/w/api.php?action=wbgetentities&props=claims&format=json&ids=" + "|".join(batch)
    payload = fetch_json(url, attempts=3)
    for qid, entity in payload.get("entities", {}).items():
        coords = []
        for claim in entity.get("claims", {}).get("P625", []):
            value = claim.get("mainsnak", {}).get("datavalue", {}).get("value")
            if value:
                coords.append((value["latitude"], value["longitude"], value.get("precision")))
        found[qid] = coords
        redirected = entity.get("redirects", {}).get("from")
        if redirected:
            found[redirected] = coords
    return found


def _wikidata_sparql(batch: list[str]) -> dict[str, list[tuple[float, float, float | None]]]:
    values = " ".join(f"wd:{qid}" for qid in batch)
    query = f"""SELECT ?item ?lat ?lon ?precision WHERE {{
      VALUES ?item {{ {values} }}
      OPTIONAL {{ ?item p:P625/psv:P625 ?node .
                 ?node wikibase:geoLatitude ?lat ; wikibase:geoLongitude ?lon .
                 OPTIONAL {{ ?node wikibase:geoPrecision ?precision }} }}
    }}"""
    url = "https://query.wikidata.org/sparql?format=json&query=" + urllib.parse.quote(query)
    payload = fetch_json(url)
    found: dict[str, list[tuple[float, float, float | None]]] = {qid: [] for qid in batch}
    for row in payload["results"]["bindings"]:
        qid = row["item"]["value"].rsplit("/", 1)[-1]
        if "lat" in row:
            precision = float(row["precision"]["value"]) if "precision" in row else None
            found.setdefault(qid, []).append((float(row["lat"]["value"]), float(row["lon"]["value"]), precision))
    return found


OVERPASS_ENDPOINTS = [
    "https://overpass-api.de/api/interpreter",
    "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
]


def osm_coordinates(refs: list[str]) -> dict[str, tuple[float, float]]:
    found: dict[str, tuple[float, float]] = {}
    for start in range(0, len(refs), 100):
        batch = refs[start:start + 100]
        parts = "".join(f"{ref.split('/')[0]}({ref.split('/')[1]});" for ref in batch)
        query = f"[out:json][timeout:90];({parts});out center;"
        payload = None
        for endpoint in OVERPASS_ENDPOINTS:
            try:
                payload = fetch_json(endpoint, data=urllib.parse.urlencode({"data": query}).encode(), attempts=2)
                break
            except RuntimeError:
                continue
        if payload is None:
            # Overpass is down or busy: ask the main OSM API one element at a time.
            for ref in batch:
                coord = _osm_api_center(ref)
                if coord:
                    found[ref] = coord
            continue
        for element in payload.get("elements", []):
            ref = f"{element['type']}/{element['id']}"
            if "lat" in element:
                found[ref] = (element["lat"], element["lon"])
            elif "center" in element:
                found[ref] = (element["center"]["lat"], element["center"]["lon"])
        time.sleep(1)
    return found


def _osm_api_center(ref: str) -> tuple[float, float] | None:
    """Same result as Overpass `out center`: a node's position, or the middle of a way's or relation's bounding box."""
    kind, number = ref.split("/")
    suffix = ".json" if kind == "node" else "/full.json"
    try:
        payload = fetch_json(f"https://api.openstreetmap.org/api/0.6/{kind}/{number}{suffix}", attempts=3)
    except (RuntimeError, urllib.error.HTTPError):
        return None
    nodes = [e for e in payload.get("elements", []) if e.get("type") == "node" and "lat" in e]
    if kind == "node":
        return (nodes[0]["lat"], nodes[0]["lon"]) if nodes else None
    if not nodes:
        return None
    lats = [n["lat"] for n in nodes]
    lons = [n["lon"] for n in nodes]
    return ((min(lats) + max(lats)) / 2, (min(lons) + max(lons)) / 2)


def check_online(report: Report, spots: list[dict]) -> None:
    qids = sorted({s["source"][1] for s in spots if s["source"] and s["source"][0] == "wikidata"})
    refs = sorted({s["source"][1] for s in spots if s["source"] and s["source"][0] == "osm"})
    print(f"Checking {len(qids)} Wikidata items and {len(refs)} OSM elements online...", file=sys.stderr)
    try:
        wd = wikidata_coordinates(qids) if qids else {}
        osm = osm_coordinates(refs) if refs else {}
    except RuntimeError as exc:
        report.error("online", str(exc))
        return
    for spot in spots:
        if not spot["source"] or spot["lat"] is None:
            continue
        stype, ref = spot["source"]
        if stype == "wikidata":
            coords = wd.get(ref)
            if coords is None:
                report.error(spot["where"], f"Wikidata item {ref} not found")
                continue
            if not coords:
                report.error(spot["where"], f"Wikidata item {ref} has no coordinate (P625)")
                continue
            best = min(coords, key=lambda c: haversine_meters(spot["lat"], spot["lon"], c[0], c[1]))
            distance = haversine_meters(spot["lat"], spot["lon"], best[0], best[1])
            if distance > COORDINATE_TOLERANCE_METERS:
                report.error(spot["where"], f"coordinate is {distance:.0f} m from Wikidata {ref} ({best[0]}, {best[1]})")
            elif best[2] is not None and best[2] > 0.0005:
                report.error(spot["where"], f"Wikidata {ref} coordinate precision is only {best[2]} degrees; use OSM")
        else:
            coord = osm.get(ref)
            if coord is None:
                report.error(spot["where"], f"OSM element {ref} not found")
                continue
            distance = haversine_meters(spot["lat"], spot["lon"], coord[0], coord[1])
            if distance > COORDINATE_TOLERANCE_METERS:
                report.error(spot["where"], f"coordinate is {distance:.0f} m from OSM {ref} ({coord[0]}, {coord[1]})")


def check_links(report: Report, spots: list[dict]) -> None:
    urls = sorted({url for s in spots for url in s["urls"]})
    print(f"Requesting {len(urls)} source URLs...", file=sys.stderr)

    def probe(url: str) -> tuple[str, str | None]:
        headers = {"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 Safari/605.1.15"}
        try:
            request = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(request, timeout=25) as response:
                return url, None if response.status < 400 else f"HTTP {response.status}"
        except urllib.error.HTTPError as exc:
            # Many sites reject scripts with 403 or 429 while working fine in a browser.
            return url, None if exc.code in (401, 403, 405, 429) else f"HTTP {exc.code}"
        except Exception as exc:  # noqa: BLE001 - report any network failure as a warning
            return url, str(exc)

    with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
        for url, problem in pool.map(probe, urls):
            if problem:
                report.warn("links", f"{url} -> {problem}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("files", nargs="*", type=Path, help="area files to check (default: all)")
    parser.add_argument("--online", action="store_true", help="verify coordinates against Wikidata and OSM")
    parser.add_argument("--check-links", action="store_true", help="request every source URL")
    parser.add_argument("--quiet-warnings", action="store_true", help="only print errors")
    args = parser.parse_args()

    all_files = sorted(AREAS_DIR.glob("*.json"))
    files = [f.resolve() for f in args.files] if args.files else all_files
    if not files:
        print(f"No area files found in {AREAS_DIR}", file=sys.stderr)
        return 1

    report = Report()
    checked_spots: list[dict] = []
    all_spots: list[dict] = []
    area_ids: dict[str, Path] = {}
    for path in sorted(set(all_files) | set(files)):
        scoped = Report()
        spots = validate_area(scoped, path)
        all_spots += spots
        if path in files:
            report.errors += scoped.errors
            report.warnings += scoped.warnings
            checked_spots += spots
        area_ids.setdefault(path.stem, path)
    check_cross_file(report, all_spots)

    if args.online:
        check_online(report, checked_spots)
    if args.check_links:
        check_links(report, checked_spots)

    if not args.quiet_warnings:
        for warning in report.warnings:
            print(f"warning: {warning}")
    for error in report.errors:
        print(f"error: {error}")
    fact_count = 0
    for path in files:
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            fact_count += sum(len(s.get("facts", [])) for s in data.get("spots", []) if isinstance(s, dict))
        except (json.JSONDecodeError, AttributeError, UnicodeDecodeError):
            pass
    print(f"\n{len(files)} files, {len(checked_spots)} spots, {fact_count} facts: "
          f"{len(report.errors)} errors, {len(report.warnings)} warnings")
    return 1 if report.errors else 0


if __name__ == "__main__":
    sys.exit(main())
