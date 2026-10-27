"""Loads the Textual Chef recipe feed into Qdrant.

Fetches https://textualchef.com/recipes.json (one request; individual recipe pages are
not fetched, to spare the site), embeds one document per recipe with Ollama, and
upserts it into the Qdrant collection with the metadata as filterable payload.
Ingredients come from the feed itself: the main ingredient plus those named in the
description.

Standard library only, so it runs in a plain python image. Safe to re-run: point ids
are derived from the recipe id, so existing points are overwritten in place.
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid

FEED_URL = os.environ.get("FEED_URL", "https://textualchef.com/recipes.json")
OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://host.lima.internal:11434").rstrip("/")
EMBED_MODEL = os.environ.get("EMBED_MODEL", "nomic-embed-text")
QDRANT_URL = os.environ.get("QDRANT_URL", "http://qdrant:6333").rstrip("/")
COLLECTION = os.environ.get("COLLECTION", "recipes")
LIMIT = int(os.environ.get("LIMIT", "0"))  # 0 = all recipes; set for a quick test run
EMBED_BATCH = 32
VECTOR_SIZE = 768  # nomic-embed-text

# Payload fields that get a Qdrant index, so the agent can filter on them.
KEYWORD_FIELDS = ["cuisine", "course", "method", "difficulty", "mainIngredient", "diets", "restrictions", "tags"]
INTEGER_FIELDS = ["totalTimeMinutes", "caloriesPerServing", "servings"]

ID_NAMESPACE = uuid.UUID("5b3c1f0e-7d2a-4c1e-9a55-2f3e6b8d0c11")


def log(msg: str) -> None:
    print(f"[ingest] {msg}", flush=True)


def http(method: str, url: str, body: object | None = None, timeout: int = 120) -> object:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Content-Type": "application/json",
        "User-Agent": "wso2-lab-recipe-ingest/1.0",
    })
    with urllib.request.urlopen(req, timeout=timeout) as res:
        raw = res.read()
    return json.loads(raw) if raw else None


def document(r: dict) -> str:
    """The text that gets embedded: what a searcher would describe."""
    parts = [
        f"{r['name']}. {r.get('description', '')}",
        f"Cuisine: {r.get('cuisine')}. Course: {r.get('course')}. Method: {r.get('method')}.",
        f"Main ingredient: {r.get('mainIngredient')}. Difficulty: {r.get('difficulty')}.",
    ]
    if r.get("diets") or r.get("restrictions"):
        parts.append("Suitable for: " + ", ".join(r.get("diets", []) + r.get("restrictions", [])) + ".")
    if r.get("tags"):
        parts.append("Tags: " + ", ".join(r["tags"]) + ".")
    return "search_document: " + " ".join(parts)


def embed(texts: list[str]) -> list[list[float]]:
    res = http("POST", f"{OLLAMA_URL}/v1/embeddings", {"model": EMBED_MODEL, "input": texts}, timeout=300)
    return [d["embedding"] for d in sorted(res["data"], key=lambda d: d["index"])]


def ensure_collection() -> None:
    try:
        http("GET", f"{QDRANT_URL}/collections/{COLLECTION}")
        log(f"collection '{COLLECTION}' exists; updating in place")
    except urllib.error.HTTPError as exc:
        if exc.code != 404:
            raise
        log(f"creating collection '{COLLECTION}'")
        http("PUT", f"{QDRANT_URL}/collections/{COLLECTION}", {"vectors": {"size": VECTOR_SIZE, "distance": "Cosine"}})
    for f in KEYWORD_FIELDS:
        http("PUT", f"{QDRANT_URL}/collections/{COLLECTION}/index?wait=true", {"field_name": f, "field_schema": "keyword"})
    for f in INTEGER_FIELDS:
        http("PUT", f"{QDRANT_URL}/collections/{COLLECTION}/index?wait=true", {"field_name": f, "field_schema": "integer"})
    # Word-level matching for ingredient searches ("chickpeas", "spinach").
    http("PUT", f"{QDRANT_URL}/collections/{COLLECTION}/index?wait=true", {
        "field_name": "ingredientsText",
        "field_schema": {"type": "text", "tokenizer": "word", "lowercase": True},
    })


def main() -> int:
    log(f"fetching {FEED_URL}")
    feed = http("GET", FEED_URL)
    recipes = feed.get("recipes", [])
    if LIMIT:
        recipes = recipes[:LIMIT]
    if not recipes:
        log("feed has no recipes")
        return 1
    log(f"{len(recipes)} recipes in the feed (updated {feed.get('updated')})")

    for r in recipes:
        # The feed has no ingredient list, so ingredient searches match the main ingredient,
        # the recipe name and the description ("roasted garlic blended with potato and broth").
        r["ingredientsText"] = f"{r.get('mainIngredient', '')} {r['name']} {r.get('description', '')}"

    ensure_collection()

    start = time.time()
    for i in range(0, len(recipes), EMBED_BATCH):
        batch = recipes[i : i + EMBED_BATCH]
        vectors = embed([document(r) for r in batch])
        points = [
            {"id": str(uuid.uuid5(ID_NAMESPACE, r["id"])), "vector": v, "payload": r}
            for r, v in zip(batch, vectors)
        ]
        http("PUT", f"{QDRANT_URL}/collections/{COLLECTION}/points?wait=true", {"points": points})
        done = i + len(batch)
        if done % (EMBED_BATCH * 20) == 0 or done == len(recipes):
            log(f"embedded and stored {done}/{len(recipes)} ({time.time() - start:.0f}s)")

    count = http("POST", f"{QDRANT_URL}/collections/{COLLECTION}/points/count", {"exact": True})["result"]["count"]
    log(f"done: collection '{COLLECTION}' holds {count} recipes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
