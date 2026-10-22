# App Review reply — iOS 1.10.1 (18), Guideline 2.1 "Information Needed"

Submission `249d6273-dcfa-4f9c-b959-a17ea937fdbf`, rejected 2026-10-22 01:05 (Apple message
"Guideline 2.1 - Information Needed - New App Submission"). Not a bug, metadata or policy finding:
Apple asks every developer account with a *limited App Review history* for extra context on its
first submission. **Same build 18 is resubmitted — no code change, no re-tag.**

Three paste-ready blocks below. Order of operations in App Store Connect (owner, irreversible
clicks):

1. Record the video (block C), check it, keep it on the phone / AirDrop it to the PC.
2. App Store tab → version 1.10.1 → **App Review Information → Notes**: replace the text with
   block B. Keep "Sign-in required" = Yes and the demo account that is already there. **Log in
   with that account on the iPhone first** to prove the password still works (Play rejected
   v1.8.0 on exactly this). Save.
3. App Review page → **Reply to App Review**: paste block A, attach the video (or, if the upload
   is refused, paste an unlisted link — YouTube unlisted or a Google Drive "anyone with the link"
   share — and put the same link into the Notes field).
4. **Resubmit to App Review**. Release stays MANUAL.

Fill `<iOS version>` (Settings → General → About → iOS Version, after installing any pending
update) and `<link>` (only if the video is hosted) before pasting.

---

## A. Reply text (paste into "Reply to App Review")

~4,900 characters. If the reply box enforces a limit (it may cap at 4,000), send it as TWO
messages in the same thread: items 1–4 first (with the video attached), then items 5–7 — the
thread accepts multiple replies before resubmitting.

```
Thank you for the review. Below is the requested information, numbered to match your list. The same information has been added to the Notes field of App Review Information.

1. Screen recording
Attached: tablelab-ios-review.mp4, recorded on an iPhone 17e running iOS <iOS version>, starting from a cold launch. It shows: onboarding, account registration with email and the confirmation link, login, logging a poker session, recording a hand and requesting AI coaching, the Study tab (strategy charts), the Tools and Settings screens, and account deletion from Settings, which returns the user to the login screen.
- The app has no user-generated content that is visible to other users. Sessions, hands, player reads and notes are private to the account that created them, so there is no content reporting or blocking mechanism.
- The app has no paid content or features. Everything is free.

2. Purpose and audience
TableLab is a results tracker and study tool for people who play poker elsewhere (live card rooms, home games, online sites). Players log the sessions they have already played and the app computes their bankroll trend, win rate, ROI, variance and other statistics. They can record individual hands, replay them, and request AI-generated coaching that is grounded in deterministic equity and pot-odds math and in strategy charts we computed offline with a solver. The audience is adult poker players who want to understand where their results come from and what to fix in their decisions. Nothing is played or wagered inside the app.

3. Setup and access
Sign in with the demo account listed in App Review Information (email and password; the same account is on file with Google Play for the Android version). Alternatively create a new account with email, Google, or Sign in with Apple; email sign-up sends a confirmation link.
Main features: Stats tab (bankroll and statistics, tap any stat for its chart); Sessions tab (the + button offers "Start live" to run a session in real time or "Log past" to enter one); Hands tab (the + button offers Quick Hand or Full Hand; a hand's menu opens AI Coaching and the replayer); Reads tab (private notes and tags about opponents); Study tab (solver-computed strategy charts for preflop and postflop spots); the side menu holds Tools (Equity, ICM and Variance calculators), Tournament Calendar, Settings, Help and Data & Privacy. Account deletion is in Settings ("Delete account") and removes all server data and, for Sign in with Apple users, revokes the Apple authorization. No sample files are required; the demo account already contains sessions and hands. CSV/Excel import of sessions from other apps is optional (Settings → Data).

4. External services
- Supabase: authentication (email/password, Google, and Sign in with Apple providers), PostgreSQL database with row-level security, and Edge Functions; hosted on Amazon Web Services.
- Anthropic (Claude API): generates the AI coaching text. Called only when the user taps Analyse, through our Supabase Edge Function; the hand or session details are sent, no API key is on the device.
- Firebase Crashlytics (Google): crash reporting.
- PostHog: product usage analytics (feature usage events; no cross-app tracking, no advertising).
- Cloudflare R2 (packs.tablelab.app): hosts our own pre-computed strategy chart files that the Study tab downloads.
- PokerNews: the source of the tournament calendar listings (public event schedules, collected weekly by our server and attributed in the app); declared under Content Rights.
- Loops: delivery of the account emails described in our privacy policy (receives the email address only).
- tablelab.app (GitHub Pages behind Cloudflare): the email-confirmation landing page, privacy policy and terms.
No payment processor, no advertising SDK, no third-party login other than Google and Apple.

5. Regional differences
None. The app functions identically in every region with the same content. The interface is available in English, Spanish, French, Italian and Dutch and follows the device language; AI coaching text is in English everywhere.

6. Regulated industry / protected material
TableLab is not a gambling product. It does not offer real-money or simulated gambling, takes no wagers, holds no funds, and does not connect to any poker operator, betting provider or odds service; it records results of games played elsewhere, like a sports results diary. No licence or regulatory authorization applies. The only third-party material is the tournament calendar, which lists public event schedules sourced from PokerNews with attribution (declared under Content Rights). The strategy charts and all coaching content are our own output.

7. In-App Purchases
None. The app is completely free: no subscriptions, no consumables, no unlockable features, and no In-App Purchase products are configured.

Please let us know if anything else would help complete the review.
```

## B. Notes field (App Review Information → Notes; replaces the earlier paragraph; ≤ 4000 chars)

```
TableLab is a results tracker and study tool for poker players. It contains no gambling, real or simulated: nothing can be played or wagered in the app, no funds are held, and it connects to no poker operator or betting service. Users log sessions they played elsewhere, record hands, review statistics, study solver-computed strategy charts, and request AI-generated coaching.

ACCESS: Sign-in is required. Use the demo account above (email + password; it already contains sessions and hands). New accounts can also be created with email (confirmation link), Google, or Sign in with Apple. The demo account uses email.

FEATURES: Stats tab (bankroll/statistics), Sessions tab (+ = Start live or Log past), Hands tab (+ = Quick or Full hand; hand menu = AI Coaching / replayer), Reads tab (private opponent notes), Study tab (strategy charts downloaded from our own server), side menu = Tools (Equity/ICM/Variance calculators), Tournament Calendar, Settings, Help, Data & Privacy. "Delete account" in Settings removes all server data and revokes the Sign in with Apple authorization. Optional CSV/Excel import under Settings > Data.

USER CONTENT: nothing a user enters is visible to other users (no sharing, no feed, no messaging), so there is no reporting/blocking mechanism.

EXTERNAL SERVICES: Supabase (auth incl. Google + Apple providers, Postgres DB, Edge Functions; on AWS), Anthropic Claude API (AI coaching, only when the user taps Analyse, via our Edge Function), Firebase Crashlytics (crashes), PostHog (usage analytics, no tracking), Cloudflare R2 at packs.tablelab.app (our strategy chart files), PokerNews (source of the tournament calendar listings, declared under Content Rights), Loops (account emails), tablelab.app (confirmation page, privacy, terms). No payment processor, no ads.

REGIONS: identical features and content everywhere; UI in en/es/fr/it/nl following the device language; AI coaching text is English.

IN-APP PURCHASES: none. The app is fully free.

REVIEW HISTORY: the first 1.10.1 submission received Guideline 2.1 "Information Needed"; a device screen recording (cold launch, email registration, login, session + hand + AI coaching, Study, Settings, account deletion) was supplied in the reply on that submission<link>.
```

If the video is hosted, replace `<link>` with ` and is available at https://…`; otherwise delete `<link>`.

## C. Recording runbook (owner, iPhone 17e, build 18 from TestFlight)

Prep
- Settings → General → Software Update: install anything pending. Apple asked for the "latest
  operating system"; note the version for block A.
- Settings → Control Center: add Screen Recording. Enable Do Not Disturb (no notifications in
  the clip). Portrait only.
- Decide the throwaway account: a Gmail plus-alias such as `<your gmail>+review@gmail.com` works
  (the confirmation mail lands in the normal inbox; Supabase treats it as a distinct user).
  **Never use the demo account on file** — the clip must end with account deletion, and deleting
  the review account would invalidate the credentials in App Store Connect and Google Play and
  cause the next rejection ("Guideline 2.1 – Accessing the app").
- If the app is open, swipe it out of the app switcher so the clip starts from a cold launch.

Flow (one take, aim for 3–5 minutes; the microphone can stay off)
1. Start recording from Control Center, go to the Home screen, tap TableLab.
2. Onboarding pages → Sign up with the throwaway email + a password.
3. Open Mail (or Gmail), tap the confirmation link → tablelab.app/confirmed.html → "Open the
   TableLab app" → log in with the same credentials.
4. Stats tab briefly → Sessions tab → + → Log past → fill a cash session (date, location, stakes,
   buy-in, cash-out) → Save. Show the session in the list, tap it, show the detail.
5. Hands tab → + → Quick Hand → hero cards, position, stakes, the decision, result → Save.
6. Hand menu (⋮) → AI Coaching → wait for the result and scroll through it (this is the
   Anthropic call; it takes a few seconds). Back.
7. Study tab → tap through one spot (board picker, a postflop action) so the charts render.
8. Side menu → Tools → switch the pill through Equity / ICM / Variance once. Back.
9. Side menu → Settings → show the language/theme rows → scroll to "Delete account" → tap →
   confirm → the app returns to the login screen. Hold 2 seconds.
10. Stop recording (Control Center or the red status indicator).

Optional second clip (30–45 s) if you want to show Sign in with Apple: login screen → Sign in with
Apple → Hide My Email → Continue → onboarding → Settings → Delete account. Afterwards check
Settings → Apple ID → Sign in with Apple no longer lists TableLab.

Check before sending
- The clip shows registration, login and deletion end to end; nothing personal is visible
  (no notification banners, no password on screen other than dots, no other apps' content).
- Trim dead time in Photos (Edit → trim). A few minutes at the phone's default quality is fine;
  if App Store Connect refuses the attachment for size, re-export at 1080p from Photos or share
  it via an unlisted link instead and reference the link in both block A and block B.
- Name the file `tablelab-ios-review.mp4` (Photos exports `.mov`; App Store Connect accepts
  either — keep the name consistent with block A or edit the name there).
