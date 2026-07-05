#!/bin/bash
# mod-tool.sh — helper for the Cyberpunk mod workspace.
#   info <mod-id>              fetch Nexus page via r.jina.ai, save full page, print digest
#   grab <slug> <glob>         wait for a browser download, archive it, extract to staging
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
    cat >&2 <<'EOF'
Usage:
  mod-tool.sh info <mod-id>
      Fetch https://www.nexusmods.com/cyberpunk2077/mods/<mod-id> via r.jina.ai,
      save the full markdown to mods/pages/<mod-id>-pages.md and print a digest
      (title / category / stats / description / Nexus requirements).

  mod-tool.sh grab <slug> <downloads-glob>
      Wait (poll 2s, timeout 180s) for a finished download in ~/Downloads matching
      <downloads-glob>, move it to mods/downloaded/<slug>.<ext>, extract it with
      bsdtar into mods/staging/<slug>/, and print the extracted file list
      (paths relative to mods/staging/<slug>/).
EOF
    exit 1
}

info_cmd() {
    local id="${1:-}"
    [ -n "$id" ] || usage

    local pages_dir="$ROOT/mods/pages"
    local page_file="$pages_dir/${id}-pages.md"
    mkdir -p "$pages_dir"

    if ! curl -s "https://r.jina.ai/https://www.nexusmods.com/cyberpunk2077/mods/${id}" -o "$page_file"; then
        echo "ERROR: curl failed fetching mod ${id} via r.jina.ai" >&2
        exit 1
    fi

    local line_count
    line_count=$(wc -l < "$page_file" | tr -d '[:space:]')
    if [ "$line_count" -lt 100 ]; then
        echo "ERROR: fetched content is suspiciously short (${line_count} lines) — Cloudflare/jina likely failed. Raw output kept at ${page_file}" >&2
        exit 1
    fi

    awk '
        # Replace every [text](url) markdown link with just "text".
        function delink(s,    inner) {
            while (match(s, /\[[^]]*\]\([^)]*\)/)) {
                inner = substr(s, RSTART + 1)
                inner = substr(inner, 1, index(inner, "]") - 1)
                s = substr(s, 1, RSTART - 1) inner substr(s, RSTART + RLENGTH)
            }
            return s
        }
        function rtrim(s) { sub(/[ \t]+$/, "", s); return s }

        NR == 1 && /^Title: / { title = $0; next }

        # state 0: before the stat block. Track the latest breadcrumb category link;
        # the real content anchor is the "*   Endorsements" stat line (the first
        # "# " H1 can be a "# Please log in" banner, so it is not a safe anchor).
        state == 0 {
            if ($0 ~ /categoryName=/ && match($0, /\[[^]]*\]/))
                category = substr($0, RSTART + 1, RLENGTH - 2)
            if ($0 ~ /^\*   Endorsements/) {
                state = 1
                stats = rtrim(delink($0))
                next
            }
            next
        }

        # state 1: collecting the remaining stat lines (contiguous block).
        state == 1 {
            if ($0 ~ /^\*   (Unique DLs|Total DLs|Total views|Version)/) {
                stats = stats "\n" rtrim(delink($0))
                next
            }
            state = 2
        }

        # state 2: waiting for the About header.
        state == 2 && /^## About this mod$/ { state = 3; next }

        # state 3: first non-empty line after the About header is the description.
        state == 3 {
            if ($0 ~ /^[ \t]*$/) next
            about = rtrim(delink($0))
            state = 4
            next
        }

        # state 4: waiting for the Nexus requirements header (may be absent).
        state == 4 && /^### Nexus requirements$/ { state = 5; next }

        # state 5: skip blanks, then collect the markdown table lines.
        state == 5 {
            if ($0 ~ /^\|/) {
                reqs = (reqs == "" ? "" : reqs "\n") rtrim(delink($0))
                intable = 1
                next
            }
            if (intable) { state = 6 }   # first non-table line after the table
            next
        }

        END {
            print (title != "" ? title : "Title: (not found)")
            print "Category: " (category != "" ? category : "(not found)")
            if (stats != "") print stats
            print "About: " (about != "" ? about : "(not found)")
            print "Nexus requirements:"
            print (reqs != "" ? reqs : "none listed")
        }
    ' "$page_file"

    printf 'Full content in `mods/pages/%s-pages.md`\n' "$id"
}

grab_cmd() {
    local slug="${1:-}"
    local glob="${2:-}"
    [ -n "$slug" ] && [ -n "$glob" ] || usage

    local dl_dir="$HOME/Downloads"
    local timeout=180
    local interval=2
    local elapsed=0
    local candidate="" prev_file="" prev_size=""

    while :; do
        local partial file
        partial=$(find "$dl_dir" -maxdepth 1 \( -name "${glob}*.crdownload" -o -name "${glob}*.download" \) -print 2>/dev/null | head -n 1)
        file=$(find "$dl_dir" -maxdepth 1 -type f -name "$glob" ! -name '*.crdownload' ! -name '*.download' -print 2>/dev/null | head -n 1)

        if [ -n "$file" ] && [ -z "$partial" ]; then
            local size
            size=$(stat -f %z "$file")
            if [ "$file" = "$prev_file" ] && [ "$size" = "$prev_size" ]; then
                candidate="$file"
                break
            fi
            prev_file="$file"
            prev_size="$size"
        else
            prev_file=""
            prev_size=""
        fi

        if [ "$elapsed" -ge "$timeout" ]; then
            echo "ERROR: timed out after ${timeout}s waiting for a finished download matching \"${glob}\" in ${dl_dir}" >&2
            exit 1
        fi
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    local base ext dest
    base="$(basename "$candidate")"
    ext="${base##*.}"
    [ "$ext" = "$base" ] && ext="zip"   # no extension: default to zip
    dest="$ROOT/mods/downloaded/${slug}.${ext}"

    mkdir -p "$ROOT/mods/downloaded"
    mv -f "$candidate" "$dest"

    local staging="$ROOT/mods/staging/${slug}"
    rm -rf "$staging"
    mkdir -p "$staging"

    if ! bsdtar -xf "$dest" -C "$staging"; then
        echo "ERROR: bsdtar failed to extract ${dest} into ${staging}" >&2
        exit 1
    fi

    (cd "$staging" && find . -type f | sed 's|^\./||' | sort)
}

cmd="${1:-}"
[ -n "$cmd" ] || usage
shift

case "$cmd" in
    info) info_cmd "$@" ;;
    grab) grab_cmd "$@" ;;
    *)    usage ;;
esac
