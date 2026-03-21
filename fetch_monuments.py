#!/usr/bin/env python3
"""Fetch Turkish cultural heritage monuments from Wikidata and save as JSON."""

import json
import time
import urllib.request
import urllib.parse
import urllib.error
from datetime import date

import os

SPARQL_ENDPOINT = "https://query.wikidata.org/sparql"
BATCH_SIZE = 5000
MAX_OFFSET = 60000  # safety cap
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_PATH = os.path.join(SCRIPT_DIR, "WLMTurkey", "Resources", "monuments.json")

SPARQL_TEMPLATE = """
SELECT DISTINCT
  ?item
  ?itemLabelTR ?itemLabelEN
  ?lat ?lon
  ?image
  ?osmRelation ?osmWay
  ?instanceOfLabelTR ?instanceOfLabelEN
  ?adminEntityLabelTR ?adminEntityLabelEN
  ?heritageDesignationLabelTR ?heritageDesignationLabelEN
  ?architectLabelTR ?architectLabelEN
  ?archStyleLabelTR ?archStyleLabelEN
WHERE {{
  ?item wdt:P11729 [] ;
        wdt:P17 wd:Q43 ;
        wdt:P625 ?coord .
  BIND(geof:latitude(?coord) AS ?lat)
  BIND(geof:longitude(?coord) AS ?lon)

  OPTIONAL {{ ?item wdt:P18 ?image . }}
  OPTIONAL {{ ?item wdt:P402 ?osmRelation . }}
  OPTIONAL {{ ?item wdt:P10689 ?osmWay . }}

  OPTIONAL {{
    ?item wdt:P31 ?instanceOf .
    ?instanceOf rdfs:label ?instanceOfLabelTR . FILTER(LANG(?instanceOfLabelTR) = "tr")
    OPTIONAL {{ ?instanceOf rdfs:label ?instanceOfLabelEN . FILTER(LANG(?instanceOfLabelEN) = "en") }}
  }}

  OPTIONAL {{
    ?item wdt:P131 ?adminEntity .
    ?adminEntity rdfs:label ?adminEntityLabelTR . FILTER(LANG(?adminEntityLabelTR) = "tr")
    OPTIONAL {{ ?adminEntity rdfs:label ?adminEntityLabelEN . FILTER(LANG(?adminEntityLabelEN) = "en") }}
  }}

  OPTIONAL {{
    ?item wdt:P5816 ?heritageDesignation .
    ?heritageDesignation rdfs:label ?heritageDesignationLabelTR . FILTER(LANG(?heritageDesignationLabelTR) = "tr")
    OPTIONAL {{ ?heritageDesignation rdfs:label ?heritageDesignationLabelEN . FILTER(LANG(?heritageDesignationLabelEN) = "en") }}
  }}

  OPTIONAL {{
    ?item wdt:P84 ?architect .
    ?architect rdfs:label ?architectLabelTR . FILTER(LANG(?architectLabelTR) = "tr")
    OPTIONAL {{ ?architect rdfs:label ?architectLabelEN . FILTER(LANG(?architectLabelEN) = "en") }}
  }}

  OPTIONAL {{
    ?item wdt:P149 ?archStyle .
    ?archStyle rdfs:label ?archStyleLabelTR . FILTER(LANG(?archStyleLabelTR) = "tr")
    OPTIONAL {{ ?archStyle rdfs:label ?archStyleLabelEN . FILTER(LANG(?archStyleLabelEN) = "en") }}
  }}

  OPTIONAL {{ ?item rdfs:label ?itemLabelTR . FILTER(LANG(?itemLabelTR) = "tr") }}
  OPTIONAL {{ ?item rdfs:label ?itemLabelEN . FILTER(LANG(?itemLabelEN) = "en") }}
}}
ORDER BY ?item
LIMIT {limit}
OFFSET {offset}
"""


def run_query(sparql: str, retries: int = 3) -> list:
    """Execute a SPARQL query against Wikidata and return results."""
    params = urllib.parse.urlencode({"query": sparql, "format": "json"})
    url = f"{SPARQL_ENDPOINT}?{params}"
    headers = {
        "User-Agent": "WLMTurkeyBot/1.0 (https://github.com/Sadrettin86/WLMTurkey)",
        "Accept": "application/sparql-results+json",
    }
    req = urllib.request.Request(url, headers=headers)

    for attempt in range(retries):
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                return data["results"]["bindings"]
        except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError) as e:
            print(f"  Attempt {attempt + 1} failed: {e}")
            if attempt < retries - 1:
                wait = 30 * (attempt + 1)
                print(f"  Waiting {wait}s before retry...")
                time.sleep(wait)
            else:
                raise


def extract_filename(uri: str) -> str:
    """Extract filename from Wikimedia Commons URI."""
    if not uri:
        return ""
    # URI like http://commons.wikimedia.org/wiki/Special:FilePath/Filename.jpg
    parts = uri.rsplit("/", 1)
    if len(parts) == 2:
        return urllib.parse.unquote(parts[1])
    return ""


def get_val(binding: dict, key: str) -> str:
    """Get string value from a SPARQL binding."""
    if key in binding:
        return binding[key]["value"]
    return ""


def qid(uri: str) -> str:
    """Extract QID from Wikidata URI."""
    return uri.rsplit("/", 1)[-1] if uri else ""


def main():
    print("Fetching Turkish monuments from Wikidata...")
    all_bindings = []
    offset = 0

    while offset <= MAX_OFFSET:
        query = SPARQL_TEMPLATE.format(limit=BATCH_SIZE, offset=offset)
        print(f"Batch: offset={offset}, limit={BATCH_SIZE}")
        results = run_query(query)
        print(f"  Got {len(results)} rows")
        all_bindings.extend(results)

        if len(results) < BATCH_SIZE:
            print("  Last batch (fewer results than limit).")
            break

        offset += BATCH_SIZE
        time.sleep(5)  # be polite to the endpoint

    print(f"Total rows fetched: {len(all_bindings)}")

    # Deduplicate and merge by QID - keep first non-empty value for each field
    monuments_map: dict[str, dict] = {}

    for b in all_bindings:
        item_uri = get_val(b, "item")
        q = qid(item_uri)
        if not q:
            continue

        if q not in monuments_map:
            monuments_map[q] = {
                "q": q,
                "n": "",
                "ne": "",
                "la": 0.0,
                "lo": 0.0,
                "p": False,
                "i": "",
                "r": "",
                "w": "",
                "t": "",
                "te": "",
                "a": "",
                "ae": "",
                "h": "",
                "he": "",
                "ar": "",
                "are": "",
                "s": "",
                "se": "",
            }

        m = monuments_map[q]

        # Always update coords (they should be the same across rows)
        lat_str = get_val(b, "lat")
        lon_str = get_val(b, "lon")
        if lat_str:
            m["la"] = round(float(lat_str), 6)
        if lon_str:
            m["lo"] = round(float(lon_str), 6)

        # Labels
        if not m["n"]:
            m["n"] = get_val(b, "itemLabelTR")
        if not m["ne"]:
            m["ne"] = get_val(b, "itemLabelEN")

        # Image
        img = get_val(b, "image")
        if img and not m["i"]:
            m["i"] = extract_filename(img)
            m["p"] = True

        # OSM
        if not m["r"]:
            m["r"] = get_val(b, "osmRelation")
        if not m["w"]:
            m["w"] = get_val(b, "osmWay")

        # Instance of
        if not m["t"]:
            m["t"] = get_val(b, "instanceOfLabelTR")
        if not m["te"]:
            m["te"] = get_val(b, "instanceOfLabelEN")

        # Admin entity
        if not m["a"]:
            m["a"] = get_val(b, "adminEntityLabelTR")
        if not m["ae"]:
            m["ae"] = get_val(b, "adminEntityLabelEN")

        # Heritage designation
        if not m["h"]:
            m["h"] = get_val(b, "heritageDesignationLabelTR")
        if not m["he"]:
            m["he"] = get_val(b, "heritageDesignationLabelEN")

        # Architect
        if not m["ar"]:
            m["ar"] = get_val(b, "architectLabelTR")
        if not m["are"]:
            m["are"] = get_val(b, "architectLabelEN")

        # Architectural style
        if not m["s"]:
            m["s"] = get_val(b, "archStyleLabelTR")
        if not m["se"]:
            m["se"] = get_val(b, "archStyleLabelEN")

    # Build final list sorted by QID
    monuments = sorted(monuments_map.values(), key=lambda x: int(x["q"][1:]))

    # Set p=True if image exists
    for m in monuments:
        m["p"] = bool(m["i"])

    output = {
        "version": str(date.today()),
        "count": len(monuments),
        "monuments": monuments,
    }

    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False)

    print(f"Saved {len(monuments)} monuments to {OUTPUT_PATH}")
    print(f"File size: {round(os.path.getsize(OUTPUT_PATH) / 1024 / 1024, 2)} MB")


if __name__ == "__main__":
    import os
    main()
