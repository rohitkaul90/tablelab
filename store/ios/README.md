# App Store (iOS) assets

Source of truth for what is uploaded to App Store Connect (app Apple ID 6824665110).
Listing copy lives in `launch/STORE_LISTING.md` (App Store section).

## screenshots/ — 1179×2556, "iPhone with Dynamic Island (medium display)" slot

Uploaded 2026-10-21 for 1.10.1 (build 18), in this order (search results show the first three):

| # | File | Scene |
|---|---|---|
| 1 | `01-stats.png` | Stats tab, cash vs tournament summary |
| 2 | `02-replayer.png` | Hand replayer, river, 9-max |
| 3 | `03-ai-coaching.png` | AI hand coaching |
| 4 | `04-sessions.png` | Sessions list |
| 5 | `05-hands.png` | Hands tab |
| 6 | `06-study.png` | Study tab (GTO explorer) |

App Store Connect's current layout has ONE required iPhone slot (accepts 1179×2556 or
1206×2622) and scales down for smaller devices; the old 6.9"/6.5" slots are gone.

**Reproduce:** capture on the iPhone (light mode is fine; the status bar may be cropped
out), then normalise with ffmpeg: scale to 1179 wide and pad the top to 2556 using each
image's own top-edge colour. Never centre-crop: it clips the right edge of the UI.

```bash
hex=$(ffmpeg -v error -i in.PNG -vf "crop=1:1:12:12" -f rawvideo -pix_fmt rgb24 - | od -An -tx1 | tr -d ' \n')
ffmpeg -y -i in.PNG -vf "scale=1179:-1:flags=lanczos,pad=1179:2556:0:(oh-ih):color=0x$hex" out.png
```

## header/ — 3840×1646 product-page header

`header-3840x1646.png` is rendered from `header.html` (app icon + wordmark + landing-page
headline). Edit the HTML, then re-render with headless Chrome from the repo root:

```bash
# Git Bash on Windows: Chrome needs C:/... paths, not /c/... (hence cygpath -m)
W=$(cygpath -m "$PWD")
"/c/Program Files/Google/Chrome/Application/chrome.exe" --headless=new --disable-gpu \
  --hide-scrollbars --force-device-scale-factor=1 --window-size=3840,1646 \
  --screenshot="$W/store/ios/header/header-3840x1646.png" \
  "file:///$W/store/ios/header/header.html"
```
(Verified 2026-10-21: the re-render is pixel-identical to the committed PNG.)

Keep text inside the middle of the frame; App Store crops the edges on narrower devices.
The "Search Results" asset slot is intentionally left empty (the first screenshot serves).
