# Release notes — v1.8.0 (+15)

Cut 2026-09-01 from `edd4cb1` (tag `v1.8.0`). Previous production release: v1.7.1+14 (2026-07-29).

## What's new (en-US) — Play Console field (≤500 chars)

```
• Study tab: browse our full solver library — 26,000+ spots across five preflop battles, searchable by any exact flop, turn, and river.
• Study is labeled beta while we calibrate ranges — tap the badge to learn more.
• Fixed CSV/Excel export on Android.
• Exports now include every session field (expenses, breaks, currency and more) and re-import losslessly.
• Recording a hand? The back gesture now asks before discarding your progress.
```

## Underlying changes (internal)

- #55 export all session fields + lossless TableLab re-import round-trip
- `888851a` mobile CSV/Excel export fix (SAF bytes via FilePicker.saveFile)
- #60 Explorer lazy two-level pack discovery + scalable board picker (26k-spot library browsing)
- #66 Explorer suit normalizer (any-suit board search, isomorph turn/river picks)
- #71 PokerCoaching range dataset + weighted range foundation (no user-visible change; consumers in #72 deferred)
- #75 back-gesture discard guard on both hand-recording screens
- #76 Study beta badge + in-screen disclosure

Data Safety: unchanged (no new permissions/SDKs since v1.7.1).
