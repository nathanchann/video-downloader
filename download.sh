#!/bin/bash
# Usage: ./download.sh [links.txt] [output_dir]
# Routes TikTok / YouTube / Instagram links through the right tool + flags.
#   - TikTok:    yt-dlp + curl_cffi impersonation (no watermark)
#   - YouTube:   yt-dlp + Safari cookies (handles SABR/403 in 2026)
#   - Instagram: yt-dlp first; falls back to gallery-dl on failure

set -u

LINKS="${1:-links.txt}"
OUT="${2:-downloads}"
YTDLP="$HOME/.local/bin/yt-dlp"
GDL="$HOME/.local/bin/gallery-dl"
COOKIE_BROWSER="chrome"  # safari is sandboxed on macOS; use chrome/firefox/brave
BGUTIL_SCRIPT="$HOME/dev/bgutil/server/build/generate_once.js"

if [ ! -f "$LINKS" ]; then
    echo "Error: $LINKS not found"
    exit 1
fi

mkdir -p "$OUT"

download_tiktok() {
    "$YTDLP" "$1" \
        --impersonate "Safari-26.0:Ios-26.0" \
        -o "$OUT/tiktok/%(uploader)s_%(id)s.%(ext)s" \
        --merge-output-format mp4 \
        --no-warnings
}

download_youtube() {
    "$YTDLP" "$1" \
        --cookies-from-browser "$COOKIE_BROWSER" \
        --extractor-args "youtubepot-bgutilscript:script_path=$BGUTIL_SCRIPT" \
        -o "$OUT/youtube/%(uploader)s_%(id)s.%(ext)s" \
        -f "bv*+ba/b" \
        --no-warnings
}

download_instagram() {
    "$YTDLP" "$1" \
        --cookies-from-browser "$COOKIE_BROWSER" \
        -o "$OUT/instagram/%(uploader)s_%(id)s.%(ext)s" \
        --merge-output-format mp4 \
        --no-warnings && return 0
    echo "  yt-dlp failed, retrying with gallery-dl..."
    "$GDL" -d "$OUT/instagram" "$1"
}

while IFS= read -r url || [ -n "$url" ]; do
    [[ -z "$url" || "$url" =~ ^[[:space:]]*# ]] && continue
    url="${url%%[[:space:]]*}"

    echo ""
    echo "→ $url"
    case "$url" in
        *tiktok.com*)    download_tiktok "$url" ;;
        *youtube.com*|*youtu.be*) download_youtube "$url" ;;
        *instagram.com*) download_instagram "$url" ;;
        *) echo "  unknown platform — trying yt-dlp generic"
           "$YTDLP" "$url" -o "$OUT/other/%(extractor)s_%(id)s.%(ext)s" --no-warnings ;;
    esac
done < "$LINKS"

echo ""
echo "Done. Files in: $OUT/"
