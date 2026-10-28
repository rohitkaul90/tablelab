# Release notes — v1.11.0 (+20)

Cut 2026-__-__ from `_______` (tag `v1.11.0`, bump via PR #___). Previous production release on Android: v1.9.0+16 (2026-10-16) — builds 17–19 (1.10.0–1.10.2) were iOS-only and never went to Play, so the Android notes also carry their user-facing fixes. iOS: 1.10.2 (19) was the first App Store submission; 1.11.0 (20) is the first update.

Track: Android production, 100% (standing rule since 2026-09-01). iOS: App Store Connect → "+ Version" 1.11.0 → build 20 → submit (never pull 1.10.2 from review).

## What's new — Play Console / App Store Connect fields (≤500 chars each)

### en-US
```
• TableLab now also speaks Japanese, Traditional Chinese, Korean and Latin American Spanish. Pick your language in Settings → Language, or let it follow your phone.
• New currencies: Japanese yen, New Taiwan dollar and Korean won.
• Password reset links now work from any device or browser.
• The feedback sheet has a close button.
• AI coaching replies stay in English for now.
```

### es-ES
```
• TableLab ahora también habla japonés, chino tradicional, coreano y español de Latinoamérica. Elige tu idioma en Ajustes → Idioma o deja que siga al de tu móvil.
• Nuevas monedas: yen japonés, dólar taiwanés y won coreano.
• Los enlaces para restablecer la contraseña ya funcionan desde cualquier dispositivo o navegador.
• La hoja de comentarios tiene un botón para cerrar.
• Las respuestas del coaching con IA siguen en inglés por ahora.
```

### es-419
```
• TableLab ahora también habla japonés, chino tradicional, coreano y español de Latinoamérica. Elige tu idioma en Ajustes → Idioma o deja que siga al de tu celular.
• Nuevas monedas: yen japonés, dólar taiwanés y won coreano.
• Los enlaces para restablecer la contraseña ya funcionan desde cualquier dispositivo o navegador.
• La hoja de comentarios tiene un botón para cerrar.
• Las respuestas del coaching con IA siguen en inglés por ahora.
```

### fr-FR
```
• TableLab parle désormais aussi japonais, chinois traditionnel, coréen et espagnol d'Amérique latine. Choisis ta langue dans Paramètres → Langue, ou laisse-la suivre celle de ton téléphone.
• Nouvelles devises : yen japonais, dollar taïwanais et won coréen.
• Les liens de réinitialisation du mot de passe fonctionnent désormais depuis n'importe quel appareil ou navigateur.
• La feuille de retour a un bouton Fermer.
• Les réponses du coaching IA restent en anglais pour l'instant.
```

### it-IT
```
• TableLab ora parla anche giapponese, cinese tradizionale, coreano e spagnolo dell'America Latina. Scegli la lingua in Impostazioni → Lingua, oppure lascia che segua quella del telefono.
• Nuove valute: yen giapponese, dollaro taiwanese e won coreano.
• I link per reimpostare la password ora funzionano da qualsiasi dispositivo o browser.
• La scheda feedback ha un pulsante per chiudere.
• Le risposte del coaching IA restano in inglese per ora.
```

### nl-NL
```
• TableLab is nu ook beschikbaar in het Japans, Traditioneel Chinees, Koreaans en Latijns-Amerikaans Spaans. Kies je taal via Instellingen → Taal, of laat de app je telefoon volgen.
• Nieuwe valuta's: Japanse yen, Nieuwe Taiwanese dollar en Koreaanse won.
• Links om je wachtwoord te resetten werken nu vanaf elk apparaat of elke browser.
• Het feedbackvenster heeft een sluitknop.
• Antwoorden van de AI-coaching blijven voorlopig Engels.
```

### ja-JP
```
• TableLabが日本語、繁体字中国語、韓国語、ラテンアメリカのスペイン語にも対応しました。設定 → 言語で選ぶか、端末の言語に合わせられます。
• 新しい通貨：日本円、新台湾ドル、韓国ウォン。
• パスワード再設定のリンクが、どの端末・ブラウザからでも使えるようになりました。
• フィードバック画面に閉じるボタンを追加。
• AIコーチングの回答は当面英語のままです。
```

### zh-TW
```
• TableLab 現在也支援日文、繁體中文、韓文與拉丁美洲西班牙文。到「設定 → 語言」選擇，或跟隨手機語言。
• 新增幣別：日圓、新台幣與韓元。
• 重設密碼的連結現在可以在任何裝置或瀏覽器開啟。
• 意見回饋頁面新增關閉按鈕。
• AI 教練的回覆目前仍為英文。
```

### ko-KR
```
• TableLab이 이제 일본어, 중국어(번체), 한국어, 라틴아메리카 스페인어도 지원해요. 설정 → 언어에서 고르거나 휴대폰 언어를 따르게 하세요.
• 새 통화: 일본 엔, 신 타이완 달러, 한국 원.
• 비밀번호 재설정 링크가 이제 어떤 기기나 브라우저에서도 작동해요.
• 피드백 화면에 닫기 버튼이 생겼어요.
• AI 코칭 답변은 당분간 영어로 제공돼요.
```

## iOS "What's New" (App Store Connect, 1.11.0)

Same text per language as above. The Sign in with Apple line is NOT needed (it shipped in 1.10.x, the first iOS release); the password-reset line applies (1.10.2 already had the fix, but the first update's notes may still mention it).

## Underlying changes (internal)

- PR #122 — full-tag locale resolution (`kRegionalVariants`: es outside Spain → es_419; a lone shipped variant serves every device variant of its language), preference persisted as a BCP-47 tag, `intlLocaleCode`/`intlLocaleOf` (bare `zh` ARB formats as `zh_TW`), `platformLocaleTag` (`zh` declared as `zh-Hant` on Android/iOS), ARB checker accepts numeric regions, JPY/TWD/KRW currencies, thousands-grouped stakes parsing (`¥1,000/¥2,000`), monotone buy-in band edges.
- PR #___ — ja / zh (Traditional, Taiwan) / ko / es_419 ARBs (~1,377 keys each, Claude-translated with `tool/l10n/glossary.json` registers + pinned terms; es_419 adapted from es), `locales_config.xml` + `Info.plist` declarations, endonyms, spot-check and overflow tests.
- Carried from 1.10.x (never shipped on Android): #109 feedback-sheet close button, #117 cross-device password reset (token-hash recovery links), #110 in-app copy naming iOS.

Data Safety: no new permissions or SDKs on Android (`sign_in_with_apple` is iOS-only code; `app_links` was already a transitive dependency). `AndroidManifest.xml` unchanged since 1.9.0. No form change expected — owner to confirm before rollout.

Listing: four new Play listing languages (ja-JP, zh-TW, ko-KR, es-419) and the nine-language availability line in every existing listing — `launch/STORE_LISTING_translations.md`. App Store Connect: Japanese, Chinese (Traditional), Korean, Spanish (Mexico) — `launch/STORE_LISTING.md` §Localized listings.
