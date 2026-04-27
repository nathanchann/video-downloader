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

download_tiktok() {
    "$YTDLP" "$1" \
        --impersonate "safari" \
        -o "$OUT/$OUT_TEMPLATE" \
        --merge-output-format mp4 \
        --no-warnings
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
    echo ""
    echo "→ $url"
    case "$url" in
        *tiktok.com*)             download_tiktok "$url" ;;
        *youtube.com*|*youtu.be*) download_youtube "$url" ;;
        *instagram.com*)          download_instagram "$url" ;;
        *) echo "  unknown platform — trying yt-dlp generic"
           "$YTDLP" "$url" -o "$OUT/$OUT_TEMPLATE" --no-warnings ;;
    esac
}

while IFS= read -r url || [ -n "$url" ]; do
    [[ -z "$url" || "$url" =~ ^[[:space:]]*# ]] && continue
    url="${url%%[[:space:]]*}"

    dispatch "$url" &

    while (( $(jobs -rp | wc -l) >= MAX_JOBS )); do
        sleep 0.3
    done
done < "$LINKS"

wait

echo ""
echo "Done. Files in: $OUT/"
