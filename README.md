# TableLab

A Flutter poker bankroll tracker and study tool for live cash games and tournaments.

## Features

- **Session tracking** — log cash game and tournament sessions with buy-in, cash-out, rake, location, and notes
- **Hand history** — record and replay individual hands with street-by-street action
- **Reads** — build opponent profiles with tags and observations; get GTO-grounded coaching tips per player type
- **Analytics** — profit/loss charts, win rate by stakes and location, session history with filtering
- **AI analysis** — Claude-powered session and hand coaching via Supabase Edge Functions (5 session + 20 hand analyses/day per user)
- **Equity calculator** — offline hand-vs-range equity via Monte Carlo simulation
- **ICM calculator** — fair chip-chop deal calculations at final tables
- **Tournament calendar** — scraped upcoming tournament listings
- **Import/Export** — CSV and Excel import (with column mapping) and export

## Tech stack

- Flutter (Dart) — Material 3, dark theme
- Riverpod — state management
- Supabase — Postgres database, auth (email + Google OAuth), Edge Functions (no Realtime — providers invalidate after writes)
- Claude API — AI coaching via Supabase Edge Functions (Deno)

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
  config/         # Supabase credentials
  equity/         # Offline hand evaluator + Monte Carlo simulator
  models/         # Immutable data models
  providers/      # Riverpod providers
  reads/          # Insights engine + tag definitions
  screens/        # One file per screen
  services/       # Supabase service layer
  widgets/        # Shared UI components
supabase/
  functions/      # Deno Edge Functions (analyze-session, analyze-hand, scrape-tournaments)
  migrations/     # SQL migrations
```
