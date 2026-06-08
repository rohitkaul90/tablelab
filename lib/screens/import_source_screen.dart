import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'import_mapping_screen.dart';

// ─── Source app data ──────────────────────────────────────────────────────────

class _AppSource {
  final String? presetId; // null = generic / no preset
  final String name;
  final String platform;

  const _AppSource(this.presetId, this.name, this.platform);
}

const _mobileApps = <_AppSource>[
  _AppSource('poker_income',           'Poker Income',           'iOS · Android'),
  _AppSource('bankrollmob',            'BankrollMob',            'Web'),
  _AppSource('simply_poker',           'Simply Poker',           'iOS'),
  _AppSource('poker_analytics',        'Poker Analytics',        'iOS · Android'),
  _AppSource('poker_journal',          'Poker Journal',          'iOS · Android'),
  _AppSource('pokerbase',              'PokerBase',              'iOS · Android · Web'),
  _AppSource('splendid_poker',         'Splendid Poker',         'iOS'),
  _AppSource('my_poker_log',           'My Poker Log',           'Web · iOS'),
  _AppSource('poker_sessions',         'Poker Sessions',         'iOS'),
  _AppSource('poker_bankroll_tracker', 'Poker Bankroll Tracker', 'iOS · Android · Web'),
];

const _hudSoftware = <_AppSource>[
  _AppSource('pokertracker',  'PokerTracker 4',      'Windows · Mac'),
  _AppSource('hm3',           "Hold'em Manager 3",   'Windows · Mac'),
  _AppSource('hand2note',     'Hand2Note',           'Windows · Mac'),
  _AppSource('drivehud',      'DriveHUD',            'Windows · Mac'),
  _AppSource('poker_copilot', 'Poker Copilot',       'Mac · Windows'),
];

const _tournamentDbs = <_AppSource>[
  _AppSource('sharkscope',         'Sharkscope',         'Web — Gold subscription required'),
  _AppSource('pokerstars_history', 'PokerStars History', 'Tournament history export'),
];

// ─── Screen ───────────────────────────────────────────────────────────────────

class ImportSourceScreen extends StatefulWidget {
  const ImportSourceScreen({super.key});

  @override
  State<ImportSourceScreen> createState() => _ImportSourceScreenState();
}

class _ImportSourceScreenState extends State<ImportSourceScreen> {
  bool _busy = false;

  // ─── Source selection ───────────────────────────────────────────────────

  Future<void> _onSourceSelected(String? presetId) async {
    // Open file picker first; set busy only during parsing.
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx', 'xls'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    setState(() => _busy = true);
    try {
      final file = result.files.first;
      final parsed = await _parseFile(file);
      if (parsed == null) return; // user cancelled sheet selection

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ImportMappingScreen(
            fileHeaders: parsed.$1,
            rows: parsed.$2,
            initialPresetId: presetId,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not read file: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ─── File parsing ────────────────────────────────────────────────────────

  Future<(List<String>, List<List<dynamic>>)?> _parseFile(
      PlatformFile file) async {
    final ext = (file.extension ?? '').toLowerCase();
    List<String> headers;
    List<List<dynamic>> rows;

    if (ext == 'csv') {
      var content = String.fromCharCodes(file.bytes!);
      if (content.startsWith('﻿')) content = content.substring(1);
      final delimiter = _detectDelimiter(content);
      final all = CsvToListConverter(
        fieldDelimiter: delimiter,
        eol: '\n',
      ).convert(content);
      if (all.isEmpty) throw Exception('File is empty.');
      // Poker Bankroll Tracker prefixes with "—PBT Bankroll Export—"
      final skipMeta = all.length > 1 &&
          all[0].length == 1 &&
          all[0][0].toString().contains('PBT Bankroll Export');
      final headerRow = skipMeta ? all[1] : all[0];
      headers = headerRow.map((e) => e.toString().trim()).toList();
      rows = all.skip(skipMeta ? 2 : 1).where((r) => r.isNotEmpty).toList();
    } else if (ext == 'xlsx' || ext == 'xls') {
      Excel excel;
      try {
        excel = Excel.decodeBytes(file.bytes!);
      } catch (e) {
        if (e.toString().contains('numFmtId') ||
            e.toString().contains('numfmt')) {
          final patched = _patchExcelNumFmt(file.bytes!);
          excel = Excel.decodeBytes(patched);
        } else {
          rethrow;
        }
      }
      final sheetNames = excel.tables.keys.toList();
      if (sheetNames.isEmpty) throw Exception('No sheets found.');

      String sheetName;
      if (sheetNames.length == 1) {
        sheetName = sheetNames.first;
      } else {
        if (!mounted) return null;
        final picked = await _pickSheet(sheetNames);
        if (picked == null) return null;
        sheetName = picked;
      }
      final sheet = excel.tables[sheetName]!;
      final allRows = sheet.rows;
      if (allRows.isEmpty) throw Exception('Sheet is empty.');
      headers = allRows.first
          .map((c) => _cellStr(c?.value).trim())
          .toList();
      rows = allRows
          .skip(1)
          .map((r) => r.map((c) => _cellStr(c?.value)).toList())
          .where((r) => r.any((c) => c.isNotEmpty))
          .toList();
    } else {
      throw Exception('Unsupported file type: $ext');
    }

    // Drop fully empty header columns (keep row data in sync)
    final nonEmpty = <int>[];
    for (int i = 0; i < headers.length; i++) {
      if (headers[i].isNotEmpty) nonEmpty.add(i);
    }
    headers = [for (final i in nonEmpty) headers[i]];
    rows = rows
        .map((r) => [for (final i in nonEmpty) i < r.length ? r[i] : ''])
        .where((r) => r.any((c) => c.isNotEmpty))
        .toList();

    if (headers.isEmpty) throw Exception('No headers found.');
    if (rows.isEmpty) throw Exception('No data rows found.');
    return (headers, rows);
  }

  String _cellStr(CellValue? value) => value == null ? '' : value.toString();

  String _detectDelimiter(String content) {
    final sample = content.split('\n').take(5).join('\n');
    final commas = ','.allMatches(sample).length;
    final semicolons = ';'.allMatches(sample).length;
    final tabs = '\t'.allMatches(sample).length;
    if (semicolons > commas && semicolons > tabs) return ';';
    if (tabs > commas && tabs > semicolons) return '\t';
    return ',';
  }

  Future<String?> _pickSheet(List<String> names) => showDialog<String>(
        context: context,
        builder: (_) => SimpleDialog(
          title: const Text('Select sheet'),
          children: names
              .map((n) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, n),
                    child: Text(n),
                  ))
              .toList(),
        ),
      );

  Uint8List _patchExcelNumFmt(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final stylesFile = archive.findFile('xl/styles.xml');
      if (stylesFile == null) return bytes;
      var xml = utf8.decode(stylesFile.content as List<int>);
      xml = xml.replaceAllMapped(
        RegExp(r'<numFmt\s[^>]*numFmtId="(\d+)"[^>]*/?>(?:</numFmt>)?',
            caseSensitive: false),
        (m) {
          final id = int.tryParse(m.group(1) ?? '999') ?? 999;
          return id < 164 ? '' : m.group(0)!;
        },
      );
      final patchedBytes = utf8.encode(xml);
      final newArchive = Archive();
      for (final f in archive) {
        newArchive.addFile(f.name == 'xl/styles.xml'
            ? ArchiveFile('xl/styles.xml', patchedBytes.length, patchedBytes)
            : f);
      }
      final encoded = ZipEncoder().encode(newArchive);
      return encoded != null ? Uint8List.fromList(encoded) : bytes;
    } catch (_) {
      return bytes;
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import Sessions')),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Where are you importing from?',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Select your app and we\'ll pick the right column mapping automatically.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                    const SizedBox(height: 24),

                    _SectionHeader('Mobile & Web Apps'),
                    const SizedBox(height: 8),
                    _AppGroup(
                      sources: _mobileApps,
                      color: const Color(0xFF2E7D32),
                      onTap: _onSourceSelected,
                    ),
                    const SizedBox(height: 20),

                    _SectionHeader('Desktop HUD Software'),
                    const SizedBox(height: 4),
                    Text(
                      'These apps export profit (not cash-out). Cash-out is derived automatically.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                    const SizedBox(height: 8),
                    _AppGroup(
                      sources: _hudSoftware,
                      color: const Color(0xFF1565C0),
                      onTap: _onSourceSelected,
                    ),
                    const SizedBox(height: 20),

                    _SectionHeader('Tournament Databases'),
                    const SizedBox(height: 8),
                    _AppGroup(
                      sources: _tournamentDbs,
                      color: const Color(0xFFBF360C),
                      onTap: _onSourceSelected,
                    ),
                    const SizedBox(height: 20),

                    _SectionHeader('Other'),
                    const SizedBox(height: 8),
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              Theme.of(context).colorScheme.surfaceContainerHigh,
                          child: Icon(Icons.table_chart_outlined,
                              size: 20,
                              color: Theme.of(context).colorScheme.outline),
                        ),
                        title: const Text('Generic CSV / Excel'),
                        subtitle: const Text(
                            "Any spreadsheet — you'll map columns manually"),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _onSourceSelected(null),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
    );
  }
}

// ─── Section widgets ──────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      );
}

class _AppGroup extends StatelessWidget {
  final List<_AppSource> sources;
  final Color color;
  final void Function(String?) onTap;

  const _AppGroup({
    required this.sources,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          for (int i = 0; i < sources.length; i++) ...[
            ListTile(
              leading: CircleAvatar(
                backgroundColor: color,
                radius: 18,
                child: Text(
                  sources[i].name[0],
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              title: Text(sources[i].name),
              subtitle: Text(
                sources[i].platform,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onTap(sources[i].presetId),
            ),
            if (i < sources.length - 1)
              const Divider(height: 1, indent: 72, endIndent: 0),
          ],
        ],
      ),
    );
  }
}
