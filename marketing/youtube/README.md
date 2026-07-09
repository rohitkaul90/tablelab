# TableLab — Faceless YouTube Channel (working files)

Internal planning + production assets for a **faceless TableLab brand YouTube channel**
(separate from Rohit's personal channel `@rohitkaul1990`). Produced with the
`claude-youtube` skill. Reference only — not deployed.

**Channel type:** Niche Authority · **Tier:** New (0 subs) · **Goal:** Growth → app installs
**Positioning:** turn your tracked results into a study plan — solver-grounded, faceless.

## Files
| File | What it is |
|---|---|
| `PRODUCTION_GUIDE.md` | **START HERE to produce a video** — the end-to-end process (record VO → gather visuals → edit → thumbnail → upload), tools + which stage each element is created/added |
| `channel-strategy.md` | 90-day strategy pass (positioning, pillars, cadence, milestones) |
| `video-ideas.md` | 10 ranked video ideas, seeded from the 2 published blog posts |
| `idea-01-bankroll-script.md` | Full retention-engineered script for Idea #1 |
| `idea-01-bankroll-vo-readsheet.md` | Clean take-by-take VO read sheet (spoken lines only + delivery/risk cues) |
| `idea-01-bankroll-shotlist.md` | Shot list / edit timeline — maps every script beat → visual asset → source → VO |
| `idea-01-bankroll-metadata.md` | Copy-paste upload package (titles, description, tags, chapters) |
| `idea-01-bankroll-thumbnail.md` | Thumbnail brief + 3 A/B variants + gen prompts |
| `thumbnails/` | Rendered thumbnail PNGs (primary + variants A/B/C, 5504×3072 — downscale to <2 MB before upload) |

## Key decisions / conventions
- **Faceless BRAND channel** → schema-link it to `#organization`, NOT `#rohit`.
  Add the channel's `sameAs` URL to the `#organization` node (duplicated across
  `about.html`, `blog/index.html`, both blog posts — edit all copies together).
- **Real human VO, never TTS** — AI narration drops retention ~70%. Faceless = no camera, not synthetic voice.
- **Zero fabrication** — every stat is sourced from the published blog posts
  (`web/blog/poker-bankroll-management.html`, `web/blog/can-ai-solve-poker.html`).
- **Monetization = app installs (UTM'd), not AdSense.** Optimize videos for the funnel.
- Video scripts/briefs are produced by the skill; **recording/editing/rendering stay manual.**

## Production pipeline gap
The `claude-youtube` skill writes scripts + briefs, not finished videos. Path:
screen-record app + GTO Explorer → **real Rohit voiceover** → edit → reuse blog SVG charts.
NanoBanana MCP (installed) renders the thumbnail briefs into actual images via `/youtube thumbnail`.

## Next steps (post-restart)
- `/youtube thumbnail` again → now renders 4 images (NanoBanana live)
- `/youtube shorts` → 30–45s Short from the risk-of-ruin curve to funnel discovery
- Produce Idea #1, then work down the `video-ideas.md` priority order
