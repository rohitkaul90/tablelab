// Claude-backed ARB translator. Runs LOCALLY (never in CI) — needs
// ANTHROPIC_API_KEY in the environment.
//
//   dart run tool/l10n/translate.dart                 # translate what's missing/stale
//   dart run tool/l10n/translate.dart --locale es,fr  # only these locales
//   dart run tool/l10n/translate.dart --key navStats  # only these keys (forces)
//   dart run tool/l10n/translate.dart --all           # re-translate everything
//   dart run tool/l10n/translate.dart --dry-run       # show the work, call nothing
//   dart run tool/l10n/translate.dart --record        # no API: record source hashes
//                                                     # for translations a reviewer
//                                                     # hand-added to a target ARB
//
// For each target locale it selects the keys that are absent from
// lib/l10n/app_<locale>.arb OR whose English source changed since they were
// last translated (sha256 recorded per key in lib/l10n/translation_state.json),
// sends them in batches with the locked poker glossary (tool/l10n/glossary.json)
// and the previous translation (so a reviewer's wording survives a partial
// English edit), validates placeholders/ICU on the way back (arb_check.dart),
// and writes the ARB in English key order plus the updated state file.
//
// A hand-edited translation is never overwritten until its English changes:
// reviewers fix wording directly in app_<locale>.arb via a normal PR.
//
// Target locales = the keys of `register` in glossary.json.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'arb_check.dart';
import 'check_arb.dart' show flagValue, loadArbDirectory;

const _endpoint = 'https://api.anthropic.com/v1/messages';
const _defaultModel = 'claude-opus-5-5';
const _batchSize = 60;
const _maxAttempts = 4;

Future<void> main(List<String> args) async {
  final arbDir = flagValue(args, '--arb-dir') ?? 'lib/l10n';
  final model = flagValue(args, '--model') ?? _defaultModel;
  final dryRun = args.contains('--dry-run');
  final recordOnly = args.contains('--record');
  final forceAll = args.contains('--all');
  final onlyKeys = flagValue(args, '--key')?.split(',').toSet();
  final glossary = jsonDecode(_glossaryFile().readAsStringSync())
      as Map<String, dynamic>;
  final register = (glossary['register'] as Map).cast<String, String>();
  final locales =
      flagValue(args, '--locale')?.split(',') ?? register.keys.toList();

  final apiKey = Platform.environment['ANTHROPIC_API_KEY'];
  if (!dryRun && !recordOnly && (apiKey == null || apiKey.isEmpty)) {
    stderr.writeln('translate: ANTHROPIC_API_KEY is not set');
    exit(2);
  }

  final files = loadArbDirectory(Directory(arbDir));
  final template = files.template;
  final enKeys = messageKeys(template).toList();
  final state = {
    for (final e in files.state.entries) e.key: Map<String, String>.of(e.value),
  };

  var totalTranslated = 0;
  for (final locale in locales) {
    if (!register.containsKey(locale)) {
      stderr.writeln('translate: $locale has no `register` entry in glossary.json');
      exit(2);
    }
    final target = Map<String, dynamic>.of(files.targets[locale] ?? {});
    final localeState = state.putIfAbsent(locale, () => {});
    // Drop hashes for keys that no longer exist in app_en.arb so renames and
    // deletions don't leave dead entries behind.
    localeState.removeWhere((k, _) => !template.containsKey(k));

    if (recordOnly) {
      // A reviewer hand-added a translation without an API key: trust it and
      // record the English hash it corresponds to.
      var recorded = 0;
      for (final key in enKeys) {
        if (target.containsKey(key) && localeState[key] == null) {
          localeState[key] = sourceHash(template[key] as String);
          recorded++;
        }
      }
      stdout.writeln('[$locale] recorded $recorded hand-added translation(s)');
      continue;
    }

    final pending = <String>[];
    for (final key in enKeys) {
      final english = template[key] as String;
      final stale = localeState[key] != sourceHash(english);
      final missing = !target.containsKey(key);
      final forced = forceAll || (onlyKeys?.contains(key) ?? false);
      if (onlyKeys != null && !onlyKeys.contains(key)) continue;
      if (missing || stale || forced) pending.add(key);
    }
    stdout.writeln('[$locale] ${pending.length} key(s) to translate'
        '${pending.isEmpty ? '' : ': ${pending.take(8).join(', ')}${pending.length > 8 ? ', …' : ''}'}');
    if (pending.isEmpty || dryRun) continue;

    final translated = <String, String>{};
    var batchKeys = pending;
    for (var round = 0; round < 2 && batchKeys.isNotEmpty; round++) {
      final failed = <String>[];
      for (var i = 0; i < batchKeys.length; i += _batchSize) {
        final slice = batchKeys.sublist(
            i, i + _batchSize > batchKeys.length ? batchKeys.length : i + _batchSize);
        final result = await _translateBatch(
          apiKey: apiKey!,
          model: model,
          locale: locale,
          register: register[locale]!,
          glossary: glossary,
          template: template,
          target: target,
          keys: slice,
        );
        for (final key in slice) {
          final candidate = result[key];
          final problems = candidate == null
              ? ['[$locale] $key: not returned']
              : validateMessage(
                  key: key,
                  english: template[key] as String,
                  candidate: candidate,
                  locale: locale);
          if (problems.isEmpty) {
            translated[key] = candidate!;
          } else {
            problems.forEach(stderr.writeln);
            failed.add(key);
          }
        }
      }
      batchKeys = failed; // one retry round for anything that failed validation
    }
    if (batchKeys.isNotEmpty) {
      stderr.writeln('[$locale] gave up on: ${batchKeys.join(', ')}');
    }

    for (final e in translated.entries) {
      target[e.key] = e.value;
      localeState[e.key] = sourceHash(template[e.key] as String);
    }
    totalTranslated += translated.length;
    _writeArb(File('$arbDir/app_$locale.arb'), locale, enKeys, target);
    stdout.writeln('[$locale] wrote ${translated.length} translation(s)');
  }

  if (!dryRun) {
    _writeState(File('$arbDir/$kStateFileName'), state);
    stdout.writeln('translate: $totalTranslated translation(s) written; '
        'now run `dart run tool/l10n/check_arb.dart` and `flutter gen-l10n`');
  }
}

/// glossary.json lives beside this script, wherever the script is run from.
File _glossaryFile() {
  final beside = File.fromUri(Platform.script.resolve('glossary.json'));
  if (beside.existsSync()) return beside;
  return File('tool/l10n/glossary.json');
}

Future<Map<String, String>> _translateBatch({
  required String apiKey,
  required String model,
  required String locale,
  required String register,
  required Map<String, dynamic> glossary,
  required Map<String, dynamic> template,
  required Map<String, dynamic> target,
  required List<String> keys,
}) async {
  final items = [
    for (final key in keys)
      {
        'key': key,
        'source': template[key],
        if (template['@$key'] is Map &&
            (template['@$key'] as Map)['description'] != null)
          'description': (template['@$key'] as Map)['description'],
        if (target[key] != null) 'previousTranslation': target[key],
      },
  ];
  final schema = {
    'type': 'object',
    'properties': {for (final k in keys) k: {'type': 'string'}},
    'required': keys,
    'additionalProperties': false,
  };
  final body = {
    'model': model,
    'max_tokens': 16000,
    'fallbacks': 'default',
    'system': _systemPrompt(locale, register, glossary),
    'messages': [
      {
        'role': 'user',
        'content': 'Translate these UI strings. Return a JSON object mapping '
            'each key to its translation.\n\n${jsonEncode(items)}',
      },
    ],
    'output_config': {
      'effort': 'medium',
      'format': {'type': 'json_schema', 'schema': schema},
    },
  };

  for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
    final res = await http.post(
      Uri.parse(_endpoint),
      headers: {
        'content-type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'anthropic-beta': 'server-side-fallback-2026-07-01',
      },
      body: jsonEncode(body),
    );
    if (res.statusCode == 429 || res.statusCode >= 500) {
      final wait = Duration(seconds: 2 << attempt);
      stderr.writeln('[$locale] HTTP ${res.statusCode}, retrying in ${wait.inSeconds}s');
      await Future<void>.delayed(wait);
      continue;
    }
    if (res.statusCode != 200) {
      throw StateError('[$locale] HTTP ${res.statusCode}: ${res.body}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final stop = json['stop_reason'];
    if (stop != 'end_turn') {
      throw StateError('[$locale] unexpected stop_reason $stop: ${res.body}');
    }
    final text = (json['content'] as List)
        .cast<Map<String, dynamic>>()
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'] as String)
        .join();
    final usage = json['usage'] as Map<String, dynamic>?;
    stdout.writeln('[$locale] batch of ${keys.length}: '
        '${usage?['input_tokens']} in / ${usage?['output_tokens']} out tokens');
    return (jsonDecode(text) as Map<String, dynamic>).cast<String, String>();
  }
  throw StateError('[$locale] gave up after $_maxAttempts attempts');
}

String _systemPrompt(
    String locale, String register, Map<String, dynamic> glossary) {
  final keep = (glossary['keepInEnglish'] as List).cast<String>();
  final terms = (glossary['terms'] as Map).cast<String, dynamic>();
  final pinned = [
    for (final e in terms.entries)
      if ((e.value as Map)[locale] != null) '${e.key} → ${(e.value as Map)[locale]}',
  ];
  // A locale may override the default previousTranslation rule (glossary
  // `previousTranslationRule`): es_419 is seeded from the European Spanish
  // ARB and must ADAPT it, not preserve it.
  final prevRule =
      ((glossary['previousTranslationRule'] as Map?)?[locale] as String?) ??
          '`previousTranslation`, when present, was reviewed by a native '
              'speaker: keep its wording and change only what the new English '
              'requires.';
  final language = const {
        'es': 'Spanish',
        'fr': 'French',
        'it': 'Italian',
        'nl': 'Dutch',
        'ja': 'Japanese',
        'ko': 'Korean',
        'zh': 'Traditional Chinese (Taiwan)',
        'es_419': 'Latin American Spanish',
      }[locale] ??
      locale;
  return '''
You localize the user interface of TableLab, a poker bankroll tracker and hand-coaching app used by live and online players, into $language.

Register: $register. Write the way a native poker player would speak to a peer; natural, concise, never literal word-for-word.

Rules:
- Each source string is an ICU message. Preserve every placeholder exactly ({name}, {count, plural, one{...} other{...}}, {type, select, ...}): same names, same structure, translated text only inside the branches.
- Keep the translation within about 130% of the English length; these render in buttons, tabs and table cells.
- Keep capitalisation style: an ALL-CAPS source stays ALL CAPS; a Title Case button stays short.
- No quotes, no markdown, no explanations, no trailing full stops the source doesn't have.
- $prevRule
- Keep these poker terms in English, untranslated: ${keep.join(', ')}.
- Use exactly these renderings for these words: ${pinned.join('; ')}.
''';
}

void _writeArb(File file, String locale, List<String> enOrder,
    Map<String, dynamic> target) {
  final ordered = <String, dynamic>{'@@locale': locale};
  for (final key in enOrder) {
    if (target.containsKey(key)) ordered[key] = target[key];
  }
  file.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(ordered)}\n');
}

void _writeState(File file, Map<String, Map<String, String>> state) {
  final sortedLocales = state.keys.toList()..sort();
  final out = <String, dynamic>{
    for (final l in sortedLocales)
      l: {
        for (final k in (state[l]!.keys.toList()..sort())) k: state[l]![k],
      },
  };
  file.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(out)}\n');
}
