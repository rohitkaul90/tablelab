import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/providers.dart';
import '../services/analytics_service.dart';
import '../utils/save_bytes.dart';
import '../utils/session_export.dart';
import 'import_source_screen.dart';

class ImportExportScreen extends ConsumerStatefulWidget {
  const ImportExportScreen({super.key});

  @override
  ConsumerState<ImportExportScreen> createState() =>
      _ImportExportScreenState();
}

class _ImportExportScreenState extends ConsumerState<ImportExportScreen> {
  bool _busy = false;

  // ─── Export ───────────────────────────────────────────────────────────────
  // Headers + row shape live in lib/utils/session_export.dart (pure,
  // unit-tested); keep importable fields mirrored in the TableLab preset.

  /// Saves [bytes] as a file on every platform. Returns true when saved,
  /// false when the user cancelled the dialog.
  ///
  /// - **Web**: `file_picker` 8.x has NO web `saveFile` (throws
  ///   `UnimplementedError`), so we trigger a browser download directly.
  /// - **Android/iOS**: `saveFile` REQUIRES `bytes` and writes the file
  ///   itself via the Storage Access Framework (the returned path may be a
  ///   content URI — never write to it manually).
  /// - **Desktop**: `saveFile` only shows the dialog and returns a plain
  ///   path; we do the write.
  Future<bool> _saveExportFile({
    required Uint8List bytes,
    required String fileName,
    required String extension,
    required String mimeType,
    required String dialogTitle,
  }) async {
    if (kIsWeb) {
      downloadBytesWeb(bytes, fileName, mimeType);
      return true;
    }
    final path = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: [extension],
      bytes: bytes,
    );
    if (path == null) return false;
    final pluginWroteFile = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    if (!pluginWroteFile) {
      await File(path).writeAsBytes(bytes);
    }
    return true;
  }

  Future<void> _exportCsv() async {
    setState(() => _busy = true);
    try {
      // Exclude any in-progress live session — it has no cash-out yet and
      // would export as a phantom break-even/losing row.
      final sessions = (await ref.read(supabaseServiceProvider).fetchAllSessions())
          .where((s) => !s.isLive)
          .toList();
      if (sessions.isEmpty) {
        _showSnack('No sessions to export.');
        return;
      }
      final rows = [kSessionExportHeaders, ...sessions.map(sessionExportRow)];
      final csv = const ListToCsvConverter().convert(rows);
      // UTF-8 BOM so desktop Excel decodes £/€/₹/accents correctly on a
      // double-click open (BOM-less UTF-8 is read as ANSI and mojibakes).
      final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)]);
      final saved = await _saveExportFile(
        bytes: bytes,
        fileName:
            'poker_sessions_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv',
        extension: 'csv',
        mimeType: 'text/csv',
        dialogTitle: 'Export sessions as CSV',
      );
      if (saved) {
        AnalyticsService.exportTriggered(format: 'csv');
        _showSnack('Exported ${sessions.length} sessions to CSV.');
      }
    } catch (e) {
      _showSnack('Export failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportExcel() async {
    setState(() => _busy = true);
    try {
      // Exclude any in-progress live session (see _exportCsv).
      final sessions = (await ref.read(supabaseServiceProvider).fetchAllSessions())
          .where((s) => !s.isLive)
          .toList();
      if (sessions.isEmpty) {
        _showSnack('No sessions to export.');
        return;
      }
      final excel = Excel.createExcel();
      final sheet = excel['Sessions'];
      excel.setDefaultSheet('Sessions');
      for (int i = 0; i < kSessionExportHeaders.length; i++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
            .value = TextCellValue(kSessionExportHeaders[i]);
      }
      for (int r = 0; r < sessions.length; r++) {
        final row = sessionExportRow(sessions[r]);
        for (int c = 0; c < row.length; c++) {
          final cell = sheet.cell(
              CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1));
          final val = row[c];
          if (val is double) {
            cell.value = DoubleCellValue(val);
          } else if (val is int) {
            cell.value = IntCellValue(val);
          } else {
            cell.value = TextCellValue(val.toString());
          }
        }
      }
      final encoded = excel.encode();
      if (encoded == null) {
        _showSnack('Export failed: could not encode Excel file.');
        return;
      }
      final saved = await _saveExportFile(
        bytes: Uint8List.fromList(encoded),
        fileName:
            'poker_sessions_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx',
        extension: 'xlsx',
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        dialogTitle: 'Export sessions as Excel',
      );
      if (saved) {
        AnalyticsService.exportTriggered(format: 'xlsx');
        _showSnack('Exported ${sessions.length} sessions to Excel.');
      }
    } catch (e) {
      _showSnack('Export failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import / Export')),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.fromLTRB(
                  16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
              children: [
                _SectionHeader(title: 'Export'),
                const SizedBox(height: 8),
                _ActionCard(
                  icon: Icons.table_chart_outlined,
                  title: 'Export to CSV',
                  subtitle:
                      'Save all sessions as a .csv file. Can be opened in Excel, Google Sheets, etc.',
                  onTap: _exportCsv,
                ),
                const SizedBox(height: 8),
                _ActionCard(
                  icon: Icons.grid_on_outlined,
                  title: 'Export to Excel',
                  subtitle: 'Save all sessions as a .xlsx file.',
                  onTap: _exportExcel,
                ),
                const SizedBox(height: 24),
                _SectionHeader(title: 'Import'),
                const SizedBox(height: 8),
                _ActionCard(
                  icon: Icons.upload_file_outlined,
                  title: 'Import Sessions',
                  subtitle:
                      'Import from Poker Income, BankrollMob, PokerTracker 4, and 15 more apps — or any custom CSV / Excel file.',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ImportSourceScreen()),
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 16,
                              color: Theme.of(context).colorScheme.outline),
                          const SizedBox(width: 8),
                          Text('Import Tips',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.outline,
                                  )),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '• Select your source app for automatic column mapping\n'
                        '• Only Date and Buy-in are required — everything else is optional\n'
                        '• If your file has only a Profit column (no Cash-out), cash-out is derived automatically\n'
                        '• Duration accepts minutes, decimal hours, "1h 30m", "1:30", and more\n'
                        '• Duplicate sessions (same date + buy-in + cash-out) are skipped by default',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(title,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.bold));
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
