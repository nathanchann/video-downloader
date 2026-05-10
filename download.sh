#!/bin/bash
# Usage: ./download.sh [links.txt] [output_dir] [max_parallel]
# Routes TikTok / YouTube / Instagram links through the right tool + flags.
#   - TikTok:    yt-dlp + curl_cffi impersonation (no watermark)
#   - YouTube:   yt-dlp + Chrome cookies + bgutil PO token (handles SABR/403)
#   - Instagram: yt-dlp first; falls back to gallery-dl on failure

set -u

LINKS="${1:-links.txt}"
OUT="${2:-downloads}"
MAX_JOBS="${3:-3}"
YTDLP="$HOME/.local/bin/yt-dlp"
GDL="$HOME/.local/bin/gallery-dl"
COOKIE_BROWSER="chrome"  # safari is sandboxed on macOS; use chrome/firefox/brave
BGUTIL_SCRIPT="$HOME/dev/bgutil/server/build/generate_once.js"
OUT_TEMPLATE="%(uploader)s_%(id)s.%(ext)s"

if [ ! -f "$LINKS" ]; then
    echo "Error: $LINKS not found"
    exit 1
fi

mkdir -p "$OUT"

TIKTOK_LOCK="${TMPDIR:-/tmp}/video-dl-tiktok.lock.$$"

tiktok_lock_acquire() {
    while ! mkdir "$TIKTOK_LOCK" 2>/dev/null; do
        sleep 0.3
    done
}
tiktok_lock_release() {
    rmdir "$TIKTOK_LOCK" 2>/dev/null
}

download_tiktok() {
    local url="$1"
    if [[ "$url" == *"vt.tiktok.com"* ]]; then
        local resolved
        resolved=$(curl -Ls -o /dev/null -w "%{url_effective}" "$url" 2>/dev/null)
        [[ -n "$resolved" && "$resolved" != "$url" ]] && url="$resolved"
    fi
    # Serialize TikTok runs: curl_cffi has memory bugs under parallel load on Python 3.14
    tiktok_lock_acquire
    local rc=0
    "$YTDLP" "$url" \
        --impersonate "safari" \
        --concurrent-fragments 1 \
        -o "$OUT/$OUT_TEMPLATE" \
        --merge-output-format mp4 \
        --no-warnings || rc=$?
    tiktok_lock_release
    return $rc
}

download_youtube() {
    "$YTDLP" "$1" \
        --cookies-from-browser "$COOKIE_BROWSER" \
        --extractor-args "youtubepot-bgutilscript:script_path=$BGUTIL_SCRIPT" \
        -o "$OUT/$OUT_TEMPLATE" \
        -f "bv*[vcodec^=avc1]+ba[ext=m4a]/b[ext=mp4]/bv*+ba/b" \
        --merge-output-format mp4 \
        --no-warnings
}

download_instagram() {
    "$YTDLP" "$1" \
        --cookies-from-browser "$COOKIE_BROWSER" \
        -o "$OUT/$OUT_TEMPLATE" \
        --merge-output-format mp4 \
        --no-warnings && return 0
    echo "  yt-dlp failed, retrying with gallery-dl..."
    "$GDL" -d "$OUT" "$1"
}

dispatch() {
    local url="$1"
    case "$url" in
        *tiktok.com*|*vt.tiktok.com*) download_tiktok "$url" ;;
        *youtube.com*|*youtu.be*) download_youtube "$url" ;;
        *instagram.com*)          download_instagram "$url" ;;
        *) echo "  unknown platform — trying yt-dlp generic"
           "$YTDLP" "$url" -o "$OUT/$OUT_TEMPLATE" --no-warnings ;;
    esac
}

FAILED_FILE="$(mktemp)"
trap 'rm -f "$FAILED_FILE"; rmdir "$TIKTOK_LOCK" 2>/dev/null' EXIT
TOTAL=0
MAX_ATTEMPTS=5

run_with_retry() {
    local url="$1"
    local attempt
    echo ""
    echo "→ $url"
    for ((attempt=1; attempt<=MAX_ATTEMPTS; attempt++)); do
        if dispatch "$url"; then
            return 0
        fi
        echo "  attempt $attempt failed for $url"
        sleep 2
    done
    echo "  giving up on $url"
    echo "$url" >> "$FAILED_FILE"
    return 1
}

while IFS= read -r line || [ -n "$line" ]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    url=$(grep -oE 'https?://[^[:space:]]+' <<< "$line" | head -1)
    [[ -z "$url" ]] && continue
    TOTAL=$((TOTAL + 1))

    run_with_retry "$url" &

    while (( $(jobs -rp | wc -l) >= MAX_JOBS )); do
        sleep 0.3
    done
done < "$LINKS"

wait

FAIL_COUNT=0
[ -s "$FAILED_FILE" ] && FAIL_COUNT=$(wc -l < "$FAILED_FILE" | tr -d ' ')
SUCCESS_COUNT=$((TOTAL - FAIL_COUNT))

echo ""
echo "Done. Files in: $OUT/"
echo ""
echo "$SUCCESS_COUNT/$TOTAL downloaded successfully, $FAIL_COUNT failed"

if [ "$FAIL_COUNT" -gt 0 ]; then
    RETRY_OUT="$OUT/failed.txt"
    cp "$FAILED_FILE" "$RETRY_OUT"
    echo ""
    echo "Failed link(s):"
    sed 's/^/  - /' "$RETRY_OUT"
    echo ""
    echo "Saved failed URLs to: $RETRY_OUT"
    echo "Re-run with: $0 $RETRY_OUT $OUT $MAX_JOBS"
    exit 1
fi
