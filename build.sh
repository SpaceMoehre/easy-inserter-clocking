#!/usr/bin/env bash
# Builds mod-portal zips for each supported Factorio version from the shared
# source. control.lua detects the running game version at runtime, so the only
# per-target difference is info.json (factorio_version, version, base dependency).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME="easy-inserter-clocking"
DIST="$ROOT/dist"
FILES=(control.lua README.md LICENSE thumbnail.png)

# "factorio_version:mod_version" per target. Mod versions must be unique, and the
# portal expects each new upload to be higher than the previous one, so keep them
# on a single ascending line regardless of which game version they target.
# 2.0 and 2.1 share the same blueprint API, so control.lua's v2 path serves both.
TARGETS=("1.1:0.9.0" "2.0:1.0.1" "2.1:1.0.2")

build() {
    local fver="${1%%:*}" mver="${1##*:}"
    local stage="$DIST/.stage/$NAME"
    rm -rf "$DIST/.stage"; mkdir -p "$stage/locale"
    cp "${FILES[@]/#/$ROOT/}" "$stage/"
    cp -r "$ROOT/locale/." "$stage/locale/"
    python3 - "$ROOT/info.json" "$stage/info.json" "$fver" "$mver" <<'PY'
import json, sys
src, dst, fver, mver = sys.argv[1:5]
d = json.load(open(src))
d["factorio_version"] = fver
d["version"] = mver
d["dependencies"] = ["base >= %s.0" % fver]
json.dump(d, open(dst, "w"), indent=2)
PY
    local out="$DIST/${NAME}_${mver}_factorio-${fver}.zip"
    rm -f "$out"
    ( cd "$DIST/.stage" && zip -rq "$out" "$NAME" )
    echo "built $(basename "$out")  (factorio_version=$fver, version=$mver)"
}

mkdir -p "$DIST"
for t in "${TARGETS[@]}"; do build "$t"; done
rm -rf "$DIST/.stage"
