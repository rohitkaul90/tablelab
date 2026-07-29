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
import '../models/session_model.dart';
import '../providers/providers.dart';
import 'import_source_screen.dart';

class ImportExportScreen extends ConsumerStatefulWidget {
  const ImportExportScreen({super.key});

  @override
  ConsumerState<ImportExportScreen> createState() =>
      _ImportExportScreenState();
}

class _ImportExportScreenState extends ConsumerState<ImportExportScreen> {
  bool _busy = false;

  /// On Android/iOS, `FilePicker.saveFile` REQUIRES `bytes` and writes the
  /// file itself (Storage Access Framework); on web it triggers a download.
  /// Only desktop returns a plain path for us to write manually.
  static bool get _pluginWritesFile =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  // ─── Export ───────────────────────────────────────────────────────────────

  List<String> get _csvHeaders => [
        'date',
        'game_type',
        'stakes',
        'buy_in',
        'cash_out',
        'prize_won',
        'profit_loss',
        'start_time',
        'end_time',
        'duration_minutes',
        'location',
        'notes',
        'rake_paid',
        'finish_position',
        'total_entrants',
        'table_quality',
      ];

  List<dynamic> _sessionToRow(SessionModel s) => [
        s.date,
        s.gameType,
        s.stakes,
        s.buyIn,
        s.cashOut,
        s.prizeWon ?? '',
        s.profitLoss,
        s.startTime,
        s.endTime,
        s.durationMinutes,
        s.location ?? '',
        s.notes ?? '',
        s.rakePaid ?? '',
        s.finishPosition ?? '',
        s.totalEntrants ?? '',
        s.tableQuality ?? '',
      ];

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
      final rows = [_csvHeaders, ...sessions.map(_sessionToRow)];
      final csv = const ListToCsvConverter().convert(rows);
      final bytes = Uint8List.fromList(utf8.encode(csv));
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Export sessions as CSV',
        fileName:
            'poker_sessions_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
        bytes: bytes,
      );
      if (path != null) {
        if (!_pluginWritesFile) {
          await File(path).writeAsBytes(bytes);
        }
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
      for (int i = 0; i < _csvHeaders.length; i++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
            .value = TextCellValue(_csvHeaders[i]);
      }
      for (int r = 0; r < sessions.length; r++) {
        final row = _sessionToRow(sessions[r]);
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
      final bytes = Uint8List.fromList(encoded);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Export sessions as Excel',
        fileName:
            'poker_sessions_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        bytes: bytes,
      );
      if (path != null) {
        if (!_pluginWritesFile) {
          await File(path).writeAsBytes(bytes);
        }
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
