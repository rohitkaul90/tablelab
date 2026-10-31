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
• Study tab — browse a library of 26,000+ solver-computed spots for common preflop battles, street by street.
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

Available in English, Spanish (Spain and Latin America), French, Italian, Dutch, Japanese, Traditional Chinese and Korean, on Android and on the web at tablelab.app.

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

# App Store (iOS) listing — drafted 2026-10-20 for 1.10.1 (build 18, PR #111)

Paste into App Store Connect → My Apps → TableLab (Apple ID 6824665110 — confirm against the
App Information page; it is recorded nowhere else) → App Store tab → the 1.10.1 version page. Apple indexes **name + subtitle + keyword field** (the description is
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
- The availability line (second-to-last paragraph; keep the closing MagpiQ / support@ line) →
  `Available in English, Spanish (Spain and Latin America), French, Italian, Dutch, Japanese, Traditional Chinese and Korean, on iPhone and on the web at tablelab.app.`
- The Study bullet drops its "(beta)" — `• Study tab — browse a library of 26,000+ …` (App Review 2.2, 2026-10-31).
- **No Android mention anywhere in the description or What's New** (App Review 2.3.10, 2026-10-31).

## What's New (first iOS release)
```
TableLab is now on iPhone: bankroll tracking, hand replays, equity/ICM/variance calculators, a solver-computed study library and AI coaching, with Sign in with Apple. Your account syncs with the web app at tablelab.app.
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
Apple's revised questionnaire (mandatory since 31 Jan 2026; tiers 4+/9+/13+/16+/18+) has more
items than the old one. One consistent story everywhere, including the review notes below:
**TableLab contains no gambling, real or simulated — it is a results log and study tool for a
game people play elsewhere.**
- Simulated gambling: **Frequent** — set on App Review's instruction (2026-10-31 rejection under
  2.3.6: "since the app includes frequent simulated gambling, you must select Frequent"); the
  questionnaire then computes **18+**. Real-money gambling / lotteries: **No**. Contests: **No**.
- Violence, horror, sexual/mature themes, profanity, alcohol/tobacco/drugs references: **None**.
- Medical/wellness or health-related content: **No**. Unrestricted web access: **No**.
  In-app parental controls / age assurance: **No**. Messaging or user-generated content shown to
  others: **No** (reads/notes are private to the account). Advertising: **No**.
- Result **18+** (was 4+ with Simulated gambling = None on the first two submissions; Apple
  rejected that). Nothing else in the listing depends on the tier. Play's IARC rating is a
  different body and was NOT changed (owner decision 2026-10-31); the review notes must not
  claim "no simulated gambling" any more — they say no gambling SERVICES.

## App Privacy (must agree with `ios/Runner/PrivacyInfo.xcprivacy`)
Data collected, all **Linked to you**, none **Used to track you**:

| Data type | Purpose(s) | Source |
|---|---|---|
| Email Address | App Functionality (account), Analytics | Supabase auth; also a PostHog person property (`identify`) |
| Name | App Functionality | Sign in with Apple / Google profile |
| User ID | App Functionality, Analytics | Supabase user id = the PostHog distinct id |
| Other User Content | App Functionality (sessions, hands, reads, notes) | Supabase |
| Product Interaction | Analytics | PostHog events |
| Crash Data | App Functionality | Firebase Crashlytics (its own installation id; no account id is set — "linked" is declared conservatively, matching the manifest) |

The table is a one-to-one copy of `NSPrivacyCollectedDataTypes` in the manifest (same PR); change
both together.

Not collected: location, contacts, purchases, browsing, search history, identifiers for advertising,
health, financial info (bankroll figures are user content, not financial-account data), photos.
Data is not shared with third parties for their own use; Anthropic receives hand/session text only
when the user taps Analyse (disclosed in the policy's AI section).

## Review notes (App Review Information)
- Sign-in required: **Yes**. Demo account = the non-smoke review account already on file with Google
  Play (see memory `play-review-credentials`); confirm the password still works the day you submit.
- Notes text: the **long version in `launch/APP_REVIEW_REPLY.md` block B** (access, features,
  user-content, external services, regions, IAP, review history — ≤ 4000 chars). Keep the Notes
  field populated with it on every future submission; a short paragraph was not enough.
- **First submission of 1.10.1 (18) was rejected 2026-10-22 under Guideline 2.1 "Information
  Needed – New App Submission"** (limited App Review history, not a fault with the build): Apple
  wanted a physical-device screen recording (launch → registration → login → account deletion),
  purpose/audience, setup instructions, the external-services list, regional differences,
  regulated-industry status and an IAP overview. The reply text, the Notes text and the recording
  runbook live in `launch/APP_REVIEW_REPLY.md`. For a NEW app record in future, attach the
  recording and the full notes at first submission to skip this round.
- **Second rejection 2026-10-31 (1.10.2 build 19)**: 2.2 Beta Testing (the Study tab's BETA
  badge/chip/footer), 2.3.10 (Android in the description + What's New), 2.3.6 (age rating →
  Frequent simulated gambling). Fix = 1.11.1 (+21) with the beta wording removed + the metadata
  edits above; reply + notes in `launch/APP_REVIEW_REPLY.md` round 3.
- Contact: your name, phone, and `support@tablelab.app`.

## Screenshots
App Store Connect (layout as of 2026-10-21) has ONE required iPhone slot, **"iPhone with Dynamic
Island (medium display)"**, accepting **1179×2556** or **1206×2622** (portrait); it scales down for
smaller iPhones. The old 6.9"/6.5" slots are gone. Owner captures the six scenes on the iPhone 17e
(Stats, Sessions, Hands, Replayer, Study, AI coaching; light mode is fine; status bar may be
cropped) and Claude normalises them with ffmpeg: scale to 1179 wide, pad the top to 2556 with each
image's own top-edge colour (never centre-crop — it clips the right edge). Done 2026-10-21 →
`~/Downloads/appstore-medium/*.png`.

## Localized listings (es-ES / fr-FR / it-IT / nl-NL / ja / zh-Hant / ko / es-MX)
Description + name: reuse `STORE_LISTING_translations.md` with the same two edits as the English
description, using these lines (the availability line replaces the existing one in each
translation; the sign-in bullet goes under the "no ads" bullet):

| | Sign-in bullet | Availability line |
|---|---|---|
| es | `• Inicia sesión con Apple, Google o tu email.` | `Disponible en español (España y Latinoamérica), inglés, francés, italiano, neerlandés, japonés, chino tradicional y coreano, en iPhone y en la web en tablelab.app.` |
| fr | `• Connexion avec Apple, Google ou par e-mail.` | `Disponible en français, anglais, espagnol (Espagne et Amérique latine), italien, néerlandais, japonais, chinois traditionnel et coréen, sur iPhone et sur le web à tablelab.app.` |
| it | `• Accedi con Apple, Google o email.` | `Disponibile in italiano, inglese, spagnolo (Spagna e America Latina), francese, olandese, giapponese, cinese tradizionale e coreano, su iPhone e sul web su tablelab.app.` |
| nl | `• Log in met Apple, Google of e-mail.` | `Beschikbaar in het Nederlands, Engels, Spaans (Spanje en Latijns-Amerika), Frans, Italiaans, Japans, Traditioneel Chinees en Koreaans, op iPhone en op het web via tablelab.app.` |
| ja | `• Apple、Google、またはメールでサインイン。` | `英語、スペイン語、フランス語、イタリア語、オランダ語、日本語、繁体字中国語、韓国語に対応。iPhone とウェブ（tablelab.app）で利用できます。` |
| zh-Hant | `• 使用 Apple、Google 或 email 登入。` | `支援英文、西班牙文、法文、義大利文、荷蘭文、日文、繁體中文與韓文，可在 iPhone 與網頁版 tablelab.app 使用。` |
| ko | `• Apple, Google 또는 이메일로 로그인.` | `영어, 스페인어, 프랑스어, 이탈리아어, 네덜란드어, 일본어, 중국어(번체), 한국어 지원. iPhone과 웹(tablelab.app)에서 사용할 수 있어요.` |
| es-MX | `• Inicia sesión con Apple, Google o tu correo.` | `Disponible en español (Latinoamérica y España), inglés, francés, italiano, neerlandés, japonés, chino tradicional y coreano, en iPhone y en la web en tablelab.app.` |

Study bullet without "(beta)" per language (App Review 2.2 — paste over the existing bullet):

| | Study bullet (App Store) |
|---|---|
| es / es-MX | `• Pestaña Estudio: explora una biblioteca de más de 26.000 spots calculados por solver para los enfrentamientos preflop más comunes, calle por calle.` (es-MX: `26,000`) |
| fr | `• Onglet Étude : parcours une bibliothèque de plus de 26 000 spots calculés par solver pour les confrontations préflop courantes, street par street.` |
| it | `• Scheda Studio: sfoglia una libreria di oltre 26.000 spot calcolati dal solver per gli scontri preflop più comuni, street per street.` |
| nl | `• Tab Studie: blader door een bibliotheek van meer dan 26.000 door solvers berekende spots voor veelvoorkomende preflop-situaties, street voor street.` |
| ja | `• 学習タブ：よくあるプリフロップの対戦について、ソルバーで計算した26,000以上のスポットをストリートごとに閲覧。` |
| zh-Hant | `• 學習分頁：瀏覽超過 26,000 個由 solver 計算的常見翻前對局，逐街呈現。` |
| ko | `• 학습 탭: 흔한 프리플랍 상황에 대해 솔버로 계산한 26,000개 이상의 스팟을 스트리트별로 살펴보세요.` |

The tail of each sentence must match the Play translation in `STORE_LISTING_translations.md` (only the
"(beta)" parenthetical is removed there); the table above is the reference wording.

Short fields (poker terms deliberately kept in English):

| | Subtitle (≤30) | Promotional text (≤170) |
|---|---|---|
| es | `Sesiones, coaching IA y equity` | `Tracker de bankroll de póker gratuito: registra sesiones de cash y torneos, reproduce manos, calcula equity, ICM y varianza y recibe coaching con IA.` |
| fr | `Sessions, coaching IA, equity` | `Tracker de bankroll poker gratuit : sessions cash et tournois, replays de mains, calculs d'equity, ICM et variance, et un coaching IA qui te dit quoi corriger.` |
| it | `Sessioni, coaching IA, equity` | `Tracker di bankroll poker gratuito: registra sessioni cash e tornei, rivedi le mani, calcola equity, ICM e varianza e ricevi coaching con IA.` |
| nl | `Sessies, AI-coaching en equity` | `Gratis poker bankroll tracker: log cash- en toernooisessies, speel handen opnieuw af, bereken equity, ICM en variantie en krijg AI-coaching.` |
| ja | `セッション、AIコーチング、エクイティ` | `無料のポーカーバンクロールトラッカー：キャッシュとトーナメントのセッションを記録、ハンドをリプレイ、エクイティ・ICM・分散を計算、AIコーチングで改善点がわかる。` |
| zh-Hant | `場次、AI 教練與勝率` | `免費撲克 bankroll 追蹤：記錄現金桌與錦標賽場次、重播手牌、計算勝率、ICM 與變異數，並由 AI 教練告訴你該修正什麼。` |
| ko | `세션, AI 코칭, 에퀴티` | `무료 포커 뱅크롤 트래커: 캐시게임과 토너먼트 세션을 기록하고, 핸드를 리플레이하고, 에퀴티·ICM·분산을 계산하고, AI 코칭으로 고칠 점을 확인하세요.` |
| es-MX | `Sesiones, coaching IA y equity` | `Tracker de bankroll de póker gratis: registra sesiones de cash y torneos, reproduce manos, calcula equity, ICM y varianza y recibe coaching con IA.` |

Keywords per locale (≤100): es `bankroll,manos,historial,ICM,odds,calculadora,diario,registro,estudio,GTO,solver,cash,torneo,stats` ·
fr `bankroll,mains,historique,ICM,cotes,calculateur,journal,suivi,étude,GTO,solver,cash,tournoi,stats` ·
it `bankroll,mani,storico,ICM,odds,calcolatore,diario,registro,studio,GTO,solver,cash,torneo,stats` ·
nl `bankroll,handen,historie,ICM,odds,calculator,dagboek,logboek,studie,GTO,solver,cash,toernooi,stats` ·
ja `ポーカー,バンクロール,収支,ハンド,ICM,オッズ,計算機,記録,GTO,ソルバー,トーナメント,キャッシュ,統計` ·
zh-Hant `撲克,德州撲克,bankroll,收支,手牌,ICM,賠率,計算機,記錄,GTO,solver,錦標賽,現金桌,統計` ·
ko `포커,홀덤,뱅크롤,수익,핸드,ICM,오즈,계산기,기록,GTO,솔버,토너먼트,캐시게임,통계` ·
es-MX same as es.

App Store Connect has no es-419 locale — use **Spanish (Mexico)** for the Latin American text (Play uses `es-419`). Name + full description for the four new languages: `STORE_LISTING_translations.md` (the iPhone availability line above replaces the Android one; the sign-in bullet goes under the "no ads" bullet; drop "(beta)" from the Study bullet in every language — see the table below).
