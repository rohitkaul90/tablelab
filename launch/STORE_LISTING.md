# TableLab — Google Play Store Listing / ASO

Drafted 2026-06-19; updated 2026-06-21 for v1.6.0; **updated 2026-07-11 for v1.7.0** (new STUDY
SOLVER STRATEGIES section for the Study tab, variance-calculator bullet, Stats-breakdown bullet;
"solver" claim scope revised — see "Deliberately NOT claimed"); **updated 2026-09-01 for v1.8.0**
(Study bullets: 26,000+ spot library, any-board search, "(beta)" label to match the in-app
disclosure). **READY TO APPLY** with the v1.7.0
production rollout. Store-listing edits go through Play's separate *content* review; apply alongside
the release so copy + build go live together.

Grounded in `web/about.html` (positioning + features) and `launch/competitive-positioning.md`
(the wedge, and what *not* to overclaim).

## Play ASO ground rules (so the copy is doing the right job)
- **No keyword field on Google Play** (that's Apple). Indexing is driven by **title + short description + full description** text. Keywords must appear naturally in the copy.
- **Field limits:** title **30 chars**, short description **80 chars**, full description **4000 chars**.
- **Weight:** the **title** carries the most ASO weight → the primary keyword ("Poker Tracker") belongs there. Short description is second + the main conversion line.
- **Don't keyword-stuff** (Play policy can suppress/reject) and **don't name competitors** ("GTO Wizard", "Pokerbase") in the listing — trademark/policy risk.
- **Don't claim what's false:** no iOS (Android + Web only); AI is plain-English feedback, **not** solver-grade.

---

## Title (≤30 chars)

**Recommended:** `TableLab: Poker Tracker & AI`  *(28)*

Alternatives:
- `TableLab: Poker Bankroll Log`  *(28)* — leans "bankroll/log" instead of "AI"
- `TableLab – Poker Tracker`  *(24)* — cleanest, drops "& AI" (loses an AI keyword)

Rationale: keep the brand first (you want "TableLab" searches to land), then the single
highest-value keyword phrase **"Poker Tracker"**, then the differentiator **AI**.

---

## Short description (≤80 chars)

**Recommended:** `Poker bankroll tracker with hand recording, equity calc & AI coaching.`  *(70)*

Alternatives:
- `Track cash & tournament poker, record hands, and get AI coaching. Free.`  *(71)* — leads with the use-case + "Free"
- `Bankroll tracker, hand recorder, equity calculator & AI poker coach.`  *(67)* — most keyword-dense

The recommended line front-loads the top keywords (bankroll tracker, hand recording, equity,
AI coaching) while staying readable — Play weights the short description heavily.

---

## Full description (≤4000 chars — this draft ≈1,550)

```
Track your poker. Fix your leaks.

TableLab is a free, all-in-one poker bankroll tracker for cash games and tournaments — with hand recording, an equity calculator, and AI coaching that tells you what to work on. Log a session in seconds, study the hands that mattered, and watch your win rate climb.

TRACK EVERY SESSION
• Log cash and tournament sessions: stakes, buy-in, cash-out, location, table size, duration, and notes.
• Live session recorder — track rebuys, add-ons, breaks, and expenses in real time, no mental math.
• Bankroll dashboard — tap any stat (profit, win rate, BB/100, ROI) to chart it over time, with date, currency, and location filters.
• See what's driving your win rate — breakdowns by stakes, day of week, time, session length, location, and more, plus cash vs tournament side by side.
• Play in multiple currencies? Pick your display currency; mixed-currency totals are clearly marked.

RECORD & REPLAY HANDS
• Capture full hand histories street by street, from heads-up to 9-handed.
• Replay any hand on a visual table.
• Link hands to sessions so your study stays organized.

AI POKER COACHING
• Plain-English analysis of your sessions and individual hands.
• Concrete, actionable feedback on your leaks — grounded in real equity math and solver-computed frequencies, not vague tips.
• A generous free daily allowance.

STUDY SOLVER STRATEGIES
• Study tab (beta) — browse a library of 26,000+ solver-computed spots for common preflop battles, street by street.
• Search any exact flop, turn, and river and see how often each hand bets, checks, calls, or raises.
• Strategy grid, equity charts, and hand-class views — the same framework your AI coaching uses.

BUILT-IN TOOLS
• Equity calculator — range vs range with GTO presets and Monte Carlo simulation, fully offline.
• Variance calculator — risk of ruin, expected downswings, and bankroll targets from your win rate or your own logged results.
• ICM calculator for tournament and final-table spots.
• Player reads — track tendencies on the regulars you face and turn tags into insights.
• Import and export your data to CSV/Excel, and import from other trackers.

FREE & PRIVATE
• No ads. We never sell your data.
• Your records are private to your account, protected by row-level security.

Available in English, Spanish, French, Italian and Dutch, on Android and on the web at tablelab.app.

Built and operated by MagpiQ. Questions or feedback? support@tablelab.app
```

---

## Keyword targets (for coverage — and reusable as the Apple keyword field later)
Primary: **poker tracker, poker bankroll tracker, poker session tracker**
Secondary: poker hand recorder / hand history, poker equity calculator, poker odds, ICM calculator,
poker stats, BB/100, win rate, poker journal/log, poker study, AI poker coach
Long-tail: cash game tracker, tournament tracker, live poker tracker, poker leak finder

Check each primary/secondary term appears at least once in the title/short/full copy above
(they do). That's the whole Play "keyword strategy" — no separate field to fill.

---

## Deliberately NOT claimed
- **iOS** — Android + Web only today. Don't imply an iPhone app.
- **"Solves any hand" / live solving** — REVISED 2026-07-11: the Study tab genuinely ships
  solver-computed strategies (licensed solver, ≤0.5% exploitability pre-solved library), so
  "browse/study solver-computed strategies" is now truthful and claimed. What stays OFF-limits:
  implying the app *solves arbitrary spots on demand*, or that the **AI coaching itself is
  solver-grade** — coaching is plain-English feedback grounded in equity + solver frequencies.
- **Competitor names** — kept out for policy/trademark safety.

## When you apply it
- Title/short/full → Play Console → Main store listing. Changes trigger Play's content review
  (separate from production-access review). Safest to apply **around public launch** so copy is fresh.
- Reuse the keyword list for the **Apple** keyword field if/when iOS ships.
- Pair with the screenshots already uploaded; consider a short feature-graphic tagline matching
  the title.

---
---

# App Store (iOS) listing — drafted 2026-10-20 for 1.10.1 (build 18)

Paste into App Store Connect → My Apps → TableLab (Apple ID 6824665110) → App Store tab →
the 1.10.1 version page. Apple indexes **name + subtitle + keyword field** (the description is
NOT indexed), so the keyword field must not repeat words already in the name/subtitle.
Once this listing is live, retire the "no iOS" lines in the Play section above and update
`web/about.html` / `index.html` / `gto-library.html` / `llms.txt` (deferred web PR).

## Name (≤30)
```
TableLab: Poker Tracker & AI
```
Same as Play, so brand searches land on one name across stores.

## Subtitle (≤30)
```
Sessions, AI Coaching & Equity
```
Alternative: `Bankroll, Hands & AI Coaching` (29).

## Keywords (≤100 chars, comma-separated, no spaces, no words from name/subtitle)
```
bankroll,hand,history,replay,ICM,odds,calculator,journal,log,study,GTO,solver,cash,tournament,stats
```

## Promotional text (≤170, editable without a new build)
```
Free poker bankroll tracker: log cash and tournament sessions, replay hands, run equity, ICM and variance numbers, and get AI coaching that tells you what to fix.
```

## Description (≤4000)
The Play full description above, verbatim, with two edits:
- Under **FREE & PRIVATE** add the bullet `• Sign in with Apple, Google, or email.`
- Last paragraph → `Available in English, Spanish, French, Italian and Dutch, on iPhone, Android and on the web at tablelab.app.`

## What's New (first iOS release)
```
TableLab is now on iPhone: bankroll tracking, hand replays, equity/ICM/variance calculators, a solver-computed study library and AI coaching, with Sign in with Apple. Your account syncs across iPhone, Android and the web.
```

## URLs
- Support URL: `https://tablelab.app/about`
- Marketing URL: `https://tablelab.app`
- Privacy Policy URL: `https://tablelab.app/privacy` (says "Android and iOS" for Crashlytics since PR #110)
- Copyright: `2026 MagpiQ`

## Category
Primary **Sports**, secondary **Utilities**. (Finance implies money management of real funds and
pulls the app next to banking apps in review; poker trackers on the store sit under Sports/Utilities.)

## Age rating questionnaire
Mirror the Play IARC answers. Apple's items that matter here:
- Simulated Gambling: **Infrequent/Mild** — the app is *about* poker but does not let anyone play
  or wager; choosing "None" invites a reviewer to disagree. Expected result **12+**.
- Gambling (real money): **No**. Contests: **No**. Unrestricted web access: **No**.
- Everything else (violence, mature themes, profanity, drugs, medical): **None**.

## App Privacy (must agree with `ios/Runner/PrivacyInfo.xcprivacy`)
Data collected, all **Linked to you**, none **Used to track you**:

| Data type | Purpose(s) | Source |
|---|---|---|
| Email Address | App Functionality (account) | Supabase auth |
| Name | App Functionality | Sign in with Apple / Google profile |
| User ID | App Functionality, Analytics | Supabase user id → PostHog `identify`, Crashlytics |
| Other User Content | App Functionality (sessions, hands, reads, notes) | Supabase |
| Product Interaction | Analytics | PostHog events |
| Crash Data | App Functionality, Analytics | Firebase Crashlytics |

Not collected: location, contacts, purchases, browsing, search history, identifiers for advertising,
health, financial info (bankroll figures are user content, not financial-account data), photos.
Data is not shared with third parties for their own use; Anthropic receives hand/session text only
when the user taps Analyse (disclosed in the policy's AI section).

## Review notes (App Review Information)
- Sign-in required: **Yes**. Demo account = the non-smoke review account already on file with Google
  Play (see memory `play-review-credentials`); confirm the password still works the day you submit.
- Notes text:
```
TableLab is a results tracker and study tool for poker players. It does not offer real-money or simulated gambling: users log sessions they played elsewhere, record hands, and review statistics and AI-generated coaching. No in-app purchases. Sign in with Apple, Google, and email are all available; the demo account above uses email. The Study tab shows pre-computed strategy charts bundled from our own server. The "Delete account" option in Settings removes all data and revokes the Sign in with Apple authorization server-side.
```
- Contact: your name, phone, and `support@tablelab.app`.

## Screenshots
App Store Connect requires **one** iPhone set at **6.9"** (1320×2868) *or* **6.5"** (1284×2778);
6.1" captures from the iPhone 17e (1179×2556) are not accepted as the required set. Fastest route:
take the six scenes on the 17e in dark mode (Stats, Sessions, Hands list, Replayer, Study, AI
coaching) and upscale to 1320×2868 — the aspect ratios differ by 0.2%, a one-pixel-row crop
nobody will see. Ask Claude to batch the resize (Pillow/ffmpeg). Fallback: a CI-booted
iPhone 17 Pro Max simulator with `xcrun simctl io booted screenshot`.

## Localized listings (es-ES / fr-FR / it-IT / nl-NL)
Description + name: reuse `STORE_LISTING_translations.md` with the same two edits as the English
description. Short fields (poker terms deliberately kept in English):

| | Subtitle (≤30) | Promotional text (≤170) |
|---|---|---|
| es | `Sesiones, coaching IA y equity` | `Tracker de bankroll de póker gratuito: registra sesiones de cash y torneos, reproduce manos, calcula equity, ICM y varianza y recibe coaching con IA.` |
| fr | `Sessions, coaching IA, equity` | `Tracker de bankroll poker gratuit : sessions cash et tournois, replays de mains, calculs d'equity, ICM et variance, et un coaching IA qui te dit quoi corriger.` |
| it | `Sessioni, coaching IA, equity` | `Tracker di bankroll poker gratuito: registra sessioni cash e tornei, rivedi le mani, calcola equity, ICM e varianza e ricevi coaching con IA.` |
| nl | `Sessies, AI-coaching en equity` | `Gratis poker bankroll tracker: log cash- en toernooisessies, speel handen opnieuw af, bereken equity, ICM en variantie en krijg AI-coaching.` |

Keywords per locale (≤100): es `bankroll,manos,historial,ICM,odds,calculadora,diario,registro,estudio,GTO,solver,cash,torneo,stats` ·
fr `bankroll,mains,historique,ICM,cotes,calculateur,journal,suivi,étude,GTO,solver,cash,tournoi,stats` ·
it `bankroll,mani,storico,ICM,odds,calcolatore,diario,registro,studio,GTO,solver,cash,torneo,stats` ·
nl `bankroll,handen,historie,ICM,odds,calculator,dagboek,logboek,studie,GTO,solver,cash,toernooi,stats`.
