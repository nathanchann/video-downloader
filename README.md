# video-downloader

A small bash script that batch-downloads videos from TikTok, YouTube, and Instagram given a list of URLs. Routes each link through the right tool + flags so watermarks are stripped (TikTok) and 2026 SABR/PO-token blocks are handled (YouTube).

## What it does

| Platform | Tool | Notes |
|---|---|---|
| TikTok | `yt-dlp` + `curl_cffi` impersonation | No watermark |
| YouTube | `yt-dlp` + Chrome cookies + bgutil PO-token script | Handles SABR (Shorts and regular videos) |
| Instagram | `yt-dlp` (primary), `gallery-dl` (fallback) | Public reels work; private accounts need cookies |
| Other | `yt-dlp` generic extractor | ~1000 sites supported |

## Install

Tested on macOS (Apple Silicon).

```bash
# 1. Core tools
brew install pipx ffmpeg node deno
pipx ensurepath

# 2. yt-dlp with impersonation extras + gallery-dl
pipx install "yt-dlp[default,curl-cffi]"
pipx install gallery-dl

# 3. bgutil PO-token plugin (Python side)
pipx inject yt-dlp bgutil-ytdlp-pot-provider

# 4. bgutil generator script (Node side) — required for YouTube
git clone --depth 1 https://github.com/Brainicism/bgutil-ytdlp-pot-provider.git ~/dev/bgutil
cd ~/dev/bgutil/server
npm ci
npx tsc

# 5. This repo
git clone https://github.com/nathanchann/video-downloader.git ~/dev/video-downloader
chmod +x ~/dev/video-downloader/download.sh
```

If your bgutil clone lives elsewhere, edit `BGUTIL_SCRIPT` near the top of `download.sh`.

## Usage

```bash
cd ~/dev/video-downloader
cp links.example.txt links.txt
# paste URLs into links.txt, one per line
./download.sh links.txt
```

Files land in `./downloads/<platform>/<uploader>_<id>.<ext>`.

Optional second arg sets the output dir: `./download.sh links.txt /tmp/out`.

## Cookies

Default browser is Chrome (Safari is sandboxed on macOS — its cookies aren't readable without Full Disk Access). Edit `COOKIE_BROWSER` in the script if you use Firefox / Brave / Edge.

For private Instagram content, log into Instagram in your browser first — the script will pick up the session cookies automatically.

## Permissions on macOS

The first time `curl_cffi` makes a network request, macOS may prompt Python (or your terminal) for **Local Network** access. Allow it. If you accidentally deny, re-enable under System Settings → Privacy & Security → Local Network.

## Stack versions used during development

- yt-dlp 2026.03.17
- curl_cffi 0.14.0
- gallery-dl 1.32.0
- ffmpeg 8.1
- node 25, deno (for EJS JS challenge solving)
- bgutil-ytdlp-pot-provider 1.3.1
