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
supabase db push                  # apply pending migrations

# Asset regeneration
dart run flutter_native_splash:create
dart run flutter_launcher_icons
dart run build_runner build --delete-conflicting-outputs   # only if @riverpod annotations added
```

## Slash-command agents

Twelve specialist agents live in `.claude/commands/`. Invoke with `/agent-name [args]`:

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

Start any new session on launch work with `/release-orchestrator` — it reads the actual codebase state and outputs a prioritized action plan.

## Architecture

**TableLab** is a Flutter poker bankroll tracker. Package name: `tablelab`. Dark Material 3 theme, seed color `#1B5E20`.

### Navigation flow

`main.dart → AuthGate → MainNavigation`

`AuthGate` uses `StreamBuilder<AuthState>` + `AnimatedSwitcher` to fade between `SplashScreen` (while auth resolves), `LoginScreen`, and `_OnboardingGate`. `_OnboardingGate` watches `profileProvider` — if `profile == null || !profile.hasSeenOnboarding` it shows `OnboardingScreen`, otherwise `MainNavigation`. The splash is shown until Supabase emits the first valid auth event — no minimum timer.

`MainNavigation` is an `IndexedStack` with a `NavigationBar` (5 tabs: Dashboard, Sessions, Hands, Reads, Tournaments). The `AppDrawer` is mounted via `mainScaffoldKey` (a `GlobalKey<ScaffoldState>` exported from `app_drawer.dart`) so any screen can call `mainScaffoldKey.currentState?.openDrawer()`.

Drawer sections: **Home** (Navigator.popUntil isFirst) → **Profile** → **APP** (Tournament Calendar, Settings, Help, About, Terms of Service, Data & Privacy, Feedback) → **Sign Out** (pinned). Screens pushed via Navigator.push must include `drawer: const AppDrawer()` on their Scaffold if they need drawer access; alternatively call `mainScaffoldKey.currentState?.openDrawer()` from a custom leading button.

Bottom nav tabs: Dashboard, Sessions, Hands, Reads, **Tools**. The Tools tab hosts `ToolsScreen` — a `SegmentedButton` pill toggle switching between `EquityCalculatorScreen(showScaffold: false)` and `IcmCalculatorScreen(showScaffold: false)` via `IndexedStack` (state preserved on tab switch). Both calculator screens accept `showScaffold: bool` (default `true`) — when `false` they return body content only, no Scaffold/AppBar, suitable for embedding.

`AuthGate` also handles `AuthChangeEvent.passwordRecovery` → shows `ResetPasswordScreen` (set new password + auto sign-out on success).

### State management — Riverpod

Service classes are plain Dart, wrapped in `Provider<>` at the provider layer. All providers live in `lib/providers/`.

| Provider | Type | Notes |
|---|---|---|
| `authUserIdProvider` | `StreamProvider<String?>` | emits current user ID on auth change |
| `sessionsProvider` | `StreamProvider` | Supabase stream; watches `authUserIdProvider` |
| `filteredSessionsProvider` | `Provider` | derived from sessions + filter |
| `filterProvider` | `StateProvider<SessionFilter>` | global session filter state |
| `handsProvider` | `FutureProvider` | fetch-once; watches `authUserIdProvider` |
| `tournamentListingsProvider` | `FutureProvider.autoDispose` | |
| `readsProvider` | `StreamProvider` | in `reads_provider.dart` |
| `profileProvider` | `FutureProvider` | in `profile_provider.dart`; watches `authUserIdProvider` |

**Cross-account scoping** — every user-scoped provider must `ref.watch(authUserIdProvider)` so it restarts when a different account signs in. After any write (insert/update/delete), call `ref.invalidate(sessionsProvider)` — Supabase `.stream()` requires Realtime enabled to push live changes; explicit invalidation is the reliable fallback.

### Backend — Supabase

All data is user-scoped via Row Level Security. Credentials live in `lib/config/supabase_config.dart` (anon key — public by design; file is gitignored). All Supabase calls go through `withSupabaseRetry<T>()` (`lib/services/supabase_retry.dart`), which retries once on PGRST303 (JWT clock-skew error).

**Tables:** `sessions`, `hands` (JSONB `hand_data`, nullable `session_id`), `player_reads`, `player_read_notes`, `rake_presets`, `profiles` (includes `starting_bankroll numeric`, `starting_bankroll_currency text`), `ai_analyses`, `ai_hand_analyses`, `ai_usage_log`, `tournament_listings`.

**Note:** `sessions`, `hands`, and `rake_presets` were created directly in the Supabase dashboard before the migration workflow was established — their DDL is not in `supabase/migrations/`. All other tables have migration files.

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
- Both functions store `cache_read_tokens` + `cache_write_tokens` per call (columns added to `ai_analyses` + `ai_hand_analyses`) for cost modeling

### CI/CD — GitHub Actions

Four active workflows in `.github/workflows/`:

| Workflow | Trigger | What it does |
|---|---|---|
| `ci.yml` | Push/PR to `main` | `flutter analyze --fatal-infos` + `flutter test --coverage` |
| `deploy-web.yml` | Push to `main` touching `lib/`, `web/`, `assets/`, `pubspec.*` | Builds web + deploys to `docs/` (preserves CNAME + .nojekyll) |
| `build-android.yml` | Push of `v*.*.*` tag | Decodes keystore from secret, builds signed AAB, creates GitHub Release |
| `scrape-tournaments.yml` | Weekly cron (Mon 9am UTC) | Calls `scrape-tournaments` Edge Function |

Required GitHub Secrets: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_ALIAS`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_PASSWORD`.

CI generates `lib/config/supabase_config.dart` at build time from secrets — it is never committed. The `deploy-web.yml` commit uses `[skip ci]` in its message to prevent loops.

### Firebase Crashlytics

Active on Android only. `lib/firebase_options.dart` is generated (not a stub) — do not overwrite it. `main.dart` routes `FlutterError` and `PlatformDispatcher` errors to Crashlytics, guarded by `if (!kIsWeb)` — Crashlytics throws on web. `android/app/google-services.json` is committed and required for Android builds.

### Splash screen

Three layers, all matching background `#111811`:
1. **Native** — generated by `flutter_native_splash`; assets in `android/app/src/main/res/` and `ios/Runner/`; Android 12+ uses Splash Screen API with icon on `#1B5E20` circle
2. **Flutter overlay** — `lib/widgets/splash_screen.dart`; shown by `AuthGate` until auth resolves; fades via `AnimatedSwitcher(duration: 350ms)`
3. **Web** — custom HTML/CSS in `web/index.html`; splash div fades out on `flutter-first-frame` event

### Equity Calculator

`lib/screens/equity_calculator_screen.dart` + `lib/widgets/equity/`.

Each player has two modes toggled in `PlayerRangeEditor`:
- **Range mode** — 13×13 matrix + GTO presets; `expandCombos()` expands to all concrete card pairs
- **Exact Hand mode** — two specific cards via `CardPickerSheet`; `expandCombos()` returns a single `[[card1, card2]]`

Board cards and other exact-hand players' cards are passed as `excludedCards`. Simulation runs via Monte Carlo (`lib/equity/simulator.dart`).

### Key subsystems

- **`lib/equity/`** — offline equity: card encoding (rank×4+suit), 7-card evaluator (brute-force 5-card combos), Monte Carlo simulator, GTO preflop ranges
- **`lib/reads/`** — `insights_engine.dart` (rule-based coaching from player tags), `tag_definitions.dart`
- **`lib/utils/helpers.dart`** — currency conversion, `parseBBFromStakes`, `calcBB100`, `formatPL`, `fieldSizeBucket`, all shared formatting

### Models

`SessionModel` — `fromMap()` (snake_case DB → camelCase Dart).  
`PokerHand` — `fromJson()`/`toJson()` (entire hand serialized as JSONB); has optional `tournamentStage` and `TableSetup.ante` fields.  
All models are plain immutable classes — no code generation.

### Hand recording

`HandInputScreen` supports tournament hands: `isTournamentSession` param shows stage dropdown, ante field, relabels stakes as "Blind Level". All-in runout: `_allInSeats` persists across streets; `_isAllInRunout` getter auto-deals remaining streets when ≤1 non-all-in player remains. Undo stack (`_HandSnapshot`) captures state before each action.

### Critical patterns

**Async + ref after widget disposal** — always guard `ref` usage after any `await` with `if (!mounted) return;` (use `mounted` in `State`/`ConsumerState`, not `context.mounted`). `AppDrawer._confirmSignOut` is the canonical example.

**Dismissible + provider invalidation** — never call `ref.invalidate` in `onDismissed` without first removing the item from local state. Pattern: `ConsumerStatefulWidget` + `Set<String> _deletingIds`; add ID on dismiss, filter list in build, call service async. See `HandsScreen`.

**Save button guard** — any form with an async save must have `bool _saving` that disables the button during the call to prevent double-submission.

**fl_chart on Windows** — always set `barTouchData: BarTouchData(enabled: false)` and `lineTouchData: const LineTouchData(enabled: false)` on every chart. Default enabled state throws `RangeError` on Windows when mouse nears edge.

### Analyzer configuration

`analysis_options.yaml` excludes `test_imports/` (untracked scratch directory) and disables `use_null_aware_elements` (requires Dart SDK ≥3.8 collection literal syntax not yet available). `flutter analyze --fatal-infos` must return zero issues — CI enforces this.

### Web deployment — critical details

- Custom domain `tablelab.app` → build with `--base-href /` (root, not `/tablelab/`)
- Web build output goes into `docs/` folder on `main` branch (GitHub Pages source)
- `docs/CNAME` must contain `tablelab.app` — preserve it on every deploy
- `docs/.nojekyll` must exist — recreate after every wipe
- PowerShell for the flutter build command; bash for the file copy
- `web/privacy.html` is served at `tablelab.app/privacy` — required by Apple App Store review

### Android build

- `compileSdk = 36`, `minSdk = maxOf(flutter.minSdkVersion, 23)` (flutter_secure_storage requires API 23+; `maxOf` prevents Android Studio/Flutter Gradle plugin from silently reverting to 21), `targetSdk = 35` — all in `android/app/build.gradle.kts`
- `android/build.gradle.kts` has a `gradle.afterProject` block that forces `languageVersion` and `apiVersion` to `KOTLIN_2_0` for all plugin subprojects — required because KGP 2.3+ dropped support for Kotlin 1.6 (used by `posthog_flutter` and others)
- Release signing reads `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` from env vars; falls back to debug signing locally when `tablelab-release.jks` is absent
- `tablelab-release.jks` is gitignored — CI decodes it from `ANDROID_KEYSTORE_BASE64` secret
- ProGuard enabled on release builds (`android/app/proguard-rules.pro`)
- `INTERNET` permission explicitly declared in `AndroidManifest.xml`
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

All analytics calls go through `lib/services/analytics_service.dart` — static fire-and-forget methods with a Windows no-op guard. Events wired: `onboarding_completed`, `onboarding_skipped`, `session_logged`, `hand_recorded`, `ai_session_analysis_requested`, `ai_hand_analysis_requested`, `ai_rate_limit_hit`.

### Onboarding

`lib/screens/onboarding_screen.dart` — 3-page `PageView` with `PopScope(canPop: false)`. Completion calls `ProfileService.markOnboardingComplete()` which upserts `has_seen_onboarding = true` on `profiles`. `_OnboardingGate` in `auth_gate.dart` gates on `profile.hasSeenOnboarding`. Existing users are grandfathered (`DEFAULT true` on column add, reset to `false` for new inserts via second migration).

### Pre-launch status (as of 2026-05-31)

**Done:** Play Store screenshots (8 phone + 8×7" + 8×10" tablet), Play Console internal track live, data safety form, onboarding flow, PostHog analytics, delete-account, GDPR polish, all Supabase migrations applied, Edge Functions hardened and deployed, RLS hardened, UptimeRobot monitors, Anthropic spend alerts ($80 alert / $100 hard limit).

**Remaining:** Add ≥5 testers to Play Console internal track → collect beta feedback → promote to production. Supabase Pro upgrade at ~400 MAU.
