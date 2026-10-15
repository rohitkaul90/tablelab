// Pure ARB consistency rules shared by `tool/l10n/check_arb.dart` (the CI gate)
// and `tool/l10n/translate.dart` (validates model output before writing).
// No Flutter imports — runs under plain `dart run` and in unit tests
// (test/tool/arb_check_test.dart).
import 'dart:convert';

import 'package:crypto/crypto.dart';

/// The ARB template locale (source of truth for every other locale).
const kTemplateLocale = 'en';

/// sha256 of an English source string — the sidecar `translation_state.json`
/// stores this per (locale, key) so a translation is re-generated only when its
/// English source changes (a reviewer's hand edit is never overwritten until
/// then).
String sourceHash(String englishValue) =>
    sha256.convert(utf8.encode(englishValue)).toString();

/// Message keys of an ARB map: everything that isn't `@@locale`-style metadata
/// or an `@key` attribute block.
Iterable<String> messageKeys(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@'));

/// ICU placeholders referenced by a message, e.g. `{name}` or the argument of
/// `{count, plural, ...}`. A `{` directly preceded by a word character opens a
/// plural/select BRANCH body (`one{...}`), not a placeholder, so it is skipped;
/// anything else that opens with an identifier followed by `,` or `}` is one.
Set<String> placeholdersOf(String message) {
  final out = <String>{};
  for (var i = 0; i < message.length; i++) {
    if (message[i] != '{') continue;
    if (i > 0 && _isWordChar(message[i - 1])) continue; // branch body
    var j = i + 1;
    while (j < message.length && message[j] == ' ') {
      j++;
    }
    final start = j;
    // Identifiers start with a letter or underscore (never a digit).
    if (j >= message.length || _isDigit(message[j])) continue;
    while (j < message.length && _isIdentChar(message[j])) {
      j++;
    }
    if (j == start) continue;
    var k = j;
    while (k < message.length && message[k] == ' ') {
      k++;
    }
    if (k < message.length && (message[k] == ',' || message[k] == '}')) {
      out.add(message.substring(start, j));
    }
  }
  return out;
}

bool _isWordChar(String c) => _isIdentChar(c);
bool _isDigit(String c) {
  final code = c.codeUnitAt(0);
  return code >= 48 && code <= 57;
}
bool _isIdentChar(String c) {
  final code = c.codeUnitAt(0);
  return (code >= 48 && code <= 57) || // 0-9
      (code >= 65 && code <= 90) || // A-Z
      (code >= 97 && code <= 122) || // a-z
      code == 95; // _
}

final _icuArgRe = RegExp(r'\{\s*[A-Za-z_][A-Za-z0-9_]*\s*,\s*(plural|select)\s*,');
final _otherBranchRe = RegExp(r'\bother\s*\{');

/// True when the message uses ICU plural/select but has no `other` branch
/// (gen-l10n requires one; without it the message is unreachable for some
/// values).
bool missingOtherBranch(String message) =>
    _icuArgRe.hasMatch(message) && !_otherBranchRe.hasMatch(message);

/// Problems found in one message value (shared with the translator's output
/// validation). Empty list = fine.
List<String> validateMessage({
  required String key,
  required String english,
  required String candidate,
  required String locale,
}) {
  final problems = <String>[];
  if (candidate.trim().isEmpty) {
    problems.add('[$locale] $key: empty value');
    return problems;
  }
  final want = placeholdersOf(english);
  final got = placeholdersOf(candidate);
  if (want.length != got.length || !want.containsAll(got)) {
    final w = (want.toList()..sort()).join(', ');
    final g = (got.toList()..sort()).join(', ');
    problems.add('[$locale] $key: placeholders differ — en {$w} vs {$g}');
  }
  if (missingOtherBranch(candidate)) {
    problems.add('[$locale] $key: ICU plural/select without an `other` branch');
  }
  if (candidate.contains('<parameter') || candidate.contains('```')) {
    problems.add('[$locale] $key: looks like leaked markup');
  }
  return problems;
}

/// Full consistency check across the template, every target locale and the
/// sidecar hash state. Returns human-readable problems; empty = OK.
///
/// Rules:
/// (a) every en key exists in every target; (b) no extra keys in a target;
/// (c) placeholder sets match; (d) ICU plural/select carries `other`;
/// (e) no empty values; (f) sidecar hash == sha256(en value) for every
///     (locale, key) — stale means "run translate.dart"; (g) an en message of
///     ≤2 words must carry `@key.description` (ambiguity guard: "Check",
///     "Call", "Back" are untranslatable without context); (h) `@@locale`
///     matches the map's locale.
List<String> checkArb({
  required Map<String, dynamic> template,
  required Map<String, Map<String, dynamic>> targets,
  required Map<String, Map<String, String>> state,
}) {
  final problems = <String>[];
  final enKeys = messageKeys(template).toList();

  if (template['@@locale'] != kTemplateLocale) {
    problems.add('[en] @@locale must be "$kTemplateLocale"');
  }
  for (final key in enKeys) {
    final value = template[key];
    if (value is! String) {
      problems.add('[en] $key: value must be a string');
      continue;
    }
    final meta = template['@$key'];
    final description =
        meta is Map ? (meta['description'] as String?)?.trim() : null;
    final wordCount =
        value.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    if (wordCount <= 2 && (description == null || description.isEmpty)) {
      problems.add(
          '[en] $key: short message ("$value") needs an @$key.description');
    }
    if (missingOtherBranch(value)) {
      problems.add('[en] $key: ICU plural/select without an `other` branch');
    }
  }

  for (final entry in targets.entries) {
    final locale = entry.key;
    final arb = entry.value;
    if (arb['@@locale'] != locale) {
      problems.add('[$locale] @@locale must be "$locale"');
    }
    final targetKeys = messageKeys(arb).toSet();
    final localeState = state[locale] ?? const {};
    for (final key in enKeys) {
      final english = template[key];
      if (english is! String) continue;
      final candidate = arb[key];
      if (candidate == null) {
        problems.add('[$locale] $key: missing (run tool/l10n/translate.dart)');
        continue;
      }
      if (candidate is! String) {
        problems.add('[$locale] $key: value must be a string');
        continue;
      }
      problems.addAll(validateMessage(
          key: key, english: english, candidate: candidate, locale: locale));
      if (localeState[key] != sourceHash(english)) {
        problems.add(
            '[$locale] $key: translation is stale — English changed since it '
            'was translated (run tool/l10n/translate.dart)');
      }
    }
    for (final extra in targetKeys.difference(enKeys.toSet())) {
      problems.add('[$locale] $extra: not in app_en.arb (remove it)');
    }
  }
  return problems;
}
