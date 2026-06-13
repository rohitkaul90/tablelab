# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Run the app
flutter run
flutter run -d emulator-5554     # Android emulator
flutter run -d windows            # Windows desktop

# Build
flutter build apk
flutter build appbundle --release                        # Play Store AAB
flutter build web --release --base-href "/"              # custom domain — PowerShell only
# IMPORTANT: run web build in PowerShell, not bash; bash on Windows mangles the bare /

# Deploy to GitHub Pages (after web build)
# Run in bash:
CNAME=$(cat docs/CNAME) && cp -r build/web/. docs/ && echo "$CNAME" > docs/CNAME && touch docs/.nojekyll
# Then commit and push docs/

# Dependencies / analysis / tests
flutter pub get
flutter analyze
flutter test
flutter test --coverage           # generates coverage/lcov.info
flutter test test/utils/helpers_test.dart   # run a single test file

# Version bump (increments build number, commits, tags — triggers CI AAB build)
bash scripts/bump-version.sh 1.2.0

# Supabase Edge Functions (requires supabase CLI + login)
supabase functions deploy delete-account
supabase functions deploy analyze-session
supabase functions deploy analyze-hand
supabase db push                  # apply pending migrations — ⚠️ UNSAFE here, see "Migration history is desynced" below; apply new migrations via the SQL editor instead

# Asset regeneration
dart run flutter_native_splash:create
dart run flutter_launcher_icons
dart run build_runner build --delete-conflicting-outputs   # only if @riverpod annotations added
```

## Slash-command agents

Fifteen specialist agents live in `.claude/commands/`. Invoke with `/agent-name [args]`:

| Command | Role | Scope |
|---|---|---|
| `/release-orchestrator` | Phase gate status + 72h action plan | Read-only audit |
| `/security-analyst` | RLS, secrets, OWASP, data-flow doc | Reads + fixes code |
| `/cloud-architect` | Supabase scaling, schema, Edge Functions | Reads + migrations |
| `/platform-engineer` | Flutter features, GDPR, tests, analyzer | Full code changes |
| `/devops-engineer` | GitHub Actions CI/CD pipelines | Writes workflows |
| `/qa-reliability` | Test suite, 60-row manual matrix, sign-off | Reads + writes tests |
| `/web-engineer` | manifest.json, meta tags, Cloudflare | web/ + Dart fixes |
| `/mobile-specialist` | Android/iOS native, store submissions | Native configs |
| `/ai-data-engineer` | Claude API, cost model, PostHog analytics | Edge Functions |
| `/legal-compliance` | Privacy policy, GDPR, store labels | Docs + screens |
| `/bizops` | Unit economics, pricing, RevenueCat | Analysis + docs |
| `/growth` | ASO, Reddit/PH launch, viral loop spec | Copy + specs |
| `/ux-designer` | Store visual assets, in-app UX flows, UI copy, onboarding specs | specs + Dart widgets |
| `/audit` | Deep multi-pass review of the whole codebase — finds issues *and* fixes them | Full code changes |
| `/triple-code-review` | Triple-agent PR review (Cursor Bugbot + Claude + Codex), cross-referenced to drop hallucinations | Read-only review |

Start any new session on launch work with `/release-orchestrator` — it reads the actual codebase state and outputs a prioritized action plan.

## Architecture

**TableLab** is a Flutter poker bankroll tracker. Package name: `tablelab`. Material 3, seed color `#1B5E20`, with **light + dark themes** and a System/Light/Dark toggle (see Theming below). The app is **operated by MagpiQ**, a registered Ontario sole proprietorship — the umbrella company; TableLab is the product. Privacy/about pages name MagpiQ as the data controller; user-facing contact is `privacy@`/`support@tablelab.app` (Cloudflare Email Routing on the tablelab.app domain). Company/vendor/billing contact is `admin@magpiq.com`.

### Navigation flow

`main.dart → AuthGate → MainNavigation`

`AuthGate` uses `StreamBuilder<AuthState>` + `AnimatedSwitcher` to fade between `SplashScreen` (while auth resolves), `LoginScreen`, and `_OnboardingGate`. `_OnboardingGate` watches `profileProvider` — if `profile == null || !profile.hasSeenOnboarding` it shows `OnboardingScreen`, otherwise `MainNavigation`. The splash is shown until Supabase emits the first valid auth event — no minimum timer.

`MainNavigation` is an `IndexedStack` with a `NavigationBar` (5 tabs: Stats, Sessions, Hands, Reads, Tools — note the first tab is labelled **Stats** but its widget/screen class is `DashboardScreen`). The `AppDrawer` is mounted via `mainScaffoldKey` (a `GlobalKey<ScaffoldState>` exported from `app_drawer.dart`) so any screen can call `mainScaffoldKey.currentState?.openDrawer()`.

Drawer sections: **Home** (Navigator.popUntil isFirst) → **Profile** → **APP** (Tournament Calendar, Settings, Send Feedback, Help, About) → **LEGAL** (Terms of Service, Data & Privacy) → **Sign Out** (pinned). Send Feedback sits high in APP (not buried at the bottom) and the rarely-tapped legal docs are grouped under a LEGAL label. Screens pushed via Navigator.push must include `drawer: const AppDrawer()` on their Scaffold if they need drawer access; alternatively call `mainScaffoldKey.currentState?.openDrawer()` from a custom leading button.

Bottom nav tabs: Stats (`DashboardScreen`), Sessions, Hands, Reads, **Tools**. The Tools tab hosts `ToolsScreen` — a `SegmentedButton` pill toggle switching between `EquityCalculatorScreen(showScaffold: false)` and `IcmCalculatorScreen(showScaffold: false)` via `IndexedStack` (state preserved on tab switch). Both calculator screens accept `showScaffold: bool` (default `true`) — when `false` they return body content only, no Scaffold/AppBar, suitable for embedding.

`AuthGate` also handles `AuthChangeEvent.passwordRecovery` → shows `ResetPasswordScreen` (set new password + auto sign-out on success).

**Email confirmation** — `signUp` in `login_screen.dart` sets `emailRedirectTo: 'https://tablelab.app/confirmed.html'` for **all** platforms. It must be an `https` URL, never the `io.supabase.pokertracker://` custom scheme — browsers/email clients can't open a custom scheme, which renders a blank page. `web/confirmed.html` is a static page (deployed to `docs/`) that shows a verified message and, on mobile, an "Open the TableLab app" deep-link button (the deep link is still used for Google OAuth and the button). The redirect URL must be allowlisted in Supabase → Authentication → URL Configuration (`https://tablelab.app/**`).

### Theming

`lib/theme/app_theme.dart` defines `AppTheme.light` / `AppTheme.dark` (both `ColorScheme.fromSeed` off `#1B5E20`; light overrides `scaffoldBackgroundColor` to a soft off-white `#F6F8F4`). `MaterialApp` in `main.dart` wires `theme`/`darkTheme`/`themeMode`. Theme mode is held by `themeModeProvider` (`StateNotifierProvider<ThemeModeNotifier, ThemeMode>` in `theme_provider.dart`) and **persisted to `shared_preferences`, not the Supabase profile** — it must apply at launch *before* auth resolves, so `main()` loads prefs and overrides `sharedPreferencesProvider` before `runApp`.

**Immersive poker-table screens stay dark in both modes.** `HandInputScreen` and `HandReplayerScreen` wrap their build in `Theme(data: AppTheme.dark, …)` — a green-felt table reads wrong with a light AppBar, and it bounds the color refactor. `AppTheme.dark`/`.light` are cached `static final` (not getters) because the replayer rebuilds every animation frame and `fromSeed` is non-trivial. When adding chrome, use `Theme.of(context).colorScheme` tokens (`onSurfaceVariant`, `outline`, `outlineVariant`) — not hardcoded `Colors.whiteNN`, which vanish on light.

### State management — Riverpod

Service classes are plain Dart, wrapped in `Provider<>` at the provider layer. All providers live in `lib/providers/`.

**Service DI for tests:** `ProfileService` and `AiService` take an optional `SupabaseClient` constructor arg and resolve `Supabase.instance.client` **lazily** (via a getter), so they can be constructed/faked in widget tests without an initialized Supabase. Tests override the provider with a fake — see `test/screens/profile_screen_test.dart` (guards the regression where saving the profile reset `has_seen_onboarding` and bounced users into onboarding). `AiService.fetchUsageLast24h()` reads `ai_usage_log` for the Settings "AI USAGE" rows; its row-tally is extracted into the pure, unit-tested `AiUsage.fromRows`.

| Provider | Type | Notes |
|---|---|---|
| `authUserIdProvider` | `StreamProvider<String?>` | emits current user ID on auth change |
| `sessionsProvider` | `FutureProvider` | fetch-once via `fetchAllSessions`; watches `authUserIdProvider` |
| `filteredSessionsProvider` | `Provider` | derived from sessions + filter |
| `filterProvider` | `StateProvider<SessionFilter>` | global session filter state. `SessionFilter.stakes`/`locations` are **`Set<String>` (multi-select)** — empty = no filter, else match if the session's value is in the set (OR within a set, AND across criteria). `copyWith` replaces whole sets (no sentinel); nullable scalars (`gameType`/dates/`result`) keep the `_sentinel` pattern |
| `handsProvider` | `FutureProvider` | fetch-once; watches `authUserIdProvider` |
| `handFilterProvider` | `StateProvider<HandFilter>` | Hands-tab funnel filter (game type, min pot in **bb**, street, stakes, table size, hero position, dates); applied client-side in `HandsScreen` |
| `aiUsageProvider` | `FutureProvider<AiUsage>` | 24h AI usage; feeds the contextual `AiUsagePill` indicators; **invalidate after each AI analysis** |
| `themeModeProvider` | `StateNotifierProvider<…, ThemeMode>` | System/Light/Dark, persisted to `shared_preferences` (see Theming) |
| `sharedPreferencesProvider` | `Provider` | throws until overridden in `main()` after prefs load |
| `tournamentListingsProvider` | `FutureProvider.autoDispose` | |
| `readsProvider` | `FutureProvider` | fetch-once via `fetchReads`; watches `authUserIdProvider`; in `reads_provider.dart` |
| `profileProvider` | `FutureProvider` | in `profile_provider.dart`; watches `authUserIdProvider` |
| `distinctStakesProvider` / `distinctLocationsProvider` | `Provider` | derived from sessions; feed filter/dropdown UIs |

Service classes are exposed via plain `Provider<>`: `supabaseServiceProvider`, `handServiceProvider`, `aiServiceProvider` (in `providers.dart`), `readsServiceProvider` (`reads_provider.dart`), `profileServiceProvider` (`profile_provider.dart`) — override these in tests to inject fakes.

**Cross-account scoping** — every user-scoped provider must `ref.watch(authUserIdProvider)` so it restarts when a different account signs in.

**No Realtime — invalidate after writes.** `sessionsProvider`, `readsProvider`, and `handsProvider` are all one-shot `FutureProvider`s. Supabase `.stream()` was deliberately removed (no `.stream()` calls remain in `lib/`) because a flaky Realtime channel surfaced `RealtimeSubscribeException(channelError)` directly to users on the Sessions/Reads screens. Because there is no live push, **every write path (insert/update/delete/bulk-import) must call `ref.invalidate(...)`** on the relevant provider — this is the *only* refresh mechanism, not a fallback. Easy to miss in new write sites (the CSV import path was a past offender).

### Backend — Supabase

All data is user-scoped via Row Level Security. Credentials live in `lib/config/supabase_config.dart` (anon key — public by design; file is gitignored). All Supabase calls go through `withSupabaseRetry<T>()` (`lib/services/supabase_retry.dart`), which retries once on PGRST303 (JWT clock-skew error).

**Tables:** `sessions` (incl. `table_size int` — added `20260608` via SQL editor), `hands` (JSONB `hand_data`, nullable `session_id`), `player_reads`, `player_read_notes`, `rake_presets`, `profiles` (includes `starting_bankroll numeric`, `starting_bankroll_currency text`), `ai_analyses`, `ai_hand_analyses`, `ai_usage_log`, `tournament_listings`.

**Note:** `sessions`, `hands`, and `rake_presets` were created directly in the Supabase dashboard before the migration workflow was established — their DDL is not in `supabase/migrations/`. All other tables have migration files.

**⚠️ Migration history is desynced — do NOT run `supabase db push`.** Most migrations were applied out-of-band (dashboard SQL editor / direct push without recording), so the remote `supabase_migrations.schema_migrations` history is missing ~10 entries even though their schema changes ARE live (verify with `supabase migration list` — many local rows show a blank Remote column). Running `db push` would attempt to **replay all "pending" migrations** onto prod; a single non-idempotent statement errors mid-run and can leave prod half-applied. **To apply a new migration: paste its SQL into the Supabase SQL editor and run it directly, and still commit the migration file for replayability.** The proper one-time fix is `supabase migration repair --status applied <version> …` to record the already-applied migrations, after which `db push` would be safe — but this hasn't been done (careful: same-date versions like `20260603` cover multiple files). **Schema-then-deploy order is mandatory:** an Edge Function that writes a new column must be deployed *after* the column exists, or its insert fails silently (e.g. a failed `logUsage` insert stops the rate-limit row → unlimited AI calls).

**GRANTs gotcha — new tables need explicit table + sequence grants.** Enabling RLS and adding policies is *not* enough: Postgres checks table-level `GRANT`s **before** RLS, and `service_role`'s `BYPASSRLS` does **not** include table/sequence privileges. A table created via migration with only RLS + policies (no `GRANT`) fails every access with `42501 permission denied for table …` — *before* RLS is evaluated. This silently broke the AI tables (`ai_analyses`, `ai_hand_analyses`, `ai_usage_log`): inserts 42501'd, but because the Edge Functions didn't check `.error` (and `supabase-js` doesn't throw by default) they returned 200 while writing nothing — which also disabled the AI result cache and made the rate-limit count always read 0 (unlimited AI calls). Fixed in `20260602_ai_table_grants.sql`. When adding a table, follow the `tournament_listings`/`profiles` pattern: `grant` the needed privileges to `service_role` (+ `postgres`) and read access to `authenticated`. **Also grant on the sequence** for any `serial`/`bigserial` column — inserting calls `nextval()` and needs `grant usage, select on sequence <table>_<col>_seq` separately (uuid-default PKs don't). Edge Functions should do DB writes with a **service-role client** (verify the user via the anon+JWT client's `getUser()`, then write with service role scoped explicitly by `user_id`) — the anon+JWT client's token does not reliably propagate into PostgREST's RLS context, so `auth.uid()` resolves to NULL and RLS-scoped writes fail silently.

**Edge Functions** (Deno, `supabase/functions/`):
- `analyze-session` — Claude Sonnet call via tool use; result cached in `ai_analyses`; limit 5/day per user; **120s timeout**; caps at **3 linked hands** (not 6 — larger cap causes 504s due to token volume)
- `analyze-hand` — Claude Sonnet call via tool use; result cached in `ai_hand_analyses`; limit 20/day per user; **50s timeout**
- `scrape-tournaments` — scrapes PokerNews, triggered by weekly GitHub Actions cron
- `delete-account` — verifies JWT, deletes all user data from every table in FK order, then deletes auth user via service role key
- Rate limits in `ai_usage_log`; `rhtk.1234@gmail.com` is exempt

**Edge Function patterns:**
- `SYSTEM_PROMPT` is a `const` string with `cache_control: { type: "ephemeral" }` — must stay static (no per-user data) for Anthropic prompt caching to work
- Cache check → rate limit check → Claude API call (this order is critical — cache hits are free)
- Both AI functions use `Promise.race()` with explicit timeouts: 120s for `analyze-session`, 50s for `analyze-hand`
- CORS locked to `https://tablelab.app` / `https://www.tablelab.app` with `Vary: Origin` header — do not revert to `*`
- `temperature: 0` on both functions for deterministic coaching output
- `computeDrawSummary()` injects deterministic `[FACT —` annotations into the user prompt — do not remove; these ground the model's hand-reading
- Error responses return generic user-facing messages; raw exceptions are logged server-side only
- **Ops alerting:** all four functions report errors to Discord via `_shared/alert.ts` (`reportError(fn, detail)`) — top-level catches *and* the silent-failure sites (`logUsage` insert, cache upsert, rate-limit read, delete-account per-table failures). Posts Slack-style `{"text": …}` to the `ALERT_WEBHOOK_URL` secret (a Discord webhook URL **with `/slack` suffix** — same channel/format as the smoke test's `SMOKE_ALERT_WEBHOOK`). No-op when unset; never put user data in alert text
- Both functions store `cache_read_tokens` + `cache_write_tokens` per call (columns added to `ai_analyses` + `ai_hand_analyses`) for cost modeling. **Note these cache-row token columns are OVERWRITTEN on re-analysis (`upsert onConflict`) — do not sum them for spend.** The accurate, append-only spend source is `ai_usage_log`, which has its own `input_tokens`/`output_tokens`/`cache_read_tokens`/`cache_write_tokens` (one row per call, never overwritten) written by `logUsage()` — accurate going forward only (pre-2026-06-03 calls weren't logged)

**AI cost / cache monitor** — `scripts/ai-cost-report.sql` (paste into the Supabase SQL editor, zero secrets) and `scripts/ai-cost-report.mjs` (formatted/`--json`, needs the **service-role** key since `ai_usage_log` is RLS-scoped per user — run locally, not in CI) report what the Anthropic console can't: cache hit-rate (`cache_read_share` ≈ 0 with calls > 5 = the ephemeral system-prompt cache broke, input cost ~2×), per-user spend, and days-to-$100-cap projection. Priced at **Sonnet 4.6** rates (both Edge Functions' model); one marked spot in each file to re-price if `analyze-hand` moves to Haiku. Docs in `scripts/AI_COST_MONITOR.md`.

### CI/CD — GitHub Actions

Six active workflows in `.github/workflows/`:

| Workflow | Trigger | What it does |
|---|---|---|
| `ci.yml` | Push/PR to `main` | `flutter analyze --fatal-infos` + `flutter test --coverage` |
| `deploy-web.yml` | Push to `main` touching `lib/`, `web/`, `assets/`, `pubspec.*` | Builds web + deploys to `docs/` (preserves CNAME + .nojekyll) |
| `build-android.yml` | Push of `v*.*.*` tag | Decodes keystore from secret, builds signed AAB, creates GitHub Release |
| `scrape-tournaments.yml` | Weekly cron (Mon 9am UTC) | Calls `scrape-tournaments` Edge Function |
| `smoke-test.yml` | Cron (twice hourly :07/:37 + daily 08:15 UTC) + manual | Synthetic prod E2E (`scripts/smoke-test.mjs`): auth → sessions CRUD → `analyze-hand`; catches "200 but writes nothing" failures |
| `daily-digest.yml` | Cron (daily 13:21 UTC) + manual | Morning Discord heartbeat (`scripts/daily-digest.mjs`): smoke-run summary + AI spend/cache/cap + activity counts; the message's *absence* signals dead monitoring. Needs `SUPABASE_SERVICE_ROLE_KEY` |

Required GitHub Secrets: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_ALIAS`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, `SMOKE_TEST_EMAIL`, `SMOKE_TEST_PASSWORD`, `SUPABASE_SERVICE_ROLE_KEY` (daily digest only — deliberate exposure decision 2026-06-11; if compromised, rotate in Supabase → Settings → API and update the secret) (+ optional `SMOKE_ALERT_WEBHOOK`).

**Smoke test** (`scripts/smoke-test.mjs`, docs in `scripts/SMOKE_TEST.md`) runs the real prod paths on a schedule to catch the silent-write failure class UptimeRobot can't see (42501 GRANT / broken `logUsage` / RLS regression). Cheap runs (twice hourly, at :07/:37 — GitHub throttles :00/:30 schedules hard) hit the `analyze-hand` cache = $0 **and assert no new `ai_usage_log` row appeared** (cache-hit proof; a cold cache warms-and-retries once); the daily deep run forces one uncached Claude call (~$0.034) and asserts a **fresh `ai_usage_log` row appeared** — the smoking-gun check. Uses a dedicated synthetic test account (not the exempt personal one); the sessions insert must set `user_id` explicitly (RLS `WITH CHECK (user_id = auth.uid())`), mirroring the app. **The smoke hand must exist as a row in `hands`** (the script self-provisions it, idempotently): `ai_hand_analyses.hand_id` FKs to `hands(id)`, so without that row the function's cache upsert silently fails and every cheap run costs a real Claude call.

CI generates `lib/config/supabase_config.dart` at build time from secrets — it is never committed. The `deploy-web.yml` commit uses `[skip ci]` in its message to prevent loops (note: pushing a tag also fires `deploy-web.yml` + `ci.yml` if `lib/`/`pubspec` changed, so a tag push commonly produces a `[skip ci]` deploy commit on `main` — rebase before subsequent pushes).

`build-android.yml` requires `permissions: contents: write` for the "Create GitHub Release" step (otherwise it fails with "Resource not accessible by integration"; the AAB still builds + uploads as an artifact). Actions are pinned to Node-24 majors (`checkout@v5`, `upload-artifact@v6`, `gh-release@v3`) — Node 20 runtimes are deprecated (forced switch 2026-06-16).

**Releasing to Play:** `bash scripts/bump-version.sh X.Y.Z` → push `main` + the `vX.Y.Z` tag → CI builds the signed AAB and attaches it to a GitHub Release. The AAB is then **manually uploaded** to the Play Console internal track. Google requires the *first* upload of an app to be manual; subsequent uploads can be automated via the Play Developer API + a service-account secret (not yet wired up).

### Firebase Crashlytics

Active on Android only. `lib/firebase_options.dart` is generated (not a stub) — do not overwrite it. `main.dart` routes `FlutterError` and `PlatformDispatcher` errors to Crashlytics, guarded by `if (!kIsWeb)` — Crashlytics throws on web. `android/app/google-services.json` is committed and required for Android builds.

The Crashlytics Gradle plugin (`firebase-crashlytics-gradle:3.0.3`) requires the **Google Services plugin ≥ 4.4.1**. Keep the version in sync across both declarations: `settings.gradle.kts` plugins block and `build.gradle.kts` classpath (both `4.4.2`). A mismatch only fails **release** builds (the `uploadCrashlyticsMappingFileRelease` task), not debug — so `flutter run` won't catch it.

### Splash screen

Three layers, all matching background `#111811`:
1. **Native** — generated by `flutter_native_splash`; assets in `android/app/src/main/res/` and `ios/Runner/`; Android 12+ uses Splash Screen API with icon on `#1B5E20` circle
2. **Flutter overlay** — `lib/widgets/splash_screen.dart`; shown by `AuthGate` until auth resolves; fades via `AnimatedSwitcher(duration: 350ms)`
3. **Web** — custom HTML/CSS in `web/index.html`; splash div fades out on `flutter-first-frame` event

### Equity Calculator

`lib/screens/equity_calculator_screen.dart` + `lib/widgets/equity/`.

Each player has two modes toggled in `PlayerRangeEditor`:
- **Range mode** — 13×13 matrix + GTO presets; `expandCombos()` expands to all concrete card pairs
- **Exact Hand mode** — two specific cards via `HoleCardsPickerSheet` (2 slots, one sheet visit, auto-confirms on the second card — tapping either card slot opens it with both current cards); `expandCombos()` returns a single `[[card1, card2]]`. The single-card `CardPickerSheet` remains for turn/river board picks (one tap is correct there); `FlopCardPickerSheet` handles the flop.

Board cards and other exact-hand players' cards are passed as `excludedCards`. Simulation runs via Monte Carlo (`lib/equity/simulator.dart`).

The screen **seeds two default players** (BTN vs BB, empty ranges) in `initState` so it's usable immediately — positions are cosmetic labels here (not used by the sim), so a fixed pair is preferable to random. A **Reset** affordance lives in the body (the PLAYERS header, shown via `_isModified`), **not only the AppBar** — because in the Tools tab the screen is embedded with `showScaffold: false` (no AppBar), an AppBar-only reset would be unreachable there. `_reset()` restores the 2-player default, not a blank state. You can't delete below 2 players (`onDelete` is null at length 2).

### Key subsystems

- **`lib/equity/`** — offline equity: card encoding (rank×4+suit), 7-card evaluator (brute-force 5-card combos; `evaluateBest` handles 5/6/7 cards for partial boards), Monte Carlo simulator, GTO preflop ranges. `gto_ranges.dart` is **triple-use**: the presets feed the equity range editor, the quick-hand synthesis classifier, AND the trust-pack villain range model (`villain_range.dart`) — all look presets up **by key**, keep keys stable. Beyond RFI, it has bucketed response charts (opener bucket Early/Middle/Late): Cash/Tournament Call, the 3-bet grid, and vs-3-bet (call + 4-bet value).
- **AI trust pack** — trust scaffolding around the AI coaching. (1) **Equity cross-check**: `lib/equity/villain_range.dart` (pure Dart, unit-tested) models each opponent's range — GTO preset chart from their preflop line (open/call/3-bet/limp, bucketed by opener position), widened/tightened by reads tags (a Chen-formula 169-hand ranking drives the resize), narrowed per postflop street by their action (bet→top ~55%, raise→~30%, call→~65%; tags shift thresholds; draws get score bonuses so semi-bluffs survive filters) — then Monte-Carlos hero's exact cards per street. `HandAnalysisScreen` runs it in parallel with the AI call (best-effort, null when unmodelable); per-street **EQ chips** open an assumptions sheet whose `rangeTrail` strings explain every modeling step; quick hands get a "synthesized scaffolding" caveat. Recorded villain hole cards (showdown) bypass the range model. **The cross-check also grounds the AI**: `equityCheckFacts()` renders the per-street equity + range basis into `[FACT —]` lines that `HandAnalysisScreen` passes to `analyzeHand(equityFacts:)`; `analyze-hand` injects them into the prompt and merges them into `analysis.facts`, so the coaching can't claim showdown value when hero has ~8% (the fix for the self-contradiction class — model says "nit never bluffs" then calls the fold a leak). Equity is computed *before* the AI call now (was parallel) so it can ride into the prompt. (2) **Thumbs up/down** (`AnalysisFeedbackBar`, both analysis screens) writes `rating`/`rated_at` directly to `ai_hand_analyses`/`ai_analyses` via `AiService.rateHandAnalysis`/`rateSessionAnalysis` — requires `20260612_ai_feedback_rating.sql` (column-scoped `GRANT UPDATE` + RLS UPDATE policies; apply via SQL editor **before** the client ships — GRANTs gotcha applies). Ratings seed the future eval dataset. (3) **Confidence + alternative + facts**: client parses all three as nullable/empty-safe (legacy cached analyses render nothing); `analyze-hand` emits `confidence` (high/medium/low) and `alternative` ("Also defensible: …") in the tool schema and attaches the per-street `[FACT —]` strings as `analysis.facts` server-side (never model output) before caching — **deploy the function post-gate, after the rating migration**. (4) One-line disclaimer on both analysis screens — "AI coaching can be wrong — verify big decisions."
- **`lib/reads/`** — `insights_engine.dart` (rule-based coaching from player tags), `tag_definitions.dart`. Tags span preflop/postflop sets plus a **Tournament/ICM** group. Archetype tags use **quadrant-based compatibility** (`_archetypeStyles`/`_styleOf` + `tagDisabled`): only *contradictory* tags grey out in the picker (Fish+Station, LAG+Maniac co-selectable) — this is forward-only and never strips tags off legacy reads that hold multiple archetypes. `kArchetypeDefinitions` backs the player-type **glossary** (`lib/widgets/reads/archetype_glossary.dart`, `showArchetypeGlossary()`), reachable via an info icon by the tag pickers. `readableTagColor(context, tag)` keeps tag chips legible on any background in both themes (lerps toward black/white by brightness) — use it instead of raw tag colors on chips.
- **Session logging vs hand recording** — two distinct entry paths. `LogSessionScreen` (`log_session_screen.dart`) is the cash/tournament *session* form (date, game type, location, stakes, buy-in/cash-out); it takes an optional `session` arg for edit mode and is pushed from Dashboard, Sessions list, and `SessionDetailScreen`. Hand recording (`hand_input/`) records an individual *hand* — two modes behind one chooser, see "Hand recording" below. Don't conflate sessions and hands.
- **`lib/screens/hand_replayer/`** — `HandReplayerScreen`: street-by-street visual playback of a recorded `PokerHand` on a painted table (`_TablePainter`, `_Frame`/`_SeatState` model the animation). Launched from `HandsScreen` and `HandInputScreen`.
- **`lib/screens/analytics_screen.dart`** — `AnalyticsScreen`: in-app charts/stat breakdowns over sessions+hands (distinct from PostHog product analytics). Uses a `SliverPersistentHeader` summary delegate. The cumulative graph sits **above** the controls (not below the fold); a full-screen view (`_PLChartFullScreen`, `_PLChart(fullScreen: true)`) is launchable. Recommendations render un-collapsed at the bottom. Hours use `formatHours()`. **Country and Location filters are multi-select** (`Set<String>`) in `AnalyticsFilterSheet` + `_AnalyticsBody._filtered`; the dashboard owns this filter state (`_analyticsCountryFilter`/`_analyticsLocationFilter` as `Set<String>`). Venue/date/currency stay single-select.
- **Hands tab** — `HandsScreen` lists recorded hands with a funnel filter (`handFilterProvider` / `HandFilter`, applied client-side; distinct chip options derived from the loaded hands). Tile layout uses a `LayoutBuilder` that **measures text width and sizes the cards to fill the leftover space** — the info text has no ellipsis (can't truncate) and hole + community cards share one computed size. Per-hand actions (AI Coaching / Delete) live in a `⋮` overflow menu; tapping the tile opens the replayer. `AiUsagePill` shows the contextual AI quota on this tab, the dashboard coaching card, and session detail.
- **Import/Export** — three screens: `import_export_screen.dart` (hub — CSV/Excel export + entry to import) → `import_source_screen.dart` (source picker: 17 named app presets across mobile, desktop-HUD, and tournament-DB categories, plus a generic CSV/Excel option; auto-detects delimiter, handles xlsx/xls) → `import_mapping_screen.dart` (column mapping: 20 fields, only `date` + `buy_in` required, derives cash-out from a "Profit" column when absent). **Dedup key = `date + buy_in + cash_out`** (toggleable; an "overwrite" mode is the alternative). Reached from the Sessions AppBar, **Settings → DATA**, and the Sessions/Dashboard empty-state "Import from another app" CTAs. The importer does **not** invalidate providers — the call site does on return (e.g. the Hands/Sessions FAB).
- **`lib/utils/helpers.dart`** — currency conversion, `parseBBFromStakes`, `calcBB100`, `formatPL`, `formatHours`, `fieldSizeBucket`, `tableSizeLabel`, all shared formatting. `parseBBFromStakes` is regex-tokenised: handles currency symbols (£/€/₹), dash separators, NL/PLO labels, k-suffix, comma decimals, and `NLxxx` cap notation (BB = num/100); a bare ambiguous number returns `null`. **It is currency-blind by design** — `calcBB100` assumes profit and the parsed BB share the session's currency (each `SessionModel` carries one `currency`), so `profitLoss / bb` is dimensionless; feeding it mixed-currency rows under unlabeled blinds produces nonsense. `calcBB100` only counts cash sessions with a parseable BB and estimates hands as `(handsPerHour ?? 25) × hours`. **Terminology:** user-facing copy says **"Profit"**, never "P&L" (standardized across Analytics/Help/About/import).

### Models

`SessionModel` — `fromMap()` (snake_case DB → camelCase Dart); includes optional `tableSize`.  
`PokerHand` — `fromJson()`/`toJson()` (entire hand serialized as JSONB); fields include optional `tournamentStage`, `TableSetup.ante`, and an explicit **`isTournament` bool**. `isTournament` is the reliable game-type signal (set from the recording toggle / locked session value); legacy hands without it infer `tournamentStage != null || ante != null` in `fromJson`. `PokerHand.finalPot` derives the pot in chips (sum of each seat's max contribution per street — mirrors the replayer).  
`TableSetup` supports **2–9 seats** via `positionLabels(seats)` (heads-up → 9-max); heads-up is special-cased (button posts the SB; BB acts first postflop). See `hand_filter.dart` for `HandFilter`/`handStakesKey`/`handHeroPosition`.  
`PokerHand.isQuickEntry` (default `false`, omitted from JSON when false — legacy-safe) marks hands captured via Quick Hand mode; the Hands tile appends "· Quick" to its line-2 string.  
All models are plain immutable classes — no code generation.

### Hand recording

**Two modes behind one chooser.** Both entry points (Hands-tab FAB and `SessionDetailScreen` "Record a Hand") call `showRecordHandSheet()` (`hand_input/record_hand_sheet.dart`) with the same prefill args; the sheet offers **Quick Hand** (`QuickHandScreen`) or **Full Hand** (`HandInputScreen`). Call sites keep the `await …; if (!mounted) return; ref.invalidate(handsProvider);` shape. The card picker is shared: `lib/widgets/hand_card_picker.dart` (`showHandCardPicker`) — extracted from the wizard and **always wrapped in `AppTheme.dark`** (its glyph colors are hardcoded for dark) even when opened from the light-themed quick form. `kPresetStakes` / `kTournamentStages` are exported from `hand_input_screen.dart` for both modes.

**Quick Hand mode** (`hand_input/quick_hand_screen.dart`, single scrollable form, ambient theme — it's a form, not a felt table): hero cards + position + stakes + the one decision that mattered + result, target ≤30s. Only hero cards / position / valid blinds / hero action are required. Saves through `HandService.saveHand(..., isQuickEntry: true)` and fires `AnalyticsService.handRecorded(entryMode: 'quick')`. AppBar "Full mode" button `pushReplacement`s to the wizard (form data doesn't carry over). The heavy lifting is **`synthesizeQuickHand()`** (`lib/utils/quick_hand_synthesis.dart`, pure Dart, heavily unit-tested):
- Builds a 2-player hand (Hero + stand-in "Villain"). **Hard invariant: every emitted action's seat must belong to a player** — the replayer does `seats[action.seat]!` and crashes otherwise; a parameterized sweep test guards the full facing×action×street×position×earlier matrix. Never add an action-emission path without it.
- **Chart-informed preflop line**: hero's hand is classified against the GTO presets — in-range hands make hero the aggressor with standard sizes; a hand in no chart is **never** the synthesized aggressor (defend / cold-call / limp-call fallbacks). Optional "How preflop went" chips (Auto/Limped/Single-raised/3-bet/4-bet) override the inference.
- **"Pot entering this street" reconciles exactly**: preflop sizing windows + intermediate-street bet/call pairs (clamped to plausible pot fractions, capped by effective stacks); the last synthesized bet closes the gap.
- **"Earlier this street" chips** (postflop, facing bet/raise/all-in): Villain acted first / I checked first / I bet first (+ size) — captures check-then-faced and bet-then-got-raised lines. Facing **Raise** locks to "I bet first" (can't be raised without betting). Ordering is position-aware: a blind hero acts first; preflop facing a 3-bet implies hero's open, facing a 4-bet+ implies open → hero 3-bet → 4-bet.
- **The notes line is the AI's ground truth**: it opens with an instruction to evaluate ONLY the recorded decision (the synthesized actions are scaffolding) and states the assumed preflop story + heads-up abstraction. It rides into `analyze-hand` via the existing `hand.notes` prompt injection — **no Edge Function change needed; don't weaken this disclaimer**.
- Out of scope by design (use Full mode): multiway pots, raise wars beyond one raise per street, two recorded decisions in one hand, straddles/side pots.

**Full wizard:** `HandInputScreen` supports tournament hands: `isTournamentSession` param shows stage dropdown, ante field, relabels stakes as "Blind Level". Table size is a **2–9 dropdown** (not a 6/9 toggle). All-in runout: `_allInSeats` persists across streets; `_isAllInRunout` getter auto-deals remaining streets when ≤1 non-all-in player remains. Undo stack (`_HandSnapshot`) captures state before each action. The save persists explicit `isTournament`.

**Recording from a session** (`prefilledSessionId != null`, launched from `SessionDetailScreen`): game type is inherited and **locked** (read-only label, no toggle); session stakes pre-fill as an **editable** default (any value, incl. non-presets) since the session's stakes can't capture a straddle / 3-blind game. Two session pickers show date · game type · stakes · **location**: `_SessionPickerTile` (recording) and the replayer's `_SessionLinkSheet` (linking a pre-recorded hand, which also shows profit). `SessionDetailScreen` lists the hands linked to that session (filtered `handsProvider` by `sessionId`).

### Critical patterns

**Async + ref after widget disposal** — always guard `ref` usage after any `await` with `if (!mounted) return;` (use `mounted` in `State`/`ConsumerState`, not `context.mounted`). `AppDrawer._confirmSignOut` is the canonical example.

**Dismissible + provider invalidation** — never call `ref.invalidate` in `onDismissed` without first removing the item from local state. Pattern: `ConsumerStatefulWidget` + `Set<String> _deletingIds`; add ID on dismiss, filter list in build, call service async. See `HandsScreen`.

**Save button guard** — any form with an async save must have `bool _saving` that disables the button during the call to prevent double-submission.

**fl_chart on Windows** — always set `barTouchData: BarTouchData(enabled: false)` and `lineTouchData: const LineTouchData(enabled: false)` on every chart. Default enabled state throws `RangeError` on Windows when mouse nears edge.

**SegmentedButton rows wrap on phones** — Material 3 adds a checkmark icon to the selected segment, widening it; a 3–4-segment row then overflows to a second line after selection. Set `showSelectedIcon: false` on multi-segment rows (selection still reads via the fill color). Hit on Quick Hand's street selector.

**Deep links need a route fallback** — the app navigates imperatively (`Navigator.push` only) with `MaterialApp(home:)` and no named routes. When the OS delivers a platform route push (the `io.supabase.pokertracker` OAuth / email-confirmation deep link arrives as a named route like `/?code=…`), the framework calls `Navigator.pushNamed`, finds no match, and hits `widget.onUnknownRoute!` on a null value. The guarding assert is stripped in **release**, so this crashes only in production. `MaterialApp.onUnknownRoute` (in `main.dart`) returns an `AuthGate` route to swallow these safely — do not remove it. Supabase handles the actual deep link via its own listener; the route push is the redundant copy.

**ListTile under a colored box** — never wrap a `ListTile`/`SwitchListTile` (or a `Column`/`ListView` of them) in a `Container`/`DecoratedBox` with a background `color`/`decoration` without a `Material` in between — the tile paints its background + ink splashes on the nearest `Material` ancestor, so the colored box hides them and trips `ListTile._debugCheckBackgroundIsHidden` (debug-only assert). Use a `Material` (with `color` + `borderRadius` + `clipBehavior`) instead of the colored `Container`.

**Crashlytics is release-only by intent** — `main.dart` calls `setCrashlyticsCollectionEnabled(!kDebugMode)`, so debug builds (`flutter run` on a device) don't report crashes. This keeps debug-only asserts out of the production Crashlytics dashboard; when triaging, filter issues by the released build's version to ignore stale crashes from old builds.

### Analyzer configuration

`analysis_options.yaml` excludes `test_imports/` (untracked scratch directory) and disables `use_null_aware_elements` (requires Dart SDK ≥3.8 collection literal syntax not yet available). `flutter analyze --fatal-infos` must return zero issues — CI enforces this.

### Web deployment — critical details

- Custom domain `tablelab.app` → build with `--base-href /` (root, not `/tablelab/`)
- Web build output goes into `docs/` folder on `main` branch (GitHub Pages source)
- `docs/CNAME` must contain `tablelab.app` — preserve it on every deploy
- `docs/.nojekyll` must exist — recreate after every wipe
- PowerShell for the flutter build command; bash for the file copy
- Static pages in `web/` are copied into the build and served at the root. They form a **cohesive marketing site** sharing one stylesheet (`web/site.css`, served at `/site.css`) with a common sticky header-nav + footer: `about.html` (`/about`) is the **landing page** (hero, features, FAQ), `privacy.html` (`/privacy`, required by Apple review), `terms.html` (`/terms`), `confirmed.html` (`/confirmed.html`, the email-verification landing page — see Email confirmation above). The **Flutter app stays at `/`** — don't move it (would break OAuth/email redirects + base-href); keep `/about` and `/privacy` URLs stable (store-listing). Match the dark theme (`#111811` bg, `#4CAF50` accents) and link `/site.css` when adding pages.

### Android build

- `compileSdk = 36`, `minSdk = maxOf(flutter.minSdkVersion, 23)` (flutter_secure_storage requires API 23+; `maxOf` prevents Android Studio/Flutter Gradle plugin from silently reverting to 21), `targetSdk = 35` — all in `android/app/build.gradle.kts`
- `android/build.gradle.kts` has a `gradle.afterProject` block that forces `languageVersion` and `apiVersion` to `KOTLIN_2_0` for all plugin subprojects — required because KGP 2.3+ dropped support for Kotlin 1.6 (used by `posthog_flutter` and others)
- Release signing reads `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` from env vars; falls back to debug signing locally when `tablelab-release.jks` is absent
- `tablelab-release.jks` is gitignored — CI decodes it from `ANDROID_KEYSTORE_BASE64` secret
- ProGuard enabled on release builds (`android/app/proguard-rules.pro`). Must keep `-dontwarn`/`-keep` rules for `com.google.android.play.core.**` — Flutter's `PlayStoreDeferredComponentManager` references those classes but they aren't bundled, so R8 fails `minifyRelease` with "Missing class … Compilation failed" without them. Release-only (debug skips R8).
- `INTERNET` permission explicitly declared in `AndroidManifest.xml`
- `io.supabase.pokertracker` deep-link intent filter in `AndroidManifest.xml` — used by Google OAuth callback and the email-confirmation "Open app" button
- Package ID: `com.pokertracker.poker_tracker` (tied to Google OAuth — do not rename)

### iOS build

- iOS is **deprioritized** — not building until Android + Web are stable in production
- `ios/Runner/Info.plist` `CFBundleDisplayName` = "TableLab" ✅
- `ios/Runner/PrivacyInfo.xcprivacy` exists ✅ — must be added to Xcode Runner target before first build (right-click Runner folder in Xcode → Add Files)
- `flutter_launcher_icons` has `ios: false` in `pubspec.yaml` — change to `true` before the first iOS build
- `ios/ExportOptions.plist` exists for App Store export; update `teamID` before use
- iOS builds require a macOS machine; cannot be built on Windows

### Analytics — PostHog

`posthog_flutter: ^4.0.0` is installed. API key lives in `lib/config/analytics_config.dart` (committed — PostHog project keys are public by design). Initialized in `main.dart` after Supabase, guarded by a placeholder check and a Windows platform check (PostHog Flutter SDK does not support Windows desktop).

All analytics calls go through `lib/services/analytics_service.dart` — static fire-and-forget methods with a Windows no-op guard. Events wired: `onboarding_completed`, `onboarding_skipped`, `session_logged`, `hand_recorded` (with `entry_mode: 'full' | 'quick'`), `ai_session_analysis_requested`, `ai_hand_analysis_requested`, `ai_rate_limit_hit`.

### Onboarding

`lib/screens/onboarding_screen.dart` — 3-page `PageView` with `PopScope(canPop: false)`. Completion calls `ProfileService.markOnboardingComplete()` which upserts `has_seen_onboarding = true` on `profiles`. `_OnboardingGate` in `auth_gate.dart` gates on `profile.hasSeenOnboarding`. Existing users are grandfathered (`DEFAULT true` on column add, reset to `false` for new inserts via second migration).

### Pre-launch status (as of 2026-06-01)

**Done:** Play Store screenshots (8 phone + 8×7" + 8×10" tablet), Play Console internal track live, data safety form, onboarding flow, PostHog analytics, delete-account, GDPR polish, all Supabase migrations applied, Edge Functions hardened and deployed, RLS hardened, UptimeRobot monitors, Anthropic spend alerts ($80 alert / $100 hard limit). **v1.1.2 (build +4)** AAB uploaded to internal testing — first submission, in Google's one-time initial review (subsequent internal releases publish in minutes).

**Remaining:** Get testers onto the internal track → collect beta feedback → promote to production. Note: internal testing has **no minimum tester count**; the binding gate for production (if the developer account is personal, created after 2023-11-13) is a **closed test with ≥12 testers opted-in for ≥14 days** — verify account type + requirement in Play Console. Supabase Pro upgrade at ~400 MAU.

**Deferred:** Separate staging environment / local Supabase migration validation — not worth it until real users + Supabase Pro (preview branches). The 3 dashboard-created tables (`sessions`, `hands`, `rake_presets`) should be baseline-dumped into a migration before there is real prod data, so migration history can rebuild the schema.
