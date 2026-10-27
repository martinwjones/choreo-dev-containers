#!/bin/bash
# Renders every docs/*.dot diagram to PNG and SVG with Graphviz in a throwaway container,
# so Graphviz doesn't need to be installed in the Dev Container.
set -euo pipefail
DOCS="$(cd "$(dirname "$0")" && pwd)"
docker run --rm -v "$DOCS:/docs" -w /docs alpine:3.21 sh -c '
  apk add -q graphviz font-dejavu >/dev/null
  for f in *.dot; do
    dot -Tpng -Gdpi=150 "$f" -o "${f%.dot}.png"
    dot -Tsvg "$f" -o "${f%.dot}.svg"
    echo "rendered ${f%.dot}.png and ${f%.dot}.svg"
  done'
