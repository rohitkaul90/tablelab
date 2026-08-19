import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../equity/card.dart';
import '../providers/pc_ranges_provider.dart';
import '../services/analytics_service.dart';
import '../equity/simulator.dart';
import '../widgets/app_drawer.dart';
import '../widgets/equity/card_picker.dart';
import '../widgets/equity/player_range_editor.dart';
import '../widgets/equity/range_matrix.dart';

class _PlayerState {
  String position;
  Set<int> selectedCells;
  bool isExactHand = false;
  int? card1;
  int? card2;

  _PlayerState({required this.position, required this.selectedCells});

  int get comboCount {
    if (isExactHand) return (card1 != null && card2 != null) ? 1 : 0;
    int total = 0;
    for (final key in selectedCells) {
      total += cellComboCount(key ~/ 13, key % 13);
    }
    return total;
  }

  double get rangePercent => isExactHand ? 0 : comboCount / 1326 * 100;

  List<List<int>> expandCombos(Set<int> excludeCards) {
    if (isExactHand) {
      if (card1 == null || card2 == null) return [];
      if (excludeCards.contains(card1!) || excludeCards.contains(card2!)) return [];
      return [[card1!, card2!]];
    }
    final result = <List<int>>[];
    for (final key in selectedCells) {
      for (final combo in expandCell(key ~/ 13, key % 13, exclude: excludeCards)) {
        result.add([combo.$1, combo.$2]);
      }
    }
    return result;
  }
}

class EquityCalculatorScreen extends ConsumerStatefulWidget {
  final bool showScaffold;
  const EquityCalculatorScreen({super.key, this.showScaffold = true});

  @override
  ConsumerState<EquityCalculatorScreen> createState() =>
      _EquityCalculatorScreenState();
}

class _EquityCalculatorScreenState
    extends ConsumerState<EquityCalculatorScreen> {
  final List<_PlayerState> _players = [];
  final List<int?> _board = List.filled(5, null); // 0-2=flop, 3=turn, 4=river
  SimulationResult? _result;
  bool _running = false;
  String? _errorMsg;
  List<int?> _resultBoard = List.filled(5, null);

  @override
  void initState() {
    super.initState();
    _players.addAll(_defaultPlayers());
    // Warm the PC range library so the preset picker has the weighted-chart
    // presets by the time the range editor opens.
    ref.read(pcRangeLibraryProvider);
  }

  // The calculator opens ready to use: the canonical heads-up pair (positions
  // are cosmetic labels here — they don't affect the equity math) with empty
  // ranges prompting a tap. Avoids the old "add at least 2 players" friction.
  List<_PlayerState> _defaultPlayers() => [
        _PlayerState(position: 'BTN', selectedCells: {}),
        _PlayerState(position: 'BB', selectedCells: {}),
      ];

  Set<String> get _takenPositions => _players.map((p) => p.position).toSet();
  bool get _canCalculate =>
      _players.length >= 2 && _players.every((p) => p.comboCount > 0);

  // True once the user has changed anything away from the fresh default state.
  bool get _isModified =>
      _result != null ||
      _board.any((c) => c != null) ||
      _players.length != 2 ||
      _players.any((p) => p.comboCount > 0 || p.isExactHand);

  void _addPlayer() {
    final available = kPositions.where((p) => !_takenPositions.contains(p)).toList();
    if (available.isEmpty) return;
    setState(() => _players.add(_PlayerState(position: available.first, selectedCells: {})));
    _openRangeEditor(_players.length - 1);
  }

  Set<int> _excludedForPlayer(int idx) {
    final excluded = _board.whereType<int>().toSet();
    for (int i = 0; i < _players.length; i++) {
      if (i == idx) continue;
      final p = _players[i];
      if (p.isExactHand) {
        if (p.card1 != null) excluded.add(p.card1!);
        if (p.card2 != null) excluded.add(p.card2!);
      }
    }
    return excluded;
  }

  void _openRangeEditor(int idx) {
    final p = _players[idx];
    // Pin the preset source for this sheet's lifetime: reading it inside the
    // builder would let the list swap legacy→PC on a mid-sheet rebuild,
    // stranding the dropdown's selected key.
    final pcPresets = ref.read(pcEquityPresetsProvider);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => PlayerRangeEditor(
        // PC weighted-chart presets once loaded; legacy presets meanwhile.
        presets: pcPresets,
        position: p.position,
        selectedCells: p.selectedCells,
        takenPositions: _takenPositions..remove(p.position),
        isExactHand: p.isExactHand,
        card1: p.card1,
        card2: p.card2,
        excludedCards: _excludedForPlayer(idx),
        onSave: (pos, cells, isExact, c1, c2) => setState(() {
          _players[idx].position = pos;
          _players[idx].selectedCells = cells;
          _players[idx].isExactHand = isExact;
          _players[idx].card1 = c1;
          _players[idx].card2 = c2;
          _result = null;
        }),
        onDelete: _players.length > 2
            ? () => setState(() {
                  _players.removeAt(idx);
                  _result = null;
                })
            : null,
      ),
    );
  }

  void _openCardPicker(int boardSlot) {
    final surface = Theme.of(context).colorScheme.surface;
    const shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)));

    if (boardSlot <= 2) {
      // Flop: pick all 3 at once
      final excluded = {_board[3], _board[4]}.whereType<int>().toSet();
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: surface,
        shape: shape,
        builder: (_) => FlopCardPickerSheet(
          excludedCards: excluded,
          currentFlop: [_board[0], _board[1], _board[2]],
          onConfirm: (cards) => setState(() {
            _board[0] = cards[0];
            _board[1] = cards[1];
            _board[2] = cards[2];
            _result = null;
          }),
        ),
      );
    } else {
      // Turn or River: single card
      final excluded = <int>{};
      for (int i = 0; i < 5; i++) {
        if (i != boardSlot && _board[i] != null) excluded.add(_board[i]!);
      }
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: surface,
        shape: shape,
        builder: (_) => CardPickerSheet(
          excludedCards: excluded,
          currentCard: _board[boardSlot],
          onSelected: (idx) => setState(() {
            _board[boardSlot] = idx;
            _result = null;
          }),
        ),
      );
    }
  }

  Future<void> _calculate() async {
    if (!_canCalculate) return;
    setState(() { _running = true; _errorMsg = null; });
    try {
      final boardCards = _board.whereType<int>().toList();
      final boardSet = boardCards.toSet();
      final ranges = <List<List<int>>>[];
      for (int i = 0; i < _players.length; i++) {
        final combos = _players[i].expandCombos(boardSet);
        if (combos.isEmpty) {
          setState(() {
            _errorMsg = '${_players[i].position} has no valid combos given the board.';
            _running = false;
          });
          return;
        }
        ranges.add(combos);
      }
      final result = await runSimulation(ranges: ranges, boardCards: boardCards);
      AnalyticsService.equityCalculatorUsed();
      setState(() { _result = result; _resultBoard = List<int?>.from(_board); _running = false; });
    } catch (e) {
      setState(() { _errorMsg = 'Simulation error: $e'; _running = false; });
    }
  }

  void _clearBoard() => setState(() {
    _board.fillRange(0, 5, null);
    _result = null;
    _errorMsg = null;
  });

  void _reset() => setState(() {
    _players
      ..clear()
      ..addAll(_defaultPlayers());
    _board.fillRange(0, 5, null);
    _result = null;
    _errorMsg = null;
  });

  String _streetLabel(List<int?> board) {
    final n = board.whereType<int>().length;
    if (n == 0) return 'Pre-flop';
    if (n <= 3) return 'Flop';
    if (n == 4) return 'Turn';
    return 'River';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sectionLabel = TextStyle(
      fontSize: 12, fontWeight: FontWeight.bold,
      letterSpacing: 1, color: theme.colorScheme.primary,
    );

    final body = SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Players ─────────────────────────────────────────────────
            Row(
              children: [
                Text('PLAYERS', style: sectionLabel),
                const Spacer(),
                if (_isModified)
                  TextButton.icon(
                    onPressed: _reset,
                    icon: const Icon(Icons.refresh, size: 14),
                    label: const Text('Reset'),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.75),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                if (_players.length < 9)
                  TextButton.icon(
                    onPressed: _addPlayer,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Player'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_players.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    children: [
                      Icon(Icons.people_outline,
                          size: 48, color: Theme.of(context).colorScheme.outline),
                      const SizedBox(height: 8),
                      Text('Add at least 2 players to begin',
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant
                                  .withValues(alpha: 0.75))),
                    ],
                  ),
                ),
              )
            else
              SizedBox(
                height: 150,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _players.length,
                  separatorBuilder: (context, i) => const SizedBox(width: 10),
                  itemBuilder: (context, i) => _PlayerCard(
                    player: _players[i],
                    equity: (_result != null && i < _result!.equity.length)
                        ? _result!.equity[i]
                        : null,
                    color: _playerColors[i % _playerColors.length],
                    onTap: () => _openRangeEditor(i),
                  ),
                ),
              ),

            const SizedBox(height: 20),

            // ── Board ────────────────────────────────────────────────────
            Row(
              children: [
                Text('BOARD', style: sectionLabel),
                const Spacer(),
                if (_board.any((c) => c != null))
                  TextButton.icon(
                    onPressed: _clearBoard,
                    icon: const Icon(Icons.clear, size: 14),
                    label: const Text('Clear Board'),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.75),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            // Each group (flop / turn / river) wrapped in Column so labels
            // sit directly below their cards — no hardcoded pixel offsets.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Flop — all 3 share one label
                Column(
                  children: [
                    Row(
                      children: [
                        BoardCardChip(cardIdx: _board[0], onTap: () => _openCardPicker(0)),
                        const SizedBox(width: 6),
                        BoardCardChip(cardIdx: _board[1], onTap: () => _openCardPicker(1)),
                        const SizedBox(width: 6),
                        BoardCardChip(cardIdx: _board[2], onTap: () => _openCardPicker(2)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('Flop',
                        style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.75))),
                  ],
                ),
                const SizedBox(width: 12),
                // Turn
                Column(
                  children: [
                    BoardCardChip(cardIdx: _board[3], onTap: () => _openCardPicker(3)),
                    const SizedBox(height: 4),
                    Text('Turn',
                        style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.75))),
                  ],
                ),
                const SizedBox(width: 12),
                // River
                Column(
                  children: [
                    BoardCardChip(cardIdx: _board[4], onTap: () => _openCardPicker(4)),
                    const SizedBox(height: 4),
                    Text('River',
                        style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.75))),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ── Calculate ────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _canCalculate && !_running ? _calculate : null,
                icon: _running
                    ? SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.onPrimary),
                      )
                    : const Icon(Icons.calculate),
                label: Text(_running ? 'Calculating…' : 'Calculate Equity'),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),

            if (_errorMsg != null) ...[
              const SizedBox(height: 10),
              Text(_errorMsg!, style: const TextStyle(color: Colors.redAccent)),
            ],

            // ── Results ──────────────────────────────────────────────────
            if (_result != null) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  Text('EQUITY — ${_streetLabel(_resultBoard)}', style: sectionLabel),
                  const Spacer(),
                  Text('${_result!.iterations ~/ 1000}k iterations',
                      style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: 0.75))),
                ],
              ),
              const SizedBox(height: 12),
              for (int i = 0; i < _players.length && i < _result!.equity.length; i++)
                _EquityRow(
                  position: _players[i].position,
                  equity: _result!.equity[i],
                  comboCount: _players[i].comboCount,
                  color: _playerColors[i % _playerColors.length],
                ),
            ],

            const SizedBox(height: 40),
          ],
        ),
    );

    if (!widget.showScaffold) return body;
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('Equity Calculator'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Reset', onPressed: _reset),
        ],
      ),
      body: body,
    );
  }

  static const List<Color> _playerColors = [
    Colors.teal, Colors.orange, Colors.purple, Colors.blue,
    Colors.pink, Colors.green, Colors.amber, Colors.cyan, Colors.deepOrange,
  ];
}

// ── Exact hole card display (2 cards side-by-side in the player card) ─────────

class _HoleCardsDisplay extends StatelessWidget {
  final int card1;
  final int card2;

  const _HoleCardsDisplay({required this.card1, required this.card2});

  Color _suitColor(int s) {
    switch (s) {
      case 0: return Colors.green.shade300;
      case 1: return Colors.blue.shade300;
      case 2: return Colors.red.shade400;
      case 3: return Colors.purple.shade300;
      default: return Colors.white;
    }
  }

  Widget _cardWidget(BuildContext context, int cardIdx) {
    final theme = Theme.of(context);
    final c = _suitColor(cardSuit(cardIdx));
    return Container(
      width: 36, height: 50,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: c, width: 1.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(kRankChars[cardRank(cardIdx)],
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: c)),
          Text(kSuitSymbols[cardSuit(cardIdx)],
              style: TextStyle(fontSize: 11, color: c)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _cardWidget(context, card1),
        const SizedBox(width: 4),
        _cardWidget(context, card2),
      ],
    );
  }
}

// ── Player card on main screen ─────────────────────────────────────────────

class _PlayerCard extends StatelessWidget {
  final _PlayerState player;
  final double? equity;
  final Color color;
  final VoidCallback onTap;

  const _PlayerCard({
    required this.player,
    required this.onTap,
    required this.color,
    this.equity,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasRange = player.comboCount > 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 110,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasRange ? color.withAlpha(120) : theme.colorScheme.outlineVariant,
            width: hasRange ? 1.5 : 1,
          ),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Position chip + edit icon
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withAlpha(50),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    player.position,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
                const Spacer(),
                Icon(Icons.edit,
                    size: 11,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.30)),
              ],
            ),
            const SizedBox(height: 6),
            if (hasRange) ...[
              if (player.isExactHand) ...[
                _HoleCardsDisplay(card1: player.card1!, card2: player.card2!),
              ] else ...[
                MiniRangeMatrix(selectedCells: player.selectedCells),
                const SizedBox(height: 4),
                Text(
                  '${player.comboCount} combos  ${player.rangePercent.toStringAsFixed(1)}%',
                  style: TextStyle(fontSize: 9, color: theme.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
              if (equity != null) ...[
                const SizedBox(height: 4),
                Text(
                  '${(equity! * 100).toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ] else ...[
              const Spacer(),
              Text(
                player.isExactHand ? 'Tap to\nset hand' : 'Tap to\nset range',
                style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.30)),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Equity result row ──────────────────────────────────────────────────────

class _EquityRow extends StatelessWidget {
  final String position;
  final double equity;
  final int comboCount;
  final Color color;

  const _EquityRow({
    required this.position,
    required this.equity,
    required this.comboCount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withAlpha(50), borderRadius: BorderRadius.circular(4)),
                child: Text(position,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
              ),
              const SizedBox(width: 10),
              Text('${(equity * 100).toStringAsFixed(1)}%',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface)),
              const Spacer(),
              Text('$comboCount ${comboCount == 1 ? 'combo' : 'combos'}',
                  style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.75))),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: equity,
              minHeight: 10,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}
