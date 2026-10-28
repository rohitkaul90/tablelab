# Release notes — v1.11.0 (+20)

Cut 2026-10-28 (tag `v1.11.0` on the squash-merge of bump PR #127; hash recorded at tag time). Previous production release on Android: v1.9.0+16 (2026-10-16) — builds 17–19 (1.10.0–1.10.2) were iOS-only and never went to Play, so the Android notes also carry their user-facing fixes. iOS: 1.10.2 (19) was the first App Store submission; 1.11.0 (20) is the first update.

Track: Android production, 100% (standing rule since 2026-09-01). iOS: App Store Connect → "+ Version" 1.11.0 → build 20 → submit (never pull 1.10.2 from review).

## What's new — Play Console / App Store Connect fields (≤500 chars each)

### en-US
```
• Now also in Japanese, Traditional Chinese, Korean and Latin American Spanish: Settings → Language, or follow your phone.
• New currencies: Japanese yen, New Taiwan dollar, Korean won.
• Password reset links work from any device or browser.
• Fixed a crash when a Stats chart had a single period of data.
• Every Stats tab stays visible and says what to log when empty.
• Feedback sheet has a close button. AI coaching replies stay in English for now.
```

### es-ES
```
• Ahora también en japonés, chino tradicional, coreano y español latinoamericano (Ajustes → Idioma).
• Nuevas monedas: yen japonés, dólar taiwanés y won coreano.
• Restablecer la contraseña funciona desde cualquier dispositivo o navegador.
• Corregido un cierre cuando una gráfica de Estadísticas tenía un solo periodo.
• Las pestañas de Estadísticas siguen visibles e indican qué registrar si están vacías.
• Botón de cerrar en comentarios. El coaching con IA sigue en inglés.
```

### es-419
```
• Ahora también en japonés, chino tradicional, coreano y español latinoamericano (Ajustes → Idioma).
• Nuevas monedas: yen japonés, dólar taiwanés y won coreano.
• Restablecer la contraseña funciona desde cualquier dispositivo o navegador.
• Corregimos un cierre cuando una gráfica de Estadísticas tenía un solo periodo.
• Las pestañas de Estadísticas siguen visibles e indican qué registrar si están vacías.
• Botón de cerrar en comentarios. El coaching con IA sigue en inglés.
```

### fr-FR
```
• Désormais en japonais, chinois traditionnel, coréen et espagnol latino-américain (Paramètres → Langue).
• Nouvelles devises : yen, dollar taïwanais, won coréen.
• La réinitialisation du mot de passe fonctionne depuis tout appareil ou navigateur.
• Correction d'un plantage quand un graphique des Stats n'avait qu'une période.
• Chaque onglet des Stats reste visible et indique quoi enregistrer s'il est vide.
• Bouton Fermer sur la feuille de retour. Le coaching IA reste en anglais.
```

### it-IT
```
• Ora anche in giapponese, cinese tradizionale, coreano e spagnolo latinoamericano (Impostazioni → Lingua).
• Nuove valute: yen, dollaro taiwanese, won coreano.
• Il reset della password funziona da qualsiasi dispositivo o browser.
• Risolto un crash quando un grafico delle Statistiche aveva un solo periodo.
• Ogni scheda delle Statistiche resta visibile e indica cosa registrare se è vuota.
• Pulsante Chiudi nella scheda feedback. Il coaching IA resta in inglese.
```

### nl-NL
```
• Nu ook in het Japans, Traditioneel Chinees, Koreaans en Latijns-Amerikaans Spaans (Instellingen → Taal).
• Nieuwe valuta's: yen, Taiwanese dollar, Koreaanse won.
• Wachtwoord resetten werkt vanaf elk apparaat of elke browser.
• Crash opgelost als een Stats-grafiek maar één periode had.
• Elk Stats-tabblad blijft zichtbaar en zegt wat je moet loggen als het leeg is.
• Sluitknop in het feedbackvenster. AI-coaching blijft voorlopig Engels.
```

### ja-JP
```
• TableLabが日本語、繁体字中国語、韓国語、ラテンアメリカのスペイン語にも対応しました。設定 → 言語で選ぶか、端末の言語に合わせられます。
• 新しい通貨：日本円、新台湾ドル、韓国ウォン。
• パスワード再設定のリンクが、どの端末・ブラウザからでも使えるようになりました。
• フィードバック画面に閉じるボタンを追加。
• AIコーチングの回答は当面英語のままです。
• 統計のグラフにデータが1期間しかない場合にクラッシュする問題を修正。
• 統計の各内訳タブは常に表示され、空のときは何を記録すればよいかを案内します。
```

### zh-TW
```
• TableLab 現在也支援日文、繁體中文、韓文與拉丁美洲西班牙文。到「設定 → 語言」選擇，或跟隨手機語言。
• 新增幣別：日圓、新台幣與韓元。
• 重設密碼的連結現在可以在任何裝置或瀏覽器開啟。
• 意見回饋頁面新增關閉按鈕。
• AI 教練的回覆目前仍為英文。
• 修正統計圖表只有一個期間的資料時當機的問題。
• 統計的每個分析分頁都會持續顯示，空白時會說明該記錄什麼。
```

### ko-KR
```
• TableLab이 이제 일본어, 중국어(번체), 한국어, 라틴아메리카 스페인어도 지원해요. 설정 → 언어에서 고르거나 휴대폰 언어를 따르게 하세요.
• 새 통화: 일본 엔, 신 타이완 달러, 한국 원.
• 비밀번호 재설정 링크가 이제 어떤 기기나 브라우저에서도 작동해요.
• 피드백 화면에 닫기 버튼이 생겼어요.
• AI 코칭 답변은 당분간 영어로 제공돼요.
• 통계 그래프에 데이터가 한 기간만 있을 때 앱이 종료되던 문제를 수정했어요.
• 통계의 모든 분석 탭이 항상 표시되고, 비어 있으면 무엇을 기록할지 알려줘요.
```

## iOS "What's New" (App Store Connect, 1.11.0)

Same text per language as above. The Sign in with Apple line is NOT needed (it shipped in 1.10.x, the first iOS release); the password-reset line applies (1.10.2 already had the fix, but the first update's notes may still mention it).

## Underlying changes (internal)

- PR #122 — full-tag locale resolution (`kRegionalVariants`: es outside Spain → es_419; a lone shipped variant serves every device variant of its language), preference persisted as a BCP-47 tag, `intlLocaleCode`/`intlLocaleOf` (bare `zh` ARB formats as `zh_TW`), `platformLocaleTag` (`zh` declared as `zh-Hant` on Android/iOS), ARB checker accepts numeric regions, JPY/TWD/KRW currencies, thousands-grouped stakes parsing (`¥1,000/¥2,000`), monotone buy-in band edges.
- PR #___ — ja / zh (Traditional, Taiwan) / ko / es_419 ARBs (~1,377 keys each, Claude-translated with `tool/l10n/glossary.json` registers + pinned terms; es_419 adapted from es), `locales_config.xml` + `Info.plist` declarations, endonyms, spot-check and overflow tests.
- #125 Stats metric chart crash on a single period bucket (crash-issues-15); #126 every Stats breakdown tab always visible with a per-tab "what to log" empty state (11 new strings Ã 8 locales)
- #125 Stats metric chart crash on a single period bucket (crash-issues-15); #126 every Stats breakdown tab always visible with a per-tab "what to log" empty state (11 new strings × 8 locales)
- Carried from 1.10.x (never shipped on Android): #109 feedback-sheet close button, #117 cross-device password reset (token-hash recovery links), #110 in-app copy naming iOS.

Data Safety: no new permissions or SDKs on Android (`sign_in_with_apple` is iOS-only code; `app_links` was already a transitive dependency). `AndroidManifest.xml` unchanged since 1.9.0. No form change expected — owner to confirm before rollout.

Listing: four new Play listing languages (ja-JP, zh-TW, ko-KR, es-419) and the nine-language availability line in every existing listing — `launch/STORE_LISTING_translations.md`. App Store Connect: Japanese, Chinese (Traditional), Korean, Spanish (Mexico) — `launch/STORE_LISTING.md` §Localized listings.
