import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/hand_model.dart';
import '../../providers/pc_ranges_provider.dart';
import '../../providers/providers.dart';
import '../../services/analytics_service.dart';
import '../../utils/helpers.dart';
import '../../utils/quick_hand_synthesis.dart';
import '../../widgets/hand_card_picker.dart';
import '../../widgets/playing_card_widget.dart';
import '../../widgets/session_picker_tile.dart';
import 'hand_input_screen.dart';

/// Quick Hand mode: capture the one decision that mattered in ~30 seconds —
/// hero cards, position, stakes, the spot, the action, the result. The
/// surrounding hand structure is synthesized (see quick_hand_synthesis.dart);
/// the full street-by-street wizard remains available via "Full mode".
class QuickHandScreen extends ConsumerStatefulWidget {
  final String? prefilledSessionId;
  final String? prefilledStakes;
  final String? prefilledSessionLabel;
  final bool isTournamentSession;

  const QuickHandScreen({
    super.key,
    this.prefilledSessionId,
    this.prefilledStakes,
    this.prefilledSessionLabel,
    this.isTournamentSession = false,
  });

  @override
  ConsumerState<QuickHandScreen> createState() => QuickHandScreenState();
}

class QuickHandScreenState extends ConsumerState<QuickHandScreen> {
  bool _isTournament = false;
  String _selectedStakes = '1/2';
  bool _customStakes = false;
  final _customStakesCtrl = TextEditingController();
  final _tournSbCtrl = TextEditingController();
  final _tournBbCtrl = TextEditingController();
  final _anteCtrl = TextEditingController();
  String? _tournamentStage;

  final List<String> _heroCards = [];
  int _numSeats = 6;
  String? _position;
  Street _street = Street.preflop;
  final List<String> _board = [];
  QuickFacing _facing = QuickFacing.unopened;
  QuickHeroAction? _heroAction;
  QuickPotType _potType = QuickPotType.auto;
  QuickEarlierAction _earlier = QuickEarlierAction.none;
  final _earlierBetCtrl = TextEditingController();
  final _facingSizeCtrl = TextEditingController();
  final _heroSizeCtrl = TextEditingController();
  final _potBeforeCtrl = TextEditingController();
  final _effStackCtrl = TextEditingController(text: '100');
  QuickResult? _result;
  final _resultAmountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  bool _saving = false;

  /// Session to link the saved hand to. Seeded from a prefilled (locked)
  /// session; otherwise chosen via the in-form picker (parity with the wizard).
  String? _selectedSessionId;

  bool get _sessionLocked => widget.prefilledSessionId != null;

  @override
  void initState() {
    super.initState();
    // Warm the PC range library so the save-time synthesis classifies on the
    // weighted charts (it falls back to the legacy charts if still loading).
    ref.read(pcRangeLibraryProvider);
    _selectedSessionId = widget.prefilledSessionId;
    _isTournament = widget.isTournamentSession;
    final prefill = widget.prefilledStakes?.trim();
    if (prefill != null && prefill.isNotEmpty) {
      // Tournament must be checked first: its stakes are blind levels that can
      // coincide with a cash preset (e.g. "1/2"), and a tournament always uses
      // the SB/BB fields, never the cash preset selector.
      if (_isTournament) {
        final blinds = parseBlindsFromStakes(prefill);
        if (blinds != null) {
          _tournSbCtrl.text = blinds.$1.round().toString();
          _tournBbCtrl.text = blinds.$2.round().toString();
        }
      } else if (kPresetStakes.contains(prefill)) {
        _selectedStakes = prefill;
      } else {
        _customStakes = true;
        _customStakesCtrl.text = prefill;
      }
    }
  }

  @override
  void dispose() {
    for (final c in [
      _customStakesCtrl, _tournSbCtrl, _tournBbCtrl, _anteCtrl,
      _facingSizeCtrl, _heroSizeCtrl, _potBeforeCtrl, _effStackCtrl,
      _resultAmountCtrl, _noteCtrl, _earlierBetCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Test hook — widget tests can't drive the card-picker bottom sheet.
  @visibleForTesting
  void debugSetHeroCards(List<String> cards) =>
      setState(() => _heroCards
        ..clear()
        ..addAll(cards));

  // ── parsing ──────────────────────────────────────────────────────────────────

  int? _parseBlind(String text) {
    final v = int.tryParse(text.replaceAll(',', '').trim());
    return (v != null && v > 0) ? v : null;
  }

  (int, int)? get _blinds {
    if (_isTournament) {
      final sb = _parseBlind(_tournSbCtrl.text);
      final bb = _parseBlind(_tournBbCtrl.text);
      return (sb != null && bb != null && sb <= bb) ? (sb, bb) : null;
    }
    final raw = _customStakes ? _customStakesCtrl.text : _selectedStakes;
    // Reuse the app's canonical parser so custom/prefilled stakes carrying
    // currency symbols, dash separators, k-suffixes or cap notation parse the
    // same here as everywhere else (a naive split('/') silently rejected them).
    final blinds = parseBlindsFromStakes(raw);
    if (blinds == null) return null;
    final sb = blinds.$1.round();
    final bb = blinds.$2.round();
    return (sb > 0 && bb > 0 && sb <= bb) ? (sb, bb) : null;
  }

  double? _parseBb(TextEditingController c) {
    final v = double.tryParse(c.text.trim());
    return (v != null && v > 0) ? v : null;
  }

  bool get _canSave =>
      _heroCards.length == 2 &&
      _position != null &&
      _blinds != null &&
      _heroAction != null;

  // ── street/facing/action option logic ────────────────────────────────────────

  static const _facingLabels = {
    QuickFacing.unopened: 'Unopened',
    QuickFacing.limp: 'Limper(s)',
    QuickFacing.openRaise: 'Open',
    QuickFacing.threeBet: '3-bet',
    QuickFacing.fourBetPlus: '4-bet+',
    QuickFacing.checkedTo: 'Checked to me',
    QuickFacing.bet: 'Bet',
    QuickFacing.raise: 'Raise',
    QuickFacing.allIn: 'All-in',
  };

  static const _actionLabels = {
    QuickHeroAction.fold: 'Fold',
    QuickHeroAction.check: 'Check',
    QuickHeroAction.call: 'Call',
    QuickHeroAction.bet: 'Bet',
    QuickHeroAction.raise: 'Raise',
    QuickHeroAction.allIn: 'All-in',
  };

  List<QuickFacing> get _facingOptions => _street == Street.preflop
      ? const [
          QuickFacing.unopened,
          QuickFacing.limp,
          QuickFacing.openRaise,
          QuickFacing.threeBet,
          QuickFacing.fourBetPlus,
          QuickFacing.allIn,
        ]
      : const [
          QuickFacing.checkedTo,
          QuickFacing.bet,
          QuickFacing.raise,
          QuickFacing.allIn,
        ];

  List<QuickHeroAction> get _actionOptions => switch (_facing) {
        QuickFacing.unopened => const [
            QuickHeroAction.fold,
            QuickHeroAction.check,
            QuickHeroAction.raise,
            QuickHeroAction.allIn,
          ],
        QuickFacing.limp => const [
            QuickHeroAction.fold,
            QuickHeroAction.check,
            QuickHeroAction.call,
            QuickHeroAction.raise,
            QuickHeroAction.allIn,
          ],
        QuickFacing.openRaise ||
        QuickFacing.threeBet ||
        QuickFacing.fourBetPlus ||
        QuickFacing.bet ||
        QuickFacing.raise =>
          const [
            QuickHeroAction.fold,
            QuickHeroAction.call,
            QuickHeroAction.raise,
            QuickHeroAction.allIn,
          ],
        QuickFacing.checkedTo => const [
            QuickHeroAction.check,
            QuickHeroAction.bet,
            QuickHeroAction.allIn,
          ],
        QuickFacing.allIn => const [
            QuickHeroAction.fold,
            QuickHeroAction.call,
          ],
      };

  /// "Earlier this street" applies to postflop aggression hero responded to.
  bool get _showEarlier =>
      _street != Street.preflop &&
      const {QuickFacing.bet, QuickFacing.raise, QuickFacing.allIn}
          .contains(_facing);

  /// Facing a raise requires hero to have bet; facing a bet means hero
  /// can't have bet (it would be a raise).
  List<QuickEarlierAction> get _earlierOptions => switch (_facing) {
        QuickFacing.raise => const [QuickEarlierAction.bet],
        QuickFacing.bet => const [
            QuickEarlierAction.none,
            QuickEarlierAction.checked,
          ],
        _ => QuickEarlierAction.values,
      };

  QuickEarlierAction get _defaultEarlier {
    if (_facing == QuickFacing.raise) return QuickEarlierAction.bet;
    return (_position == 'SB' || _position == 'BB')
        ? QuickEarlierAction.checked
        : QuickEarlierAction.none;
  }

  void _resetEarlierIfIllegal() {
    if (!_earlierOptions.contains(_earlier)) _earlier = _defaultEarlier;
  }

  bool get _facingHasSize => const {
        QuickFacing.openRaise,
        QuickFacing.threeBet,
        QuickFacing.fourBetPlus,
        QuickFacing.bet,
        QuickFacing.raise,
      }.contains(_facing);

  bool get _heroActionHasSize =>
      _heroAction == QuickHeroAction.bet || _heroAction == QuickHeroAction.raise;

  int get _boardCount => switch (_street) {
        Street.preflop => 0,
        Street.flop => 3,
        Street.turn => 4,
        Street.river => 5,
      };

  void _setStreet(Street s) => setState(() {
        final wasShown = _showEarlier;
        _street = s;
        final allowed = switch (s) {
          Street.preflop => 0,
          Street.flop => 3,
          Street.turn => 4,
          Street.river => 5,
        };
        if (_board.length > allowed) {
          _board.removeRange(allowed, _board.length);
        }
        if (!_facingOptions.contains(_facing)) {
          _facing = s == Street.preflop
              ? QuickFacing.unopened
              : QuickFacing.checkedTo;
        }
        if (!wasShown && _showEarlier) {
          _earlier = _defaultEarlier;
        } else {
          _resetEarlierIfIllegal();
        }
        if (_heroAction != null && !_actionOptions.contains(_heroAction)) {
          _heroAction = null;
        }
      });

  // ── pickers ──────────────────────────────────────────────────────────────────

  Future<void> _pickHeroCards() async {
    final cards = await showHandCardPicker(context,
        count: 2, used: _board.toSet());
    if (!mounted || cards == null) return;
    setState(() => _heroCards
      ..clear()
      ..addAll(cards));
  }

  Future<void> _pickBoard() async {
    final cards = await showHandCardPicker(context,
        count: _boardCount, used: _heroCards.toSet());
    if (!mounted || cards == null) return;
    setState(() => _board
      ..clear()
      ..addAll(cards));
  }

  // ── save ─────────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_saving || !_canSave) return;
    setState(() => _saving = true);
    try {
      final (sb, bb) = _blinds!;
      final input = QuickHandInput(
        heroCards: List.of(_heroCards),
        numSeats: _numSeats,
        positionLabel: _position!,
        smallBlind: sb,
        bigBlind: bb,
        decisionStreet: _street,
        boardCards: List.of(_board),
        facing: _facing,
        heroAction: _heroAction!,
        potType: _street == Street.preflop ? QuickPotType.auto : _potType,
        earlierAction:
            _showEarlier ? _earlier : QuickEarlierAction.none,
        earlierBetBb: _showEarlier && _earlier == QuickEarlierAction.bet
            ? _parseBb(_earlierBetCtrl)
            : null,
        facingSizeBb: _facingHasSize ? _parseBb(_facingSizeCtrl) : null,
        heroSizeBb: _heroActionHasSize ? _parseBb(_heroSizeCtrl) : null,
        potBeforeBb:
            _street == Street.preflop ? null : _parseBb(_potBeforeCtrl),
        effStackBb: _parseBb(_effStackCtrl),
        result: _result,
        resultAmountBb: _result != null ? _parseBb(_resultAmountCtrl) : null,
        userNote: _noteCtrl.text,
        isTournament: _isTournament,
        tournamentStage: _isTournament ? _tournamentStage : null,
        ante: _isTournament ? _parseBlind(_anteCtrl.text) : null,
      );
      final synth = synthesizeQuickHand(input,
          pcRanges: ref.read(pcRangeLibraryProvider).valueOrNull);
      await ref.read(handServiceProvider).saveHand(
            tableSetup: synth.tableSetup,
            players: synth.players,
            streets: synth.streets,
            sessionId: _sessionLocked ? widget.prefilledSessionId : _selectedSessionId,
            notes: synth.notes,
            tournamentStage: _isTournament ? _tournamentStage : null,
            isTournament: _isTournament,
            isQuickEntry: true,
          );
      AnalyticsService.handRecorded(
          isTournament: _isTournament, entryMode: 'quick');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Hand saved')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save hand. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _switchToFullMode() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => HandInputScreen(
          prefilledSessionId: widget.prefilledSessionId,
          prefilledStakes: widget.prefilledStakes,
          prefilledSessionLabel: widget.prefilledSessionLabel,
          isTournamentSession: widget.isTournamentSession,
        ),
      ),
    );
  }

  // ── build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quick Hand'),
        actions: [
          TextButton(
            onPressed: _switchToFullMode,
            child: const Text('Full mode'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          if (_sessionLocked)
            LinkedSessionBanner(label: widget.prefilledSessionLabel)
          else
            SessionPickerTile(
              selectedSessionId: _selectedSessionId,
              onChanged: (id) => setState(() => _selectedSessionId = id),
            ),
          const SizedBox(height: 12),
          _sectionLabel('GAME'),
          if (_sessionLocked)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                _isTournament ? 'Tournament · from session' : 'Cash · from session',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            )
          else
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('Cash')),
                ButtonSegment(value: true, label: Text('Tournament')),
              ],
              selected: {_isTournament},
              onSelectionChanged: (s) =>
                  setState(() => _isTournament = s.first),
            ),
          const SizedBox(height: 12),
          if (_isTournament) _tournamentStakesFields(cs) else _cashStakesChips(),
          const SizedBox(height: 16),
          _sectionLabel('YOUR CARDS'),
          Row(children: [
            GestureDetector(
              onTap: _pickHeroCards,
              child: Row(children: [
                PlayingCard(
                    card: _heroCards.isNotEmpty ? _heroCards[0] : null,
                    width: 44, height: 62),
                const SizedBox(width: 6),
                PlayingCard(
                    card: _heroCards.length > 1 ? _heroCards[1] : null,
                    width: 44, height: 62),
              ]),
            ),
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: _pickHeroCards,
              icon: const Icon(Icons.style_outlined, size: 18),
              label: Text(_heroCards.isEmpty ? 'Pick cards' : 'Change'),
            ),
          ]),
          const SizedBox(height: 16),
          _sectionLabel('POSITION'),
          Row(children: [
            DropdownButton<int>(
              value: _numSeats,
              items: [
                for (var n = 2; n <= 9; n++)
                  DropdownMenuItem(value: n, child: Text('$n-max')),
              ],
              onChanged: (n) => setState(() {
                _numSeats = n!;
                if (_position != null &&
                    !TableSetup.positionLabels(_numSeats)
                        .contains(_position)) {
                  _position = null;
                }
              }),
            ),
          ]),
          Wrap(
            spacing: 6,
            runSpacing: 0,
            children: [
              for (final label in TableSetup.positionLabels(_numSeats))
                ChoiceChip(
                  label: Text(label),
                  selected: _position == label,
                  onSelected: (_) => setState(() => _position = label),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _sectionLabel('THE DECISION'),
          SegmentedButton<Street>(
            // The default selected checkmark widens the segment and wraps the
            // 4-pill row on phones.
            showSelectedIcon: false,
            segments: [
              for (final s in Street.values)
                ButtonSegment(
                    value: s,
                    label: Text(s == Street.preflop ? 'Pre' : s.label)),
            ],
            selected: {_street},
            onSelectionChanged: (s) => _setStreet(s.first),
          ),
          if (_street != Street.preflop) ...[
            const SizedBox(height: 10),
            Row(children: [
              for (var i = 0; i < _board.length; i++) ...[
                PlayingCard(card: _board[i], width: 32, height: 45),
                const SizedBox(width: 4),
              ],
              TextButton.icon(
                onPressed: _pickBoard,
                icon: const Icon(Icons.dashboard_outlined, size: 18),
                label: Text(_board.isEmpty
                    ? 'Add board ($_boardCount cards) — optional'
                    : 'Change board'),
              ),
            ]),
          ],
          const SizedBox(height: 10),
          Text('Facing', style: Theme.of(context).textTheme.bodySmall),
          Wrap(
            spacing: 6,
            runSpacing: 0,
            children: [
              for (final f in _facingOptions)
                ChoiceChip(
                  label: Text(_facingLabels[f]!),
                  selected: _facing == f,
                  onSelected: (_) => setState(() {
                    final wasShown = _showEarlier;
                    _facing = f;
                    if (!wasShown && _showEarlier) {
                      _earlier = _defaultEarlier;
                    } else {
                      _resetEarlierIfIllegal();
                    }
                    if (_heroAction != null &&
                        !_actionOptions.contains(_heroAction)) {
                      _heroAction = null;
                    }
                  }),
                ),
            ],
          ),
          if (_facingHasSize)
            _bbField(_facingSizeCtrl, 'Size (BB) — optional'),
          if (_showEarlier) ...[
            const SizedBox(height: 10),
            Text('Earlier this street',
                style: Theme.of(context).textTheme.bodySmall),
            Wrap(
              spacing: 6,
              runSpacing: 0,
              children: [
                for (final e in _earlierOptions)
                  ChoiceChip(
                    label: Text(switch (e) {
                      QuickEarlierAction.none => 'Villain acted first',
                      QuickEarlierAction.checked => 'I checked first',
                      QuickEarlierAction.bet => 'I bet first',
                    }),
                    selected: _earlier == e,
                    onSelected: (_) => setState(() => _earlier = e),
                  ),
              ],
            ),
            if (_earlier == QuickEarlierAction.bet)
              _bbField(_earlierBetCtrl, 'Your earlier bet (BB) — optional'),
          ],
          const SizedBox(height: 10),
          Text('You', style: Theme.of(context).textTheme.bodySmall),
          Wrap(
            spacing: 6,
            runSpacing: 0,
            children: [
              for (final a in _actionOptions)
                ChoiceChip(
                  label: Text(_actionLabels[a]!),
                  selected: _heroAction == a,
                  onSelected: (_) => setState(() => _heroAction = a),
                ),
            ],
          ),
          if (_heroActionHasSize)
            _bbField(_heroSizeCtrl, 'Your size (BB) — optional'),
          if (_street != Street.preflop) ...[
            _bbField(_potBeforeCtrl,
                'Pot entering this street (BB) — optional'),
            const SizedBox(height: 10),
            Text('How preflop went — optional',
                style: Theme.of(context).textTheme.bodySmall),
            Wrap(
              spacing: 6,
              runSpacing: 0,
              children: [
                for (final t in QuickPotType.values)
                  ChoiceChip(
                    label: Text(switch (t) {
                      QuickPotType.auto => 'Auto',
                      QuickPotType.limped => 'Limped',
                      QuickPotType.singleRaised => 'Single-raised',
                      QuickPotType.threeBet => '3-bet pot',
                      QuickPotType.fourBet => '4-bet pot',
                    }),
                    selected: _potType == t,
                    onSelected: (_) => setState(() => _potType = t),
                  ),
              ],
            ),
          ],
          _bbField(_effStackCtrl, 'Effective stacks (BB)'),
          const SizedBox(height: 16),
          _sectionLabel('RESULT — OPTIONAL'),
          Wrap(
            spacing: 6,
            runSpacing: 0,
            children: [
              for (final r in QuickResult.values)
                ChoiceChip(
                  label: Text(switch (r) {
                    QuickResult.won => 'Won',
                    QuickResult.lost => 'Lost',
                    QuickResult.chopped => 'Chopped',
                  }),
                  selected: _result == r,
                  onSelected: (sel) =>
                      setState(() => _result = sel ? r : null),
                ),
            ],
          ),
          if (_result != null)
            _bbField(_resultAmountCtrl, 'Final pot (BB) — optional'),
          const SizedBox(height: 8),
          TextField(
            controller: _noteCtrl,
            decoration: const InputDecoration(
              labelText: 'Note — optional',
              hintText: 'Reads, dynamics, why it was close…',
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _canSave && !_saving ? _save : null,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: Text(_saving ? 'Saving…' : 'Save Hand'),
          ),
          SizedBox(height: MediaQuery.paddingOf(context).bottom),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );

  Widget _cashStakesChips() => Wrap(
        spacing: 6,
        runSpacing: 0,
        children: [
          for (final s in kPresetStakes)
            ChoiceChip(
              label: Text(s),
              selected: !_customStakes && _selectedStakes == s,
              onSelected: (_) => setState(() {
                _customStakes = false;
                _selectedStakes = s;
              }),
            ),
          ChoiceChip(
            label: const Text('Custom'),
            selected: _customStakes,
            onSelected: (_) => setState(() => _customStakes = true),
          ),
          if (_customStakes)
            SizedBox(
              width: 120,
              child: TextField(
                controller: _customStakesCtrl,
                decoration: const InputDecoration(
                    hintText: 'e.g. 2/5', isDense: true),
                keyboardType: TextInputType.text,
                onChanged: (_) => setState(() {}),
              ),
            ),
        ],
      );

  Widget _tournamentStakesFields(ColorScheme cs) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _tournSbCtrl,
                decoration:
                    const InputDecoration(labelText: 'SB', isDense: true),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _tournBbCtrl,
                decoration:
                    const InputDecoration(labelText: 'BB', isDense: true),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _anteCtrl,
                decoration: const InputDecoration(
                    labelText: 'Ante', isDense: true),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ),
          ]),
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            initialValue: _tournamentStage,
            decoration: const InputDecoration(
                labelText: 'Stage — optional', isDense: true),
            items: [
              for (final (value, label) in kTournamentStages)
                DropdownMenuItem(value: value, child: Text(label)),
            ],
            onChanged: (v) => setState(() => _tournamentStage = v),
          ),
        ],
      );

  Widget _bbField(TextEditingController ctrl, String label) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: SizedBox(
          width: 260,
          child: TextField(
            controller: ctrl,
            decoration: InputDecoration(labelText: label, isDense: true),
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
          ),
        ),
      );
}
