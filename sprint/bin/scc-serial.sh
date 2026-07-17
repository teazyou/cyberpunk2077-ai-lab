#!/usr/bin/env bash
# Serial scc compile gate — the ONLY sanctioned way to compile in this sprint.
# Takes a global lock, refreshes staging from sprint/impl, compiles the FULL
# staging script set (game copy incl. all enabled mods). Never touches the
# live game directory.
set -u
GAME="/Users/teazyou/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077"
ROOT="/Users/teazyou/dev/tmp-claude/cyberpunk/sprint"
SRC="$ROOT/impl/custom-enemy-overhaul"
DST="$ROOT/staging/r6/scripts/custom-enemy-overhaul"
LOCK="/tmp/enemy-overhaul-scc.lock.d"

waited=0
until mkdir "$LOCK" 2>/dev/null; do
  sleep 2
  waited=$((waited + 2))
  if [ "$waited" -ge 300 ]; then
    echo "[scc-serial] stale lock (>300s) — stealing" >&2
    rm -rf "$LOCK"
    waited=0
  fi
done
trap 'rmdir "$LOCK" 2>/dev/null' EXIT INT TERM

mkdir -p "$SRC" "$DST"
rsync -a --delete "$SRC/" "$DST/"
"$GAME/engine/tools/scc" -compile "$ROOT/staging/r6/scripts"
rc=$?
echo "[scc-serial] exit=$rc"
exit $rc
