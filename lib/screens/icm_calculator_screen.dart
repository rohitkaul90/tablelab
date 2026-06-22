import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../widgets/app_drawer.dart';
import '../services/analytics_service.dart';

class _ThousandsFormatter extends TextInputFormatter {
  static final _fmt = NumberFormat('#,###', 'en_US');

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final stripped = newValue.text.replaceAll(',', '');
    if (stripped.isEmpty) return newValue.copyWith(text: '');
    final n = int.tryParse(stripped);
    if (n == null) return oldValue;
    final formatted = _fmt.format(n);
    return newValue.copyWith(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class IcmCalculatorScreen extends StatefulWidget {
  final bool showScaffold;
  const IcmCalculatorScreen({super.key, this.showScaffold = true});

  @override
  State<IcmCalculatorScreen> createState() => _IcmCalculatorScreenState();
}

// ─── Entry models ────────────────────────────────────────────────────────────

class _PlayerEntry {
  final TextEditingController name = TextEditingController();
  final TextEditingController chips = TextEditingController();
  void dispose() {
    name.dispose();
    chips.dispose();
  }
}

class _IcmResult {
  final String name;
  final double chips;
  final double chipPct;
  final double icm;
  final double chipChop;

  const _IcmResult({
    required this.name,
    required this.chips,
    required this.chipPct,
    required this.icm,
    required this.chipChop,
  });

  double get diff => icm - chipChop;
}

// ─── Screen state ─────────────────────────────────────────────────────────────

class _IcmCalculatorScreenState extends State<IcmCalculatorScreen> {
  final List<_PlayerEntry> _players = [];
  final List<TextEditingController> _payouts = [];
  List<_IcmResult>? _results;
  String? _error;

  static final _currFmt = NumberFormat('#,##0', 'en_US');
  static final _chipFmt = NumberFormat('#,##0', 'en_US');

  @override
  void initState() {
    super.initState();
    // Start with 3 players and 3 payouts as a sensible default
    for (int i = 0; i < 3; i++) { _addPlayer(); }
    for (int i = 0; i < 3; i++) { _addPayout(); }
  }

  @override
  void dispose() {
    for (final p in _players) { p.dispose(); }
    for (final c in _payouts) { c.dispose(); }
    super.dispose();
  }

  void _addPlayer() {
    if (_players.length >= 9) return;
    setState(() {
      _players.add(_PlayerEntry());
      _results = null;
    });
  }

  void _removePlayer(int i) {
    if (_players.length <= 2) return;
    setState(() {
      _players[i].dispose();
      _players.removeAt(i);
      _results = null;
    });
  }

  void _addPayout() {
    if (_payouts.length >= 9) return;
    setState(() {
      _payouts.add(TextEditingController());
      _results = null;
    });
  }

  void _removePayout(int i) {
    if (_payouts.length <= 2) return;
    setState(() {
      _payouts[i].dispose();
      _payouts.removeAt(i);
      _results = null;
    });
  }

  void _calculate() {
    setState(() => _error = null);

    // Parse chips
    final chips = <double>[];
    final names = <String>[];
    for (int i = 0; i < _players.length; i++) {
      final raw = _players[i].chips.text.trim().replaceAll(',', '');
      final v = double.tryParse(raw);
      if (v == null || v <= 0) {
        setState(() => _error = 'Player ${i + 1}: enter a valid chip count.');
        return;
      }
      chips.add(v);
      final n = _players[i].name.text.trim();
      names.add(n.isEmpty ? 'Player ${i + 1}' : n);
    }

    // Parse payouts
    final payouts = <double>[];
    for (int i = 0; i < _payouts.length; i++) {
      final raw = _payouts[i].text.trim().replaceAll(',', '').replaceAll('\$', '');
      final v = double.tryParse(raw);
      if (v == null || v < 0) {
        setState(() => _error = '${_placeLabel(i + 1)}: enter a valid prize amount.');
        return;
      }
      payouts.add(v);
    }

    if (payouts.isEmpty || payouts.every((p) => p == 0)) {
      setState(() => _error = 'Enter at least one prize amount.');
      return;
    }

    if (payouts.length != _players.length) {
      setState(() => _error =
          'Number of prize places (${payouts.length}) must equal number of players (${_players.length}).');
      return;
    }

    final icmValues = _computeIcm(chips, payouts);
    final chipChopValues = _computeChipChop(chips, payouts);
    final totalChips = chips.reduce((a, b) => a + b);

    final results = <_IcmResult>[];
    for (int i = 0; i < chips.length; i++) {
      results.add(_IcmResult(
        name: names[i],
        chips: chips[i],
        chipPct: chips[i] / totalChips * 100,
        icm: icmValues[i],
        chipChop: chipChopValues[i],
      ));
    }
    // Sort by ICM equity descending
    results.sort((a, b) => b.icm.compareTo(a.icm));

    AnalyticsService.icmCalculatorUsed();
    setState(() => _results = results);
  }

  // ── ICM algorithm (Malmuth-Harville, bitmask memoisation) ───────────────────

  List<double> _computeIcm(List<double> chips, List<double> payouts) {
    final n = chips.length;
    final p = math.min(n, payouts.length);
    final effPayouts = payouts.take(p).toList();
    final memo = <int, List<double>>{};

    List<double> solve(int mask, int place) {
      if (place >= effPayouts.length) return List.filled(n, 0.0);
      final key = mask * (effPayouts.length + 1) + place;
      if (memo.containsKey(key)) return memo[key]!;

      final result = List.filled(n, 0.0);
      double totalChips = 0;
      for (int i = 0; i < n; i++) {
        if ((mask >> i) & 1 == 1) totalChips += chips[i];
      }
      if (totalChips <= 0) {
        memo[key] = result;
        return result;
      }

      for (int w = 0; w < n; w++) {
        if ((mask >> w) & 1 == 0) continue;
        final pWin = chips[w] / totalChips;
        result[w] += pWin * effPayouts[place];
        final nextMask = mask & ~(1 << w);
        final sub = solve(nextMask, place + 1);
        for (int i = 0; i < n; i++) {
          if (i != w && (mask >> i) & 1 == 1) {
            result[i] += pWin * sub[i];
          }
        }
      }

      memo[key] = result;
      return result;
    }

    return solve((1 << n) - 1, 0);
  }

  List<double> _computeChipChop(List<double> chips, List<double> payouts) {
    final totalChips = chips.reduce((a, b) => a + b);
    final totalPrize = payouts.reduce((a, b) => a + b);
    if (totalChips <= 0) return List.filled(chips.length, 0.0);
    return chips.map((c) => c / totalChips * totalPrize).toList();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  static String _placeLabel(int n) {
    const suffixes = ['st', 'nd', 'rd'];
    final suffix = n <= 3 ? suffixes[n - 1] : 'th';
    return '$n$suffix';
  }

  String _fmtMoney(double v) => '\$${_currFmt.format(v.round())}';
  String _fmtChips(double v) => _chipFmt.format(v.round());

  void _shareResults() {
    final results = _results;
    if (results == null) return;
    final totalPrize = results.fold(0.0, (s, r) => s + r.icm);
    final lines = [
      'ICM Deal (${results.length} players):',
      for (final r in results)
        '${r.name} — ${_fmtChips(r.chips)} chips (${r.chipPct.toStringAsFixed(1)}%) → ${_fmtMoney(r.icm)}',
      '',
      'Total prize pool: ${_fmtMoney(totalPrize)}',
      'Calculated with TableLab',
    ];
    SharePlus.instance.share(ShareParams(text: lines.join('\n')));
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = SafeArea(
      top: false,
        child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // ── Players ───────────────────────────────────────────────────────
          _sectionHeader(context, 'Players', '${_players.length}/9'),
          const SizedBox(height: 4),
          Text(
            'Enter each remaining player\'s chip count.',
            style: TextStyle(
                fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          ...List.generate(_players.length, (i) => _playerRow(i, theme)),
          if (_players.length < 9)
            TextButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Player'),
              onPressed: _addPlayer,
            ),

          const SizedBox(height: 24),

          // ── Payouts ───────────────────────────────────────────────────────
          _sectionHeader(context, 'Prize Pool', '${_payouts.length} places'),
          const SizedBox(height: 4),
          Text(
            'Enter the prize for each remaining place.',
            style: TextStyle(
                fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          ...List.generate(_payouts.length, (i) => _payoutRow(i, theme)),
          if (_payouts.length < 9)
            TextButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Place'),
              onPressed: _addPayout,
            ),

          const SizedBox(height: 24),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: TextStyle(
                    color: theme.colorScheme.error, fontSize: 13),
              ),
            ),

          FilledButton(
            onPressed: _calculate,
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52)),
            child: const Text('Calculate Deal',
                style: TextStyle(fontSize: 16)),
          ),

          // ── Results ───────────────────────────────────────────────────────
          if (_results != null) ...[
            const SizedBox(height: 28),
            _sectionHeader(context, 'Deal Results', null),
            const SizedBox(height: 4),
            Text(
              'Total prize pool: ${_fmtMoney(_results!.fold(0.0, (s, r) => s + r.icm))}',
              style: TextStyle(
                  fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),

            // Column headers
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  const Expanded(flex: 3, child: SizedBox()),
                  _colHeader(context, 'ICM Deal'),
                  _colHeader(context, 'Chip-Chop'),
                  _colHeader(context, 'Diff'),
                ],
              ),
            ),
            const Divider(height: 1),
            ...(_results!.map((r) => _resultRow(r, context))),
            const SizedBox(height: 20),
            _icmExplainer(theme),
          ],
        ],
      ),
      );

    if (!widget.showScaffold) return body;
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('ICM Deal Calculator'),
        actions: [
          if (_results != null)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share deal',
              onPressed: _shareResults,
            ),
        ],
      ),
      body: body,
    );
  }

  Widget _playerRow(int i, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Container(
          width: 28,
          alignment: Alignment.center,
          child: Text(
            '${i + 1}',
            style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          flex: 3,
          child: TextField(
            controller: _players[i].name,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Player ${i + 1}',
              border: const OutlineInputBorder(),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            onChanged: (_) => setState(() => _results = null),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 3,
          child: TextField(
            controller: _players[i].chips,
            keyboardType: TextInputType.number,
            inputFormatters: [_ThousandsFormatter()],
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Chips',
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            ),
            onChanged: (_) => setState(() => _results = null),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline, size: 18),
          onPressed: _players.length > 2 ? () => _removePlayer(i) : null,
          color:
              theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ]),
    );
  }

  Widget _payoutRow(int i, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        SizedBox(
          width: 36,
          child: Text(
            _placeLabel(i + 1),
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: TextField(
            controller: _payouts[i],
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
            ],
            decoration: const InputDecoration(
              isDense: true,
              prefixText: '\$',
              hintText: '0',
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            onChanged: (_) => setState(() => _results = null),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline, size: 18),
          onPressed: _payouts.length > 2 ? () => _removePayout(i) : null,
          color:
              theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ]),
    );
  }

  Widget _resultRow(_IcmResult r, BuildContext context) {
    final diffColor = r.diff >= 0 ? Colors.green : Colors.red;
    final diffSign = r.diff >= 0 ? '+' : '';
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
              color: Theme.of(context).colorScheme.outline.withAlpha(30)),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Row(children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r.name,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis),
              Text(
                '${_fmtChips(r.chips)} chips · ${r.chipPct.toStringAsFixed(1)}%',
                style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.75)),
              ),
            ],
          ),
        ),
        _resultCell(
          _fmtMoney(r.icm),
          color: Theme.of(context).colorScheme.primary,
          bold: true,
        ),
        _resultCell(_fmtMoney(r.chipChop)),
        _resultCell('$diffSign${_fmtMoney(r.diff)}', color: diffColor),
      ]),
    );
  }

  Widget _resultCell(String text, {Color? color, bool bold = false}) =>
      Expanded(
        flex: 2,
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            color: color,
          ),
          textAlign: TextAlign.right,
          overflow: TextOverflow.ellipsis,
        ),
      );

  Widget _colHeader(BuildContext context, String label) => Expanded(
        flex: 2,
        child: Text(
          label,
          style: TextStyle(
              fontSize: 10,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.75)),
          textAlign: TextAlign.right,
        ),
      );

  Widget _sectionHeader(
          BuildContext context, String title, String? badge) =>
      Row(
        children: [
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          if (badge != null) ...[
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outline.withAlpha(40),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(badge,
                  style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.75))),
            ),
          ],
        ],
      );

  Widget _icmExplainer(ThemeData theme) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: theme.colorScheme.outline.withAlpha(40)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('About ICM vs Chip-Chop',
                style: theme.textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              'ICM (Independent Chip Model) accounts for the payout structure — '
              'short stacks receive more than their chip % suggests because their '
              'elimination risk is higher. Chip-chop ignores payout jumps and '
              'splits the prize pool in direct proportion to chip counts. '
              'The "Diff" column shows how much each player gains or loses '
              'under ICM vs a pure chip-chop.',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant, height: 1.55),
            ),
          ],
        ),
      );
}
