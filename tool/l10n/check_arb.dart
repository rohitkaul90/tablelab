// CI gate for the ARB files (runs in ci.yml before `flutter analyze`).
//
//   dart run tool/l10n/check_arb.dart [--arb-dir lib/l10n]
//
// gen-l10n itself only PRINTS untranslated messages, so this is the hard check:
// every locale must carry every English key, placeholders must match, ICU
// plural/select needs `other`, short English strings need a description, and
// every translation's recorded source hash must match the current English text
// (stale = someone edited app_en.arb without re-running translate.dart).
// Rules live in arb_check.dart (unit-tested).
import 'dart:convert';
import 'dart:io';

import 'arb_check.dart';

Future<void> main(List<String> args) async {
  final arbDir = _flag(args, '--arb-dir') ?? 'lib/l10n';
  final files = loadArbDirectory(Directory(arbDir));
  final problems = checkArb(
    template: files.template,
    targets: files.targets,
    state: files.state,
  );
  if (problems.isEmpty) {
    stdout.writeln(
        'check_arb: OK — ${messageKeys(files.template).length} keys × '
        '${files.targets.length} locale(s) (${files.targets.keys.join(', ')})');
    return;
  }
  for (final p in problems) {
    stderr.writeln('check_arb: $p');
  }
  stderr.writeln('check_arb: ${problems.length} problem(s)');
  exitCode = 1;
}

String? _flag(List<String> args, String name) {
  final i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}

/// The template, every `app_<locale>.arb` beside it, and the sidecar state.
class ArbFiles {
  ArbFiles(this.template, this.targets, this.state);
  final Map<String, dynamic> template;
  final Map<String, Map<String, dynamic>> targets;
  final Map<String, Map<String, String>> state;
}

const kStateFileName = 'translation_state.json';

ArbFiles loadArbDirectory(Directory dir) {
  final templateFile = File('${dir.path}/app_$kTemplateLocale.arb');
  if (!templateFile.existsSync()) {
    stderr.writeln('check_arb: ${templateFile.path} not found');
    exit(2);
  }
  final template = _readJson(templateFile);
  final targets = <String, Map<String, dynamic>>{};
  final re = RegExp(r'^app_([a-z]{2,3}(?:_[A-Za-z]{2,4})*)\.arb$');
  for (final f in dir.listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    final m = re.firstMatch(name);
    if (m == null || m.group(1) == kTemplateLocale) continue;
    targets[m.group(1)!] = _readJson(f);
  }
  final stateFile = File('${dir.path}/$kStateFileName');
  final state = <String, Map<String, String>>{};
  if (stateFile.existsSync()) {
    final raw = _readJson(stateFile);
    for (final e in raw.entries) {
      state[e.key] = (e.value as Map).cast<String, String>();
    }
  }
  return ArbFiles(template, targets, state);
}

Map<String, dynamic> _readJson(File f) =>
    jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
