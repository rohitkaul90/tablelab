# App Review reply — iOS 1.10.1 (18), Guideline 2.1 "Information Needed"

Submission `249d6273-dcfa-4f9c-b959-a17ea937fdbf`, rejected 2026-10-22 01:05 — **answered and RESUBMITTED 2026-10-22 with build 1.10.2 (19)** (the App Store version field had to be changed 1.10.1 → 1.10.2 so build 19 became selectable) (Apple message
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

**The reply box caps at 4,000 characters** (confirmed 2026-10-22). This version is ~3,550 chars with all seven items; the recording went as a Google Photos share link (900 MB was too big to attach — an anonymous fetch confirmed the link opens without a Google account).

```
Thank you for the review. Here is the requested information, numbered to match your list. It has also been added to the Notes field of App Review Information.

1. Screen recording
<link to the recording> (about 900 MB, so shared as a link). Recorded on an iPhone 17e running iOS 27.0.1, from a cold launch. It shows onboarding, email registration and the confirmation link, login, logging a session, recording a hand and requesting AI coaching, the Study tab, Tools and Settings, and account deletion from Settings back to the login screen.
- No user-generated content is visible to other users (sessions, hands, reads and notes are private to the account), so there is no reporting or blocking mechanism.
- There is no paid content; everything is free.

2. Purpose and audience
TableLab is a results tracker and study tool for people who play poker elsewhere (card rooms, home games, online). Players log sessions they have already played and get bankroll trend, win rate, ROI and variance statistics; they can record hands, replay them, and request AI coaching grounded in deterministic equity and pot-odds math and in strategy charts we computed offline with a solver. The audience is adult poker players. Nothing is played or wagered in the app.

3. Setup and access
Sign in with the demo account in App Review Information (email and password; the same account is on file with Google Play), or create an account with email, Google, or Sign in with Apple. Main features: Stats tab; Sessions tab (+ = Start live or Log past); Hands tab (+ = Quick or Full hand; a hand's menu opens AI Coaching and the replayer); Reads tab (private opponent notes); Study tab (strategy charts); side menu = Tools (Equity, ICM, Variance calculators), Tournament Calendar, Settings, Help, Data & Privacy. "Delete account" in Settings removes all server data and revokes the Sign in with Apple authorization. No sample files are needed; the demo account already has sessions and hands.

4. External services
- Supabase: authentication (email, Google, Sign in with Apple), Postgres database, Edge Functions (hosted on AWS).
- Anthropic (Claude API): generates the AI coaching text, only when the user taps Analyse, via our Edge Function; no API key on the device.
- Firebase Crashlytics: crash reporting. PostHog: usage analytics (no cross-app tracking, no ads).
- Cloudflare R2 (packs.tablelab.app): hosts our own strategy chart files for the Study tab.
- PokerNews: source of the tournament calendar listings (public event schedules, attributed; declared under Content Rights).
- Loops: delivery of account emails. tablelab.app: email-confirmation page, privacy policy, terms.
No payment processor, no advertising SDK.

5. Regional differences
None. The app works identically everywhere. The UI is in English, Spanish, French, Italian and Dutch, following the device language; AI coaching text is English.

6. Regulated industry / protected material
Not a gambling product: no real-money or simulated gambling, no wagers, no funds held, no connection to any poker operator or betting service. It records results of games played elsewhere, like a sports results diary; no licence applies. The only third-party material is the tournament calendar sourced from PokerNews (declared under Content Rights). Strategy charts and coaching are our own output.

7. In-App Purchases
None. The app is completely free: no subscriptions, no unlockable features, no IAP products configured.

Please let us know if anything else would help.
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
