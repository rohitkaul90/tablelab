# Thumbnail Brief — "How Many Buy-Ins Do You Actually Need?"

*Idea #1. Text brief + gen prompts. NanoBanana MCP now installed → `/youtube thumbnail` can render these.*

## Title-Thumbnail Analysis
- **Title:** *Poker Bankroll: How Many Buy-Ins? (50 Cash / 100+ MTT)*
- **Title communicates:** keyword + question + the two answer numbers (50/100+)
- **Thumbnail must add:** the *stakes* — what happens if you get it wrong (you go broke). Emotion, not info.
- **Info split:** thumbnail must NOT show "how many" or "50/100" (that duplicates the title).

## Primary Brief — "The Bust Line"
- **Focal point:** a bankroll line-chart starting healthy (green, upper-left) that **crashes down to a large red `$0`** lower-right, small chip stack toppling at the crash. Line on the upper-left→lower-right diagonal; `$0` on the right-third. Focal ~55%, ~35% negative space upper-right for text.
- **Focal strategy:** object/data-driven, **no face** (faceless brand; neutral face underperforms no face; a data object reads in <1s and signals depth).
- **Text overlay:** **"GOING BROKE?"** (2 words). Heavy bold sans-serif (Montserrat ExtraBold / Anton). Cap height ≈22% of frame. Upper-right, clear of line + `$0`. White `#FFFFFF` + 3–4px black `#111811` stroke + soft shadow.
- **Palette:** off-white `#F6F8F4` bg · brand green `#1B5E20`/`#4CAF50` (healthy line start) · alarm red `#E53935` (crash + `$0`). Green→red = universal winning→losing.
- **Composition:** rule-of-thirds; eye enters top-left green line → rides crash → lands on red `$0` → kicks to text. ~35% negative space. Faint low-opacity gridline; one foreground chip stack.
- **Mobile (168×94):** keep crash shape + red `$0` + 2-word text. Remove source ticks, fine gridlines, small chip detail.
- **DO NOT:** no human face · no "50/100/how many" text (duplicates title) · no >2 words overlay · no misleading imagery (crash matches real content → safe from AI clickbait suppression).

## A/B Variants (each changes ONE variable)
- **A "The Contradiction"** — text swap only → **"IS 20 ENOUGH?"** (different number than title, contradiction hook). Higher for informed players.
- **B "The Comparison"** — focal swap only → two chip stacks (short red toppling vs tall green stable), same text + light bg. Higher on browse.
- **C "The Felt"** — background swap only → dark poker-felt `#0d130d`→`#16201a`, same line + text. Tests dark-dramatic vs light-minimal; matches dark blog identity.

**A/B protocol:** YouTube Studio native (up to 3 variants, watch-time-share, ≤2 weeks, desktop setup).
⚠️ At ~0 subs impressions are too low for significance — **ship Primary now**, run the 3-way test only once videos get a few thousand impressions.

## Synergy Check
| Rule | Status | Detail |
|---|---|---|
| Info split | PASS | title = keyword+question+50/100; thumbnail = going-broke consequence |
| Emotional alignment | PASS | neutral title + fear thumbnail |
| Curiosity amplification | PASS | "here's the number" × "or you go broke" |
| Text overlap | PASS | "GOING BROKE?" not in title |
| Mobile readability | PASS | 2-word overlay + single focal object |

**Verdict: Strong.** Note: title's `(50 Cash / 100+ MTT)` truncates on mobile, so the thumbnail's emotional hook carries the click — info-split working. Variant A reintroduces a number if desired.

## Benchmarks
| Metric | Benchmark | Target |
|---|---|---|
| Education avg CTR | 4.5% | beat |
| Finance/Business (poker-adjacent) | 5.5% | aim |
| Niche-authority strong packaging | 6–9% | stretch |
| Healthy sustained | 4–8% | maintain |

New 0-sub channel = noisy early CTR (day-1 skews high, drops as reach widens). Judge on sustained 4–8%.

## Ready-to-paste gen prompts (NanoBanana / any image tool)
**Primary:**
> YouTube thumbnail, 16:9, high contrast, clean minimal composition, legible at small size. Off-white #F6F8F4 background. A bankroll line chart starting green (#4CAF50) upper-left and crashing steeply down to a large bold red (#E53935) "$0" lower-right, a small stack of poker chips toppling at the crash point. Bold white sans-serif text "GOING BROKE?" with a 4px black stroke in the upper-right. One clear focal point, 35% negative space, no faces, no other text.

- **Variant A:** same, change text to **"IS 20 ENOUGH?"**
- **Variant B:** replace line chart with **two poker-chip stacks side by side — short toppling red vs tall stable green** — keep "GOING BROKE?" + off-white bg.
- **Variant C:** same as Primary but **dark poker-felt background, gradient #0d130d to #16201a**.

Recommended NanoBanana settings: `aspect_ratio:"16:9"`, `resolution:"4k"`, `model_tier:"nb2"`.
