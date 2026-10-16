# Release notes — v1.9.0 (+16)

Cut 2026-10-16 from `45636e7` (tag `v1.9.0`, bump via PR #97). Previous production release: v1.8.0+15 (2026-09-01). Track: production, 100% (standing rule since 2026-09-01).

## What's new — Play Console fields (≤500 chars each)

### en-US
```
• TableLab now speaks Spanish, French, Italian and Dutch. Pick your language in Settings → Language, or let it follow your phone.
• Dates and numbers follow your language too.
• AI coaching replies stay in English for now; every screen around them is translated.
• Fixed a crash on startup for some copied or restored installs. You now get a clear prompt to reinstall from Google Play.
• Help answers updated.
```

### es-ES
```
• TableLab ya está en español, francés, italiano y neerlandés. Elige tu idioma en Ajustes → Idioma o deja que siga al de tu móvil.
• Las fechas y los números también siguen tu idioma.
• Las respuestas del coaching con IA siguen en inglés por ahora; todas las pantallas a su alrededor están traducidas.
• Corregido un cierre al abrir la app en algunas instalaciones copiadas o restauradas.
```

### fr-FR
```
• TableLab parle désormais espagnol, français, italien et néerlandais. Choisis ta langue dans Paramètres → Langue, ou laisse-la suivre celle de ton téléphone.
• Les dates et les nombres suivent aussi ta langue.
• Les réponses du coaching IA restent en anglais pour l'instant ; tous les écrans autour sont traduits.
• Correction d'un plantage au démarrage sur certaines installations copiées ou restaurées.
```

### it-IT
```
• TableLab ora parla spagnolo, francese, italiano e olandese. Scegli la lingua in Impostazioni → Lingua, oppure lascia che segua quella del telefono.
• Anche date e numeri seguono la tua lingua.
• Le risposte del coaching IA restano in inglese per ora; tutte le schermate intorno sono tradotte.
• Risolto un crash all'avvio su alcune installazioni copiate o ripristinate.
```

### nl-NL
```
• TableLab is nu beschikbaar in het Spaans, Frans, Italiaans en Nederlands. Kies je taal via Instellingen → Taal, of laat de app je telefoon volgen.
• Datums en getallen volgen ook je taal.
• Antwoorden van de AI-coaching blijven voorlopig Engels; alle schermen eromheen zijn vertaald.
• Crash bij opstarten opgelost voor sommige gekopieerde of herstelde installaties.
```

## Underlying changes (internal)

- #86 native-libs-absent startup guard (crash-issues-14): reinstall dialog + Crashlytics non-fatal instead of a crash loop
- #87 l10n scaffolding (gen-l10n, Settings → Language, Android 13 per-app language via `localeConfig`, Claude translation script + `check_arb` CI gate)
- #88 analytics grouping keys split from labels; #93 buy-in bands rounded per display currency
- #89 sessions, #90 hands, #91 shell/account, #92 reads, #93 stats, #94 AI/Study/tools/calendar, #96 Help/import/legal — ~1,372 strings × es/fr/it/nl
- #95 locale-aware number/date display (storage/export/import stay en_US)
- #96 Help FAQ corrected (in-app account deletion exists; navigation answers updated)

Data Safety: no new permissions or SDKs (`flutter_localizations` is part of the Flutter SDK; `crypto` is a dev-only dependency). PostHog gains a `language_changed` event and a `language` person property — same analytics category already declared (app activity); no form change expected, owner to confirm.
