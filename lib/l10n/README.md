# App localization

- `app_en.arb` is the source of truth. Every key carries an `@key.description`
  (required for short strings — "Check" and "Call" are untranslatable without
  context). Placeholders use ICU: `{name}`, `{count, plural, one{…} other{…}}`,
  `{type, select, cash{…} tournament{…} other{…}}`.
- `app_es.arb`, `app_fr.arb`, `app_it.arb`, `app_nl.arb` are **generated** by
  `dart run tool/l10n/translate.dart` (Claude + `tool/l10n/glossary.json`) and
  then hand-reviewed. Edit a translation directly in the ARB via a normal PR —
  `translation_state.json` records the sha256 of the English source each
  translation was made from, so a reviewed line is never overwritten until its
  English changes (and then the script receives the reviewed text as
  `previousTranslation` to preserve wording).
- `generated/` is gitignored; `flutter pub get`, `flutter gen-l10n` and every
  `flutter build` regenerate it (`generate: true` in pubspec + `l10n.yaml`).
- `dart run tool/l10n/check_arb.dart` is the CI gate: missing/extra keys,
  placeholder mismatches, ICU without `other`, stale translations.

Workflow for a new string: add it to `app_en.arb` with a description → use it
as `context.l10n.key` → `dart run tool/l10n/translate.dart` → commit the ARBs +
state file → `flutter gen-l10n` → `dart run tool/l10n/check_arb.dart`.
