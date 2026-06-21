# TableLab

> Your edge, quantified.

A Flutter poker bankroll tracker and study tool for live cash games and tournaments. Operated by MagpiQ.

**Available on** Android (Google Play) and the web at [tablelab.app](https://tablelab.app). iOS is not yet released.

## Features

- **Session tracking** — log cash game and tournament sessions (buy-in, cash-out, stakes, location, table size, notes), or run the **live session recorder** to track rebuys, add-ons, breaks, and expenses in real time.
- **Stats & analytics** — a bankroll dashboard where you tap any stat (profit, win rate, BB/100, ROI) to chart it over time, with unified date, currency, country, venue, and location filters. Multi-currency display with a configurable home currency.
- **Hand history** — record and replay individual hands street by street (heads-up to 9-handed), linked to sessions.
- **AI coaching** — Claude-powered session and hand analysis via Supabase Edge Functions, grounded in an on-device equity cross-check so the feedback can't contradict the math (5 session + 20 hand analyses/day per user).
- **Reads** — build opponent profiles with tags and observations; rule-based coaching tips per player type.
- **Equity calculator** — offline range-vs-range equity via Monte Carlo simulation, with GTO presets.
- **ICM calculator** — fair chip-chop deal calculations at final tables.
- **Tournament calendar** — scraped upcoming tournament listings.
- **Import/Export** — CSV/Excel import (with column mapping and presets for other trackers) and export.

## Tech stack

- Flutter (Dart) — Material 3, light + dark themes
- Riverpod — state management
- Supabase — Postgres + Row-Level Security, auth (email + Google OAuth), Edge Functions (no Realtime — providers invalidate after writes)
- Claude API — AI coaching via Supabase Edge Functions (Deno)
- Firebase Crashlytics (Android) + PostHog analytics

## Getting started

**Prerequisites:** Flutter SDK ≥ 3.27 (uses `Color.withValues` / `MediaQuery.withClampedTextScaling`), a Supabase project

```bash
flutter pub get
flutter run
```

**Web (GitHub Pages, custom domain `tablelab.app`):**
```bash
flutter build web --release --base-href /
```
Use `--base-href /` (root) — the app is served from the custom domain `tablelab.app`, not a project subpath. Run the web build in PowerShell on Windows (bash mangles the bare `/`).

## Project structure

```
lib/
  auth/           # AuthGate (Supabase session gating)
  config/         # Supabase credentials (gitignored)
  equity/         # Offline hand evaluator + Monte Carlo simulator
  models/         # Immutable data models
  providers/      # Riverpod providers
  reads/          # Insights engine + tag definitions
  screens/        # One file per screen
  services/       # Supabase service layer
  widgets/        # Shared UI components
supabase/
  functions/      # Deno Edge Functions (analyze-session, analyze-hand, scrape-tournaments, delete-account, submit-feedback)
  migrations/     # SQL migrations
```
