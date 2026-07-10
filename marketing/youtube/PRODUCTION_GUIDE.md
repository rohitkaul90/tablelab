# Production Guide — From Files to a Live YouTube Video

*The end-to-end process for producing Idea #1 (and every video after). Faceless brand channel, solo, Windows.*

**Mental model:** The **voiceover is the spine.** Record it first → drop it on the editor timeline → layer every visual on top, timed to the words, using `idea-01-bankroll-shotlist.md` as the map. You create images in Phase 2 and *place* them in Phase 3.

**The 6 phases:** Setup → Record VO → Gather visuals → Edit → Prep thumbnail → Upload. Budget ~1–2 focused days for your first one; much faster once the system exists.

---

## PHASE 0 — One-time setup (~1 hour, only the first video)

**Install (all free, Windows):**
- **Audacity** — voiceover recording + cleanup. audacityteam.org
- **OBS Studio** — screen-record the TableLab app + blog charts. obsproject.com
- **DaVinci Resolve** (pro, steeper) *or* **CapCut Desktop** (easier, faster to learn) — video editing. *Recommendation: CapCut for your first video, Resolve later if you want more control.*
- **Canva** (free web) — text cards / stat cards, if you don't build them in the editor.

**Accounts:**
- Create the **faceless brand YouTube channel** (a Brand Account, separate from your personal `@rohitkaul1990`). YouTube → Settings → Add/manage channels → Create a new channel.
- Grab a **mic**: a USB mic (e.g. any $50–80 cardioid) is ideal, but wired earbuds with a mic or even AirPods in a quiet, soft-furnished room beat a laptop mic. **Never TTS.**

**Make a project folder:** `idea-01/` with subfolders `vo/`, `assets/`, `exports/`.

---

## PHASE 1 — Record the voiceover (Audacity, ~45–60 min)

*Why first: every visual gets cut to the audio. The VO's length also defines the video's length.*

1. **Room + mic:** quiet room, soft surfaces (curtains/bed absorb echo). Mic ~a hand's width from your mouth, slightly off-axis to avoid popping "p"s.
2. **Open Audacity → record a 5-second silence test.** Effect → Noise Reduction → "Get Noise Profile" (you'll apply it after).
3. **Record take by take** from `idea-01-bankroll-vo-readsheet.md`. One take = one block. Leave ~1s silence before/after each. Fluff a line? Clap once, pause, re-read — the clap is a visual spike you'll find easily when trimming.
4. **Hit the delivery notes:** calm-burst energy, and *land the 🔑 lines* ("a losing month becomes a non-event", "losing ten buy-ins is a Tuesday"). Record all 3 alternate opening Grabs.
5. **Clean up:** select all → Effect → Noise Reduction (apply the profile) → then Effect → Normalize to about −3 dB. Trim dead air and bad takes.
6. **Export:** File → Export → one WAV per block into `vo/` (e.g. `01-hook.wav`, `02-intro.wav` …). Stems > one big file — easier to nudge in the edit.

**Output of this phase:** clean VO stems totalling ~9 minutes.

---

## PHASE 2 — Gather & create the visuals (OBS + Canva, ~2–4 hrs)

*Now you know the exact wording and rough timing, so you build exactly what the shot list's Asset Prep Checklist calls for. Two kinds of assets:*

### A) Screen recordings (OBS Studio)
1. Open OBS → add a **Display Capture** or **Window Capture** source → set canvas to 1920×1080 (or 2560×1440 if you want crop room).
2. **Record `REC-dashboard`:** open TableLab on a **synthetic account with a realistic session history** (not empty, not your personal data). Slowly navigate Stats → Win Rate / BB100 / variance trend. Move the mouse deliberately; record 20–30s of usable footage.
3. **Record `REC-sessionlog`:** scroll the session list showing buy-in / cash-out / hours / stake.
4. **Record `REC-blog-curve`:** open `web/blog/poker-bankroll-management.html` in a browser, scroll/zoom the risk-of-ruin curve and the format bars live. (This is the easy way to "animate" the SVGs — just screen-record them in the page.)
5. Save all to `assets/`.

### B) Text & stat cards (Canva or your editor)
Build the cards from the checklist — cold-open, chapter cards (1/2/3), and the stat cards `$10,000`, `56 buy-ins ≈ 1%`, `200+ tournaments`, `91% of rake`, the formula card, the recap card.
- Brand palette: `#111811` background, `#4CAF50` green accent, white text. 1920×1080.
- Export as PNG (transparent PNG for overlays that sit on top of footage).
- Save to `assets/`.

### C) Audio bits
- Download a **royalty-free music bed** (YouTube Audio Library inside Studio, or Pixabay Music) — calm, building. One track is fine.
- Grab one **"sting" SFX** (used 3×) from the same libraries.

**Output of this phase:** an `assets/` folder with ~6 (MVP) to ~20 (full) visual files + music + SFX. The thumbnails are already done in `thumbnails/`.

---

## PHASE 3 — Edit the video (CapCut/Resolve, ~3–6 hrs) — *this is where it all comes together*

*Follow `idea-01-bankroll-shotlist.md` literally — it's a row-by-row instruction set.*

1. **New project**, 1920×1080, 30fps. Import all `vo/` stems + everything in `assets/` + music + SFX.
2. **Lay the VO spine:** drag the VO stems onto the timeline in order, back to back, small gaps where the script pauses. **This audio track is now your ruler** — its total length = your video length, and every timestamp in the shot list maps to a point on it.
3. **Layer visuals top-down, row by row through the shot list.** For each row: find that Time on the VO track, then place the named asset on a video track above it for that window. Example: at 1:40 the VO says "ten-thousand-dollar roll" → drop `CARD-10k` on screen there; at 3:40 → formula card for **≤3 seconds only**, then hard-cut to the curve.
4. **Add the motion/SFX column:** sting at 2:27, 6:30, and the Block-5 hard change; music bed underneath everything at ~−18 dB (duck it under VO); stat "pops" (scale-up animation) on each stat card.
5. **Add source lower-thirds:** a small text strip crediting Upswing / PokerNews / Primedope / Chen & Ankenman / Fiedler 2012 whenever that stat is on screen.
6. **Enforce the retention rules:** no shot >6s without a cut/zoom/text change; hook cuts every 2–3s; **formula ≤3s** (the #1 drop-off point — get this right).
7. **Watch it back once end-to-end** with fresh ears. Fix timing drift, gaps, and anywhere the visual doesn't match the word.
8. **Generate captions:** CapCut/Resolve can auto-caption → **correct the poker terms** (BB/100, buy-ins, risk of ruin) → export an **SRT file** to `exports/`.
9. **Export the video:** H.264 MP4, 1080p, ~16 Mbps, AAC audio → `exports/idea-01-final.mp4`.

**Output of this phase:** `idea-01-final.mp4` + `captions.srt`.

---

## PHASE 4 — Prep the thumbnail (5 min)

The rendered thumbnails in `thumbnails/` are 5–7 MB — **YouTube's limit is 2 MB / recommends 1280×720.**
- Go to **squoosh.app** → drag `idea-01-primary.png` → set resize to 1280×720 → export as JPEG/PNG under 2 MB.
- (Ship **Primary** for launch; hold A/B/C until the channel has a few thousand impressions.)

**Output:** `idea-01-primary-yt.jpg` (<2 MB).

---

## PHASE 5 — Upload & publish (YouTube Studio, ~20 min)

Open `idea-01-bankroll-metadata.md` in one window, Studio in the other, and copy across.

1. **studio.youtube.com → Create → Upload video** → select `idea-01-final.mp4`.
2. **Title:** paste the recommended hybrid title.
3. **Description:** paste the whole description block (it already contains the timestamps/chapters and the **UTM'd app link** — that link is your actual KPI).
4. **Thumbnail:** upload `idea-01-primary-yt.jpg`.
5. **Playlists:** create/add one (e.g. "Fix This Leak").
6. **Audience:** "No, it's not made for kids." Consider a self-applied 18+ (gambling-adjacent).
7. **Show more → Tags:** paste the tag block. **Category:** Education. **Language:** English. **Captions:** upload the SRT.
8. **Next → Video elements:** add **Cards** (~1:50 and ~6:25 per metadata) and an **End screen** (subscribe + "Can AI Solve Poker?"). *(On a debut upload with no other videos yet, use a link card to the app + a subscribe end-screen, and add the video link retroactively.)*
9. **Checks** (copyright) → **Next**.
10. **Visibility:** **Schedule** → **Saturday, 9:00 AM ET** (per metadata rationale).
11. **Publish/Schedule.** Done.

---

## After publishing
- Confirm the **UTM link** works and shows up in your analytics (installs from YouTube = the goal, not AdSense).
- First 48h: reply to every comment (feeds the algorithm), watch the retention graph — note where people drop (compare to the risk map).
- Then: `/youtube shorts` for a 30–45s discovery Short, and start Idea #2 down the `video-ideas.md` list.

---

## The whole thing in one picture

```
vo-readsheet.md ──► [Audacity] ──► VO stems ─┐
                                             │
blog SVGs + app ──► [OBS] ──► screen recs ───┤
checklist ────────► [Canva] ─► cards ────────┼──► [CapCut/Resolve] ──► final.mp4
music/SFX libraries ─────────────────────────┘        ▲
                                              shotlist.md = the map
thumbnail PNGs ──► [Squoosh] ──► <2MB jpg ──────────────────────────► [YouTube Studio] ◄── metadata.md
```
