# Release notes — v1.11.1 (+21)

Cut 2026-10-31 for the iOS App Review resubmission (1.10.2 build 19 was rejected under 2.2 / 2.3.10 /
2.3.6 — see `launch/APP_REVIEW_REPLY.md` round 3). **iOS only**: tag `v1.11.1` → `build-ios.yml` →
TestFlight build 21 → App Store Connect version 1.11.1. The Android AAB is built by the same tag but
NOT uploaded to Play (production stays on 1.11.0+20, owner decision 2026-10-31); Android picks the
change up with its next release.

Change vs 1.11.0: the Study tab's "BETA" badge / chip / footer prefix are gone (the disclosure that
strategies are refined over time now sits behind an info icon next to the Study title). Nothing else.

## iOS "What's New" (App Store Connect, 1.11.1 — first App Store release, so it describes the app; no Android mention)

### en-US
```
TableLab is now on iPhone: bankroll tracking, hand replays, equity/ICM/variance calculators, a solver-computed study library and AI coaching, with Sign in with Apple. Your account syncs with the web app at tablelab.app.
```

### es-ES / es-MX
```
TableLab llega al iPhone: seguimiento de bankroll, repetición de manos, calculadoras de equity, ICM y varianza, una biblioteca de estudio calculada por solver y coaching con IA, con inicio de sesión con Apple. Tu cuenta se sincroniza con la app web en tablelab.app.
```

### fr-FR
```
TableLab arrive sur iPhone : suivi de bankroll, replays de mains, calculateurs d'equity, d'ICM et de variance, une bibliothèque d'étude calculée par solver et un coaching IA, avec la connexion avec Apple. Ton compte se synchronise avec l'app web sur tablelab.app.
```

### it-IT
```
TableLab arriva su iPhone: gestione del bankroll, replay delle mani, calcolatori di equity, ICM e varianza, una libreria di studio calcolata dal solver e coaching con IA, con l'accesso con Apple. Il tuo account si sincronizza con l'app web su tablelab.app.
```

### nl-NL
```
TableLab is er nu voor iPhone: bankroll bijhouden, handen terugkijken, equity-, ICM- en variantiecalculators, een door solvers berekende studiebibliotheek en AI-coaching, met inloggen via Apple. Je account synchroniseert met de web-app op tablelab.app.
```

### ja-JP
```
TableLabがiPhoneに登場：バンクロール管理、ハンドのリプレイ、エクイティ・ICM・分散の計算機、ソルバーで計算した学習ライブラリ、AIコーチング。Appleでサインインに対応。アカウントはウェブ版（tablelab.app）と同期します。
```

### zh-TW
```
TableLab 登陸 iPhone：bankroll 追蹤、手牌重播、勝率 / ICM / 變異數計算機、solver 計算的學習庫與 AI 教練，支援使用 Apple 登入。帳號會與網頁版 tablelab.app 同步。
```

### ko-KR
```
TableLab이 iPhone에 출시됐어요: 뱅크롤 추적, 핸드 리플레이, 에퀴티·ICM·분산 계산기, 솔버로 계산한 학습 라이브러리, AI 코칭, Apple로 로그인. 계정은 웹 앱(tablelab.app)과 동기화돼요.
```

## Underlying changes (internal)

- Study tab: `BETA` `Badge` removed from the bottom-nav icon (`lib/main.dart`); the AppBar "BETA" pill became an `info_outline` icon opening the "About Study's strategies" dialog (`gto_explorer_screen.dart`); ARB keys `studyBeta*` → `studyInfo*`, `studyFooter` drops "Beta ·" (8 locales re-translated); `web/gto-library.html` no longer says the in-app footer reads "Beta".
- Listing docs: `launch/STORE_LISTING.md` (no Android / no "(beta)" in the App Store copy, age rating Frequent simulated gambling → 18+), `launch/STORE_LISTING_translations.md`, `launch/APP_REVIEW_REPLY.md` round 3.

Data Safety / App Privacy: unchanged (no new SDKs or permissions).
