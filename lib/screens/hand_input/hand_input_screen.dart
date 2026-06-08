import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/hand_model.dart';
import '../../providers/providers.dart';
import '../../providers/reads_provider.dart';
import '../../services/analytics_service.dart';
import '../../utils/helpers.dart';
import '../../widgets/playing_card_widget.dart';
import '../../widgets/chip_stack_widget.dart';
import '../../theme/app_theme.dart';
import '../hand_replayer/hand_replayer_screen.dart';

class _BlindFormatter extends TextInputFormatter {
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

enum _Step {
  setup,
  preflopAction,
  flopAction,
  turnAction,
  riverAction,
  showdown,
  done,
}

class HandInputScreen extends ConsumerStatefulWidget {
  final String? prefilledSessionId;
  final String? prefilledStakes;
  final String? prefilledSessionLabel;
  final bool isTournamentSession;

  const HandInputScreen({
    super.key,
    this.prefilledSessionId,
    this.prefilledStakes,
    this.prefilledSessionLabel,
    this.isTournamentSession = false,
  });

  @override
  ConsumerState<HandInputScreen> createState() => _HandInputScreenState();
}

class _HandInputScreenState extends ConsumerState<HandInputScreen> {
  // ── wizard step ─────────────────────────────────────────────────────────────
  _Step _step = _Step.setup;
  bool _awaitingDeal = false; // true while waiting to deal next street

  // ── table setup ─────────────────────────────────────────────────────────────
  int _numSeats = 6;
  int _heroSeat = 0;
  String _selectedStakes = '1/2';
  bool _hasStraddle = false;
  final List<TextEditingController> _nameCtrl =
      List.generate(9, (i) => TextEditingController());
  final List<FocusNode> _nameFocusNodes =
      List.generate(9, (_) => FocusNode());
  final List<TextEditingController> _stackCtrl =
      List.generate(9, (i) => TextEditingController());

  static const _presetStakes = [
    '1/2', '1/3', '2/3', '2/5', '5/10', '10/20', '10/25', '25/50',
  ];

  List<String> get _positions => TableSetup.positionLabels(_numSeats);

  int? get _parsedSB {
    if (_isTournamentHand) {
      final v = int.tryParse(_tournSbCtrl.text.replaceAll(',', ''));
      return (v != null && v > 0) ? v : null;
    }
    final p = _selectedStakes.split('/');
    return p.length >= 2 ? int.tryParse(p[0].trim()) : null;
  }

  int? get _parsedBB {
    if (_isTournamentHand) {
      final v = int.tryParse(_tournBbCtrl.text.replaceAll(',', ''));
      return (v != null && v > 0) ? v : null;
    }
    final p = _selectedStakes.split('/');
    return p.length >= 2 ? int.tryParse(p[1].trim()) : null;
  }

  bool get _canStart {
    final sb = _parsedSB;
    final bb = _parsedBB;
    return sb != null && bb != null && sb > 0 && bb > 0 && sb < bb;
  }

  static final _blindFmt = NumberFormat('#,###', 'en_US');
  static String _fmtBlind(int v) => _blindFmt.format(v);

  // ── hero cards ───────────────────────────────────────────────────────────────
  final List<String> _heroCards = [];

  // ── runtime hand state ───────────────────────────────────────────────────────
  late TableSetup _setup;
  late List<HandPlayer> _players;
  late List<int> _activeSeats;
  late Map<int, int> _runningStacks;
  final List<HandAction> _streetActions = [];
  Map<int, int> _contributions = {};
  int _currentBet = 0;
  List<int> _toAct = [];
  final Set<int> _allInSeats = {};
  Street _currentStreet = Street.preflop;
  int _pot = 0;
  int _lastRaiseSize = 0;
  final List<StreetData> _completedStreets = [];

  // ── community cards ──────────────────────────────────────────────────────────
  List<String> _flopCards = [];
  String? _turnCard;
  String? _riverCard;

  // ── raise UI ─────────────────────────────────────────────────────────────────
  bool _raiseMode = false;
  final _raiseCtrl = TextEditingController();

  // ── showdown ─────────────────────────────────────────────────────────────────
  final Map<int, List<String>?> _showdownCards = {};
  int _showdownIdx = 0;
  late List<int> _showdownOrder;

  // ── undo stack ───────────────────────────────────────────────────────────────
  final List<_HandSnapshot> _undoStack = [];

  void _pushSnapshot() {
    _undoStack.add(_HandSnapshot(
      streetActions: List.from(_streetActions),
      completedStreets: List.from(_completedStreets),
      toAct: List.from(_toAct),
      activeSeats: List.from(_activeSeats),
      runningStacks: Map.from(_runningStacks),
      contributions: Map.from(_contributions),
      currentBet: _currentBet,
      currentStreet: _currentStreet,
      pot: _pot,
      lastRaiseSize: _lastRaiseSize,
      allInSeats: Set.from(_allInSeats),
      step: _step,
      awaitingDeal: _awaitingDeal,
      flopCards: List.from(_flopCards),
      turnCard: _turnCard,
      riverCard: _riverCard,
    ));
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    final snap = _undoStack.removeLast();
    setState(() {
      _streetActions
        ..clear()
        ..addAll(snap.streetActions);
      _completedStreets
        ..clear()
        ..addAll(snap.completedStreets);
      _toAct = snap.toAct;
      _activeSeats = snap.activeSeats;
      _runningStacks = snap.runningStacks;
      _contributions = snap.contributions;
      _currentBet = snap.currentBet;
      _currentStreet = snap.currentStreet;
      _pot = snap.pot;
      _lastRaiseSize = snap.lastRaiseSize;
      _allInSeats
        ..clear()
        ..addAll(snap.allInSeats);
      _step = snap.step;
      _awaitingDeal = snap.awaitingDeal;
      _flopCards = snap.flopCards;
      _turnCard = snap.turnCard;
      _riverCard = snap.riverCard;
      _raiseMode = false;
    });
  }

  // ── tournament context ───────────────────────────────────────────────────────
  bool _isTournamentHand = false;
  final _anteCtrl = TextEditingController();
  final _tournSbCtrl = TextEditingController();
  final _tournBbCtrl = TextEditingController();
  String? _tournamentStage;

  static const _tournamentStages = [
    (null, 'Not specified'),
    ('early', 'Early stages (Day 1/2)'),
    ('middle', 'Middle stages'),
    ('late', 'Late stages'),
    ('bubble', 'On the bubble'),
    ('itm', 'In the money (ITM)'),
    ('ft_bubble', 'Final table bubble'),
    ('final_table', 'Final table'),
  ];

  // ── session linking ──────────────────────────────────────────────────────────
  String? _selectedSessionId;

  // ── saved hand ───────────────────────────────────────────────────────────────
  PokerHand? _savedHand;
  bool _saving = false;

  Set<String> get _usedCards {
    final used = <String>{};
    used.addAll(_heroCards);
    used.addAll(_flopCards);
    if (_turnCard != null) used.add(_turnCard!);
    if (_riverCard != null) used.add(_riverCard!);
    for (final c in _showdownCards.values) {
      if (c != null) used.addAll(c);
    }
    return used;
  }

  List<String> get _currentCommunityCards {
    switch (_currentStreet) {
      case Street.preflop:
        return [];
      case Street.flop:
        return _flopCards;
      case Street.turn:
        return [..._flopCards, if (_turnCard != null) _turnCard!];
      case Street.river:
        return [
          ..._flopCards,
          if (_turnCard != null) _turnCard!,
          if (_riverCard != null) _riverCard!,
        ];
    }
  }

  int get _currentPot =>
      _pot + _contributions.values.fold(0, (a, b) => a + b);

  // True when ≤1 non-all-in player is still active — cards run out with no action.
  bool get _isAllInRunout {
    final nonAllIn = _activeSeats.where((s) => !_allInSeats.contains(s)).length;
    return nonAllIn <= 1;
  }

  int get _minRaise =>
      _currentBet + max(_setup.bigBlind, _lastRaiseSize);

  @override
  void initState() {
    super.initState();
    if (widget.prefilledSessionId != null) {
      _selectedSessionId = widget.prefilledSessionId;
    }
    // Pre-fill stakes from the session as an editable default (cash only —
    // tournaments use the blind-level fields). Any value is accepted, not just
    // presets, so a "3/6" session doesn't silently fall back to 1/2. The user
    // can still change it or add a straddle, which the session can't capture.
    if (!widget.isTournamentSession &&
        widget.prefilledStakes != null &&
        widget.prefilledStakes!.isNotEmpty &&
        widget.prefilledStakes != 'N/A') {
      _selectedStakes = widget.prefilledStakes!;
    }
    _isTournamentHand = widget.isTournamentSession;
  }

  // ── setup → start ────────────────────────────────────────────────────────────
  void _startHand() {
    final sb = _parsedSB!;
    final bb = _parsedBB!;
    final str = _hasStraddle ? bb * 2 : null;
    final defaultStack = _hasStraddle ? 200 * bb : 100 * bb;

    _setup = TableSetup(
      numSeats: _numSeats,
      buttonSeat: 0,
      heroSeat: _heroSeat,
      smallBlind: sb,
      bigBlind: bb,
      straddle: str,
      ante: int.tryParse(_anteCtrl.text.trim()),
    );

    _players = List.generate(_numSeats, (i) {
      final name = _nameCtrl[i].text.trim();
      final customStack = int.tryParse(_stackCtrl[i].text.trim());
      return HandPlayer(
        seatIndex: i,
        name: name.isEmpty ? (i == _heroSeat ? 'Hero' : _positions[i]) : name,
        startingStack:
            (customStack != null && customStack > 0) ? customStack : defaultStack,
        isHero: i == _heroSeat,
      );
    });

    _activeSeats = List.generate(_numSeats, (i) => i);
    _runningStacks = {for (final p in _players) p.seatIndex: p.startingStack};
    _undoStack.clear();

    _initPreflop();
  }

  // ── preflop init ─────────────────────────────────────────────────────────────
  void _initPreflop() {
    _currentStreet = Street.preflop;
    _contributions = {};
    _streetActions.clear();
    _allInSeats.clear();
    _raiseMode = false;
    _currentBet = _setup.straddle ?? _setup.bigBlind;
    _lastRaiseSize = _setup.straddle ?? _setup.bigBlind;

    void post(int seat, int amount, ActionType type) {
      _contributions[seat] = amount;
      _runningStacks[seat] = _runningStacks[seat]! - amount;
      _streetActions.add(HandAction(seat: seat, type: type, amount: amount));
    }

    post(_setup.sbSeat, _setup.smallBlind, ActionType.post);
    post(_setup.bbSeat, _setup.bigBlind, ActionType.post);
    if (_setup.straddle != null) {
      post(_setup.straddleSeat, _setup.straddle!, ActionType.postStraddle);
    }

    _toAct = _setup.preflopOrder(_activeSeats);
    setState(() => _step = _Step.preflopAction);
  }

  void _initPostflop(Street street, _Step nextStep) {
    _currentStreet = street;
    _contributions = {};
    _streetActions.clear();
    // Do NOT clear _allInSeats — all-in is permanent for the hand duration.
    _raiseMode = false;
    _awaitingDeal = false;
    _currentBet = 0;
    _lastRaiseSize = 0;
    // Exclude all-in players: they have no chips to bet with on this street.
    _toAct = _setup.postflopOrder(_activeSeats)
        .where((s) => !_allInSeats.contains(s))
        .toList();
    setState(() => _step = nextStep);
  }

  // ── action handlers ───────────────────────────────────────────────────────────
  void _doFold() {
    _pushSnapshot();
    final seat = _toAct.removeAt(0);
    _activeSeats.remove(seat);
    _streetActions.add(HandAction(seat: seat, type: ActionType.fold));
    _checkStreetDone();
  }

  void _doCheck() {
    _pushSnapshot();
    final seat = _toAct.removeAt(0);
    _streetActions.add(HandAction(seat: seat, type: ActionType.check));
    _checkStreetDone();
  }

  void _doCall() {
    _pushSnapshot();
    final seat = _toAct.removeAt(0);
    final prev = _contributions[seat] ?? 0;
    final stack = _runningStacks[seat] ?? 0;
    final needed = _currentBet - prev;
    final actual = min(needed, stack);
    final isAllIn = actual >= stack;
    _contributions[seat] = prev + actual;
    _runningStacks[seat] = stack - actual;
    if (isAllIn) _allInSeats.add(seat);
    _streetActions.add(HandAction(
        seat: seat,
        type: ActionType.call,
        amount: _contributions[seat],
        isAllIn: isAllIn));
    _checkStreetDone();
  }

  void _doRaise(int totalAmount) {
    _pushSnapshot();
    final isOpeningBet = _currentBet == 0;
    final seat = _toAct.removeAt(0);
    final prev = _contributions[seat] ?? 0;
    final stack = _runningStacks[seat] ?? 0;
    final delta = totalAmount - prev;
    final isAllIn = delta >= stack;
    final actual = isAllIn ? stack : delta;
    _contributions[seat] = prev + actual;
    _runningStacks[seat] = stack - actual;

    final prevBet = _currentBet;
    _currentBet = _contributions[seat]!;
    _lastRaiseSize = _currentBet - prevBet;

    if (isAllIn) _allInSeats.add(seat);
    _streetActions.add(HandAction(
        seat: seat,
        type: ActionType.raise,
        amount: _contributions[seat],
        isAllIn: isAllIn,
        isOpeningBet: isOpeningBet));

    // Action goes clockwise from the player immediately left of the raiser.
    // This is correct for both preflop and postflop — do NOT restart from UTG.
    final nextSeat = (seat + 1) % _setup.numSeats;
    _toAct = List.generate(_setup.numSeats, (i) => (nextSeat + i) % _setup.numSeats)
        .where((s) => _activeSeats.contains(s) && s != seat && !_allInSeats.contains(s))
        .toList();

    _raiseMode = false;
    _checkStreetDone();
  }

  void _checkStreetDone() {
    if (_toAct.isEmpty || _activeSeats.length <= 1) {
      _finalizeStreet();
    } else {
      setState(() {});
    }
  }

  void _finalizeStreet() {
    // Store only the cards newly dealt THIS street, not the accumulated board.
    // The replayer accumulates cards across streets, so sending cumulative lists
    // causes duplication (flop cards would appear 3x by river).
    final newCards = switch (_currentStreet) {
      Street.preflop => <String>[],
      Street.flop => List<String>.from(_flopCards),
      Street.turn => [if (_turnCard != null) _turnCard!],
      Street.river => [if (_riverCard != null) _riverCard!],
    };
    _completedStreets.add(StreetData(
      street: _currentStreet,
      communityCards: newCards,
      actions: List.from(_streetActions),
    ));
    _pot += _contributions.values.fold(0, (a, b) => a + b);
    _contributions = {};

    if (_activeSeats.length <= 1 || _currentStreet == Street.river) {
      _beginShowdown();
    } else {
      setState(() => _awaitingDeal = true);
    }
  }

  // ── deal next street at the table ─────────────────────────────────────────────
  Future<void> _dealNextStreet() async {
    final numCompleted = _completedStreets.length;
    final nextStreet = numCompleted == 1
        ? Street.flop
        : numCompleted == 2
            ? Street.turn
            : Street.river;
    final count = nextStreet == Street.flop ? 3 : 1;

    final picked = await _pickCards(count);
    if (!mounted || picked == null || picked.length != count) return;

    _pushSnapshot();

    if (nextStreet == Street.flop) {
      _flopCards = picked;
    } else if (nextStreet == Street.turn) {
      _turnCard = picked.first;
    } else {
      _riverCard = picked.first;
    }

    if (_isAllInRunout) {
      // All-in runout: record the street with no action, then immediately
      // move to the next deal (or showdown if river).
      _currentStreet = nextStreet;
      _contributions = {};
      _streetActions.clear();
      _currentBet = 0;
      _lastRaiseSize = 0;
      _awaitingDeal = false;
      _finalizeStreet();
    } else {
      final nextStep = nextStreet == Street.flop
          ? _Step.flopAction
          : nextStreet == Street.turn
              ? _Step.turnAction
              : _Step.riverAction;
      _initPostflop(nextStreet, nextStep);
    }
  }

  // ── showdown ─────────────────────────────────────────────────────────────────
  void _beginShowdown() {
    _showdownOrder = _activeSeats.toList();
    _showdownIdx = 0;
    for (final seat in _showdownOrder) {
      if (seat == _setup.heroSeat) {
        _showdownCards[seat] = _heroCards.isEmpty ? null : _heroCards;
      }
    }
    setState(() => _step = _Step.showdown);
  }

  void _muck(int seat) {
    _showdownCards[seat] = null;
    _advanceShowdown();
  }

  void _advanceShowdown() {
    _showdownIdx++;
    if (_showdownIdx >= _showdownOrder.length) {
      _saveHand();
    } else {
      setState(() {});
    }
  }

  // ── save ─────────────────────────────────────────────────────────────────────
  Future<void> _saveHand() async {
    if (_saving) return;
    _saving = true;

    final updatedPlayers = _players.map((p) {
      final cards = _showdownCards[p.seatIndex];
      if (cards != null) return p.copyWith(holeCards: cards);
      if (p.isHero && _heroCards.isNotEmpty) {
        return p.copyWith(holeCards: _heroCards);
      }
      return p;
    }).toList();

    try {
      final service = ref.read(handServiceProvider);
      final hand = await service.saveHand(
        tableSetup: _setup,
        players: updatedPlayers,
        streets: _completedStreets,
        sessionId: _selectedSessionId,
        tournamentStage: _isTournamentHand ? _tournamentStage : null,
        isTournament: _isTournamentHand,
      );
      AnalyticsService.handRecorded(isTournament: _isTournamentHand);
      if (!mounted) return;
      setState(() {
        _savedHand = hand;
        _step = _Step.done;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save hand. Please try again.')),
      );
    } finally {
      _saving = false;
    }
  }

  // ── card picker ───────────────────────────────────────────────────────────────
  Future<List<String>?> _pickCards(int count, {Set<String>? extra}) async {
    final used = {..._usedCards, ...?extra};
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _CardPicker(count: count, used: used),
    );
  }

  Future<void> _pickHeroCards() async {
    final cards = await _pickCards(2);
    if (!mounted || cards == null) return;
    setState(() => _heroCards
      ..clear()
      ..addAll(cards));
  }

  // ── build ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) =>
      // The hand-input table is an immersive green-felt experience — keep it
      // dark regardless of the app's light/dark theme.
      Theme(data: AppTheme.dark, child: _build(context));

  Widget _build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_stepTitle),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _confirmExit(context),
        ),
        actions: [
          if (_undoStack.isNotEmpty &&
              _step != _Step.setup &&
              _step != _Step.done &&
              _step != _Step.showdown)
            IconButton(
              icon: const Icon(Icons.undo_rounded),
              tooltip: 'Undo last action',
              onPressed: _undo,
            ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  String get _stepTitle {
    switch (_step) {
      case _Step.setup:
        return 'Table Setup';
      case _Step.preflopAction:
        return _awaitingDeal ? 'Deal Flop' : 'Pre-flop';
      case _Step.flopAction:
        return _awaitingDeal ? 'Deal Turn' : 'Flop';
      case _Step.turnAction:
        return _awaitingDeal ? 'Deal River' : 'Turn';
      case _Step.riverAction:
        return 'River';
      case _Step.showdown:
        return 'Showdown';
      case _Step.done:
        return 'Hand Saved';
    }
  }

  Widget _buildBody() {
    switch (_step) {
      case _Step.setup:
        return _buildSetup();
      case _Step.preflopAction:
      case _Step.flopAction:
      case _Step.turnAction:
      case _Step.riverAction:
        return _buildVisualAction();
      case _Step.showdown:
        return _buildShowdown();
      case _Step.done:
        return _buildDone();
    }
  }

  // ── step: setup ───────────────────────────────────────────────────────────────
  Widget _buildSetup() {
    final bb = _parsedBB;
    final sb = _parsedSB;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Session linking ──────────────────────────────────────────────────
        if (widget.prefilledSessionId != null)
          _LinkedSessionBanner(label: widget.prefilledSessionLabel)
        else
          _SessionPickerTile(
            selectedSessionId: _selectedSessionId,
            onChanged: (id) => setState(() => _selectedSessionId = id),
          ),
        const SizedBox(height: 20),

        const Text('Table Size',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          initialValue: _numSeats,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
            contentPadding:
                EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          items: [
            for (var n = 2; n <= 9; n++)
              DropdownMenuItem(value: n, child: Text(tableSizeLabel(n))),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              _numSeats = v;
              if (_heroSeat >= _numSeats) _heroSeat = 0;
            });
          },
        ),
        const SizedBox(height: 20),

        // ── Tournament toggle ────────────────────────────────────────────────
        if (widget.prefilledSessionId != null)
          // Recording from a session: game type is inherited and locked — no
          // need to ask again. (Stakes are pre-filled but stay editable, since
          // the session's stakes can't capture a straddle / 3-blind game.)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(Icons.lock_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  _isTournamentHand ? 'Tournament hand' : 'Cash hand',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(width: 8),
                Text(
                  '· from session',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          )
        else
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Tournament hand'),
            subtitle: const Text(
              'Enables blind level labelling, ante, stage & BB-depth tracking',
              style: TextStyle(fontSize: 11),
            ),
            value: _isTournamentHand,
            onChanged: (v) => setState(() {
              _isTournamentHand = v;
              if (!v) {
                _anteCtrl.clear();
                _tournSbCtrl.clear();
                _tournBbCtrl.clear();
                _tournamentStage = null;
              }
            }),
          ),
        const SizedBox(height: 16),

        // ── Blind level (Stakes) ────────────────────────────────────────────
        Text(
          _isTournamentHand ? 'Blind Level' : 'Stakes',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        if (_isTournamentHand)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  controller: _tournSbCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [_BlindFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Small Blind',
                    hintText: '100',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('/',
                    style: TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w300)),
              ),
              Expanded(
                child: TextField(
                  controller: _tournBbCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [_BlindFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Big Blind',
                    hintText: '200',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          )
        else
          DropdownButtonFormField<String>(
            initialValue: _selectedStakes,
            decoration: const InputDecoration(
              prefixText: '\$',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            items: [
              // Include a non-preset prefilled value (e.g. a "3/6" session) so
              // it's selectable and the dropdown's value is always valid.
              if (!_presetStakes.contains(_selectedStakes))
                DropdownMenuItem(
                  value: _selectedStakes,
                  child: Text('\$$_selectedStakes',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ..._presetStakes.map((s) => DropdownMenuItem(
                    value: s,
                    child: Text('\$$s',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  )),
            ],
            onChanged: (v) => setState(() => _selectedStakes = v!),
          ),
        if (sb != null && bb != null)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              _isTournamentHand
                  ? 'SB ${_fmtBlind(sb)}  ·  BB ${_fmtBlind(bb)}'
                    '  ·  Default stack ${_fmtBlind(100 * bb)} chips (100 BBs)'
                  : 'SB \$$sb  ·  BB \$$bb'
                    '${_hasStraddle ? '  ·  Straddle \$${bb * 2}' : ''}'
                    '  ·  Default stack \$${_hasStraddle ? 200 * bb : 100 * bb}',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),
        const SizedBox(height: 12),

        // ── Ante (tournament only) ───────────────────────────────────────────
        if (_isTournamentHand) ...[
          TextField(
            controller: _anteCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Ante (optional)',
              hintText: 'e.g. 500 for BB ante',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),

          // ── Tournament stage ───────────────────────────────────────────────
          DropdownButtonFormField<String?>(
            initialValue: _tournamentStage,
            decoration: const InputDecoration(
              labelText: 'Tournament Stage (optional)',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            items: _tournamentStages
                .map((entry) => DropdownMenuItem<String?>(
                      value: entry.$1,
                      child: Text(entry.$2),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _tournamentStage = v),
          ),
          const SizedBox(height: 12),
        ],

        // ── Straddle (cash only) ─────────────────────────────────────────────
        if (!_isTournamentHand) ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Straddle'),
            subtitle: bb != null
                ? Text('Auto \$${bb * 2}  ·  200 BB stacks',
                    style: const TextStyle(fontSize: 11))
                : null,
            value: _hasStraddle,
            onChanged: (v) => setState(() => _hasStraddle = v),
          ),
        ],
        const SizedBox(height: 16),

        const Text('Your Position',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _positions.asMap().entries.map((e) => ChoiceChip(
                label: Text(e.value),
                selected: _heroSeat == e.key,
                onSelected: (_) => setState(() => _heroSeat = e.key),
              )).toList(),
        ),
        const SizedBox(height: 20),

        const Text('Players (optional)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 2),
        const Text('Leave stack blank for default',
            style: TextStyle(color: Colors.white38, fontSize: 11)),
        const SizedBox(height: 8),
        ...() {
          // Fetch reads once; ref.watch called only here, not once per seat.
          final readsNames = ref.watch(readsProvider).valueOrNull
                  ?.map((r) => r.playerLabel)
                  .toList() ??
              [];
          return List.generate(_numSeats, (i) {
            final pos = _positions[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Container(
                width: 46,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                decoration: BoxDecoration(
                  color: i == _heroSeat
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Colors.grey[800],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(pos,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 3,
                child: RawAutocomplete<String>(
                  textEditingController: _nameCtrl[i],
                  focusNode: _nameFocusNodes[i],
                  optionsBuilder: (v) {
                    final q = v.text.trim().toLowerCase();
                    if (q.isEmpty) return readsNames;
                    return readsNames
                        .where((n) => n.toLowerCase().contains(q));
                  },
                  displayStringForOption: (s) => s,
                  fieldViewBuilder: (ctx, ctrl, fn, _) => TextField(
                    controller: ctrl,
                    focusNode: fn,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: i == _heroSeat ? 'You' : 'Villain',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                    ),
                  ),
                  optionsViewBuilder: (ctx, onSelected, options) => Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4,
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(6),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 140),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (_, idx) {
                            final opt = options.elementAt(idx);
                            return InkWell(
                              onTap: () => onSelected(opt),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                child: Text(opt,
                                    style: const TextStyle(fontSize: 13)),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 90,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _stackCtrl[i],
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Stack',
                        prefixText: _isTournamentHand ? null : '\$',
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 8),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    if (_isTournamentHand && bb != null && bb > 0)
                      Builder(builder: (_) {
                        final entered = int.tryParse(_stackCtrl[i].text);
                        final defaultStack = 100 * bb;
                        final stack = (entered != null && entered > 0)
                            ? entered
                            : defaultStack;
                        final bbs = stack ~/ bb;
                        return Text(
                          '$bbs BBs',
                          style: const TextStyle(
                              fontSize: 9, color: Colors.white38),
                        );
                      }),
                  ],
                ),
              ),
            ]),
          );
          });
        }(),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _canStart ? _startHand : null,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: const Text('Start Recording'),
        ),
        const SizedBox(height: 32),
      ]),
    );
  }

  // ── step: visual action (table + action panel or deal panel) ─────────────────
  Widget _buildVisualAction() {
    if (_awaitingDeal) {
      return Column(children: [
        Expanded(child: _buildTableView(-1)),
        _buildDealPanel(),
      ]);
    }

    if (_toAct.isEmpty) return const SizedBox.shrink();
    final actingSeat = _toAct.first;
    final player = _players.firstWhere((p) => p.seatIndex == actingSeat);
    final position = _setup.positionName(actingSeat);
    final stack = _runningStacks[actingSeat] ?? 0;
    final prev = _contributions[actingSeat] ?? 0;
    final toCall = min(_currentBet - prev, stack);
    final canCheck = _currentBet == prev;
    final canBet = _currentBet == 0;

    return Column(children: [
      Expanded(child: _buildTableView(actingSeat)),
      _buildActionPanel(
        actingSeat: actingSeat,
        player: player,
        position: position,
        stack: stack,
        toCall: toCall,
        canCheck: canCheck,
        canBet: canBet,
      ),
    ]);
  }

  double _seatAngle(int seatIndex) {
    final displayIdx =
        (seatIndex - _setup.heroSeat + _setup.numSeats) % _setup.numSeats;
    return pi / 2 + (2 * pi * displayIdx / _setup.numSeats);
  }

  Widget _buildTableView(int actingSeat) {
    final total = _setup.numSeats;
    final panelW = total > 6 ? 72.0 : 78.0;
    final panelH = total > 6 ? 74.0 : 80.0;

    return LayoutBuilder(builder: (ctx, constraints) {
      final w = constraints.maxWidth;
      final h = constraints.maxHeight;
      final cx = w / 2;
      final cy = h / 2;
      final rx = (w * 0.35).clamp(0.0, (w - panelW) / 2 - 4);
      final ry = (h * 0.32).clamp(0.0, (h - panelH) / 2 - 4);

      return Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          CustomPaint(
              size: Size(w, h),
              painter: _InputTablePainter(cx: cx, cy: cy, rx: rx, ry: ry)),

          // Center: community cards + pot
          Align(
            alignment: Alignment.center,
            child: SizedBox(
              width: (w - panelW * 2 - 16).clamp(80.0, 200.0),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (_currentCommunityCards.isNotEmpty)
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 2,
                    runSpacing: 2,
                    children: _currentCommunityCards
                        .map((c) => PlayingCard(card: c, width: 26, height: 37))
                        .toList(),
                  ),
                if (_currentPot > 0) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Text('POT  \$$_currentPot',
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white70,
                            letterSpacing: 0.6)),
                  ),
                ],
              ]),
            ),
          ),

          // Bet chips (inner ring)
          for (final p in _players)
            if ((_contributions[p.seatIndex] ?? 0) > 0 &&
                _activeSeats.contains(p.seatIndex))
              Builder(builder: (_) {
                final a = _seatAngle(p.seatIndex);
                final left = (cx + rx * 0.42 * cos(a) - 12)
                    .clamp(0.0, w - 28.0);
                final top = (cy + ry * 0.42 * sin(a) - 22)
                    .clamp(0.0, h - 40.0);
                return Positioned(
                  left: left,
                  top: top,
                  child: ChipStack(
                    amount: _contributions[p.seatIndex]!,
                    bigBlind: _setup.bigBlind,
                    chipDiameter: 14,
                  ),
                );
              }),

          // Player panels — hero is tappable to add/change cards
          for (final p in _players)
            Builder(builder: (_) {
              final a = _seatAngle(p.seatIndex);
              final rawX = cx + rx * cos(a);
              final rawY = cy + ry * sin(a);
              final left = (rawX - panelW / 2).clamp(0.0, w - panelW);
              final top = (rawY - panelH / 2).clamp(0.0, h - panelH);
              final isActing = p.seatIndex == actingSeat;
              final isFolded = !_activeSeats.contains(p.seatIndex);

              final panel = _RecorderPlayerPanel(
                player: p,
                position: _setup.positionName(p.seatIndex),
                stack: _runningStacks[p.seatIndex] ?? 0,
                folded: isFolded,
                isActing: isActing,
                isAllIn: _allInSeats.contains(p.seatIndex),
                heroCards: p.isHero ? _heroCards : null,
              );

              return Positioned(
                left: left,
                top: top,
                width: panelW,
                height: panelH,
                child: p.isHero
                    ? GestureDetector(onTap: _pickHeroCards, child: panel)
                    : panel,
              );
            }),
        ],
      );
    });
  }

  // ── deal panel (between streets) ─────────────────────────────────────────────
  Widget _buildDealPanel() {
    final numCompleted = _completedStreets.length;
    final streetName =
        numCompleted == 1 ? 'Flop' : numCompleted == 2 ? 'Turn' : 'River';
    final runout = _isAllInRunout;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        boxShadow: [
          BoxShadow(
              color: Colors.black45, blurRadius: 8, offset: Offset(0, -2))
        ],
      ),
      padding: EdgeInsets.fromLTRB(
          12, 10, 12, 10 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (runout) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.orange.withAlpha(25),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: Colors.orange.withAlpha(80)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.all_inclusive, size: 13, color: Colors.orange),
                  SizedBox(width: 6),
                  Text('All-in — cards run out, no further betting',
                      style: TextStyle(fontSize: 11, color: Colors.orange)),
                ],
              ),
            ),
          ],
          Row(children: [
            Expanded(
              flex: 3,
              child: FilledButton.icon(
                onPressed: _dealNextStreet,
                icon: const Icon(Icons.style_outlined, size: 18),
                label: Text('Deal $streetName'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  backgroundColor: const Color(0xFF1565C0),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: _beginShowdown,
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                child: const Text('End Hand',
                    style: TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  // ── action panel ─────────────────────────────────────────────────────────────
  Widget _buildActionPanel({
    required int actingSeat,
    required HandPlayer player,
    required String position,
    required int stack,
    required int toCall,
    required bool canCheck,
    required bool canBet,
  }) {
    final theme = Theme.of(context);
    final prev = _contributions[actingSeat] ?? 0;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        boxShadow: [
          BoxShadow(
              color: Colors.black45, blurRadius: 8, offset: Offset(0, -2))
        ],
      ),
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, 8 + MediaQuery.of(context).padding.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Actor header row
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(position,
                style:
                    const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(player.name,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis),
          ),
          // Hero cards — tap to add or change
          if (player.isHero)
            GestureDetector(
              onTap: _pickHeroCards,
              child: _heroCards.isNotEmpty
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: _heroCards
                          .map((c) => Padding(
                                padding: const EdgeInsets.only(left: 2),
                                child: PlayingCard(card: c, width: 20, height: 28),
                              ))
                          .toList(),
                    )
                  : Container(
                      margin: const EdgeInsets.only(left: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white24),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('+ cards',
                          style:
                              TextStyle(fontSize: 9, color: Colors.white38)),
                    ),
            ),
          const SizedBox(width: 6),
          Text('\$$stack',
              style:
                  const TextStyle(color: Colors.white54, fontSize: 11)),
          if (!canCheck) ...[
            const SizedBox(width: 3),
            Flexible(
              child: Text('· \$$toCall',
                  style: TextStyle(
                      color: theme.colorScheme.secondary, fontSize: 11),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ]),
        const SizedBox(height: 8),

        if (!_raiseMode) ...[
          // Action buttons — FittedBox prevents overflow on small screens
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: _actionBtn(label: 'FOLD', color: const Color(0xFFD32F2F), onTap: _doFold)),
              const SizedBox(width: 6),
              Expanded(
                flex: 2,
                child: _actionBtn(
                  label: canCheck ? 'CHECK' : 'CALL \$$toCall',
                  color: const Color(0xFF388E3C),
                  onTap: canCheck ? _doCheck : _doCall,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _actionBtn(
                  label: canBet ? 'BET' : 'RAISE',
                  color: const Color(0xFFF57C00),
                  onTap: stack > toCall
                      ? () {
                          _raiseCtrl.text = _minRaise.toString();
                          setState(() => _raiseMode = true);
                        }
                      : null,
                ),
              ),
            ]),
          ),
        ] else ...[
          Row(children: [
            Expanded(
              child: TextField(
                controller: _raiseCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  prefixText: '\$',
                  labelText: canBet ? 'Bet amount' : 'Raise to',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => setState(() => _raiseMode = false),
              child: const Text('✕'),
            ),
          ]),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final lbl in [
                '1/3 pot', '½ pot', '2/3 pot', 'Pot', 'All-in'
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    label:
                        Text(lbl, style: const TextStyle(fontSize: 11)),
                    onPressed: () {
                      // Pot size = pot after the raiser calls, then raises by that amount.
                      final callAmt = _currentBet - prev;
                      final potAfterCall = _currentPot + callAmt;
                      final amt = switch (lbl) {
                        '1/3 pot' => _currentBet + (potAfterCall / 3).round(),
                        '½ pot'   => _currentBet + (potAfterCall / 2).round(),
                        '2/3 pot' => _currentBet + (potAfterCall * 2 ~/ 3),
                        'Pot'     => _currentBet + potAfterCall,
                        _         => stack + prev,
                      };
                      _raiseCtrl.text =
                          amt.clamp(_minRaise, stack + prev).toString();
                    },
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 6),
          FilledButton(
            onPressed: () {
              final amt = int.tryParse(_raiseCtrl.text) ?? _minRaise;
              _doRaise(amt.clamp(_minRaise, stack + prev));
            },
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(44)),
            child: Text(canBet ? 'Confirm Bet' : 'Confirm Raise'),
          ),
        ],
      ]),
    );
  }

  // ── step: showdown ────────────────────────────────────────────────────────────
  Widget _buildShowdown() {
    if (_showdownIdx >= _showdownOrder.length) {
      return const Center(child: CircularProgressIndicator());
    }

    final seat = _showdownOrder[_showdownIdx];
    final player = _players.firstWhere((p) => p.seatIndex == seat);
    final isHero = player.isHero;

    if (isHero) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showdownCards[seat] = _heroCards.isEmpty ? null : _heroCards;
        _advanceShowdown();
      });
      return const Center(child: CircularProgressIndicator());
    }

    final position = _setup.positionName(seat);
    final picked = _showdownCards[seat];

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Showdown', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            '${_showdownIdx + 1} of ${_showdownOrder.length} players',
            style: const TextStyle(color: Colors.white38),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(children: [
              Text('$position — ${player.name}',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              if (picked != null)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: picked
                      .map((c) => Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 4),
                            child: PlayingCard(card: c, width: 60, height: 85),
                          ))
                      .toList(),
                )
              else
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    PlayingCard(width: 60, height: 85),
                    SizedBox(width: 8),
                    PlayingCard(width: 60, height: 85),
                  ],
                ),
            ]),
          ),
          const SizedBox(height: 32),
          OutlinedButton.icon(
            onPressed: () async {
              final cards = await _pickCards(2);
              if (cards != null) setState(() => _showdownCards[seat] = cards);
            },
            icon: const Icon(Icons.style_outlined),
            label: Text(picked != null ? 'Change Cards' : 'Show Cards'),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: () => _muck(seat),
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                backgroundColor: Colors.red[900]),
            child: const Text('MUCK (fold cards)'),
          ),
          if (picked != null) ...[
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _advanceShowdown,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(44)),
              child: const Text('Confirm & Next →'),
            ),
          ],
        ]),
      ),
    );
  }

  // ── step: done ────────────────────────────────────────────────────────────────
  Widget _buildDone() {
    final hand = _savedHand;
    if (hand == null) return const Center(child: CircularProgressIndicator());

    final heroCards = hand.hero?.holeCards;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle_outline,
              size: 64, color: Color(0xFF66BB6A)),
          const SizedBox(height: 16),
          const Text('Hand recorded',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            '${_setup.numSeats}-max · \$${_setup.smallBlind}/\$${_setup.bigBlind}'
            '${_setup.straddle != null ? '/\$${_setup.straddle}' : ''}'
            ' · ${hand.streetReached}',
            style: const TextStyle(color: Colors.white54),
          ),
          const SizedBox(height: 24),
          if (heroCards != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: heroCards
                  .map((c) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: PlayingCard(card: c, width: 60, height: 85),
                      ))
                  .toList(),
            ),
          if (hand.allCommunityCards.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: hand.allCommunityCards
                  .map((c) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: PlayingCard(card: c, width: 40, height: 56),
                      ))
                  .toList(),
            ),
          ],
          const SizedBox(height: 40),
          FilledButton.icon(
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (_) => HandReplayerScreen(hand: hand)),
              );
            },
            icon: const Icon(Icons.play_circle_outline),
            label: const Text('View Hand Replay'),
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52)),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44)),
            child: const Text('Back to Hands'),
          ),
        ]),
      ),
    );
  }

  // ── helpers ───────────────────────────────────────────────────────────────────
  Widget _actionBtn({
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 46,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: onTap == null ? Colors.grey[800] : color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5)),
        ),
      ),
    );
  }

  Future<void> _confirmExit(BuildContext ctx) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Discard hand?'),
        content: const Text('This hand will not be saved.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Discard',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true && mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _raiseCtrl.dispose();
    _anteCtrl.dispose();
    _tournSbCtrl.dispose();
    _tournBbCtrl.dispose();
    for (final c in _nameCtrl) { c.dispose(); }
    for (final f in _nameFocusNodes) { f.dispose(); }
    for (final c in _stackCtrl) { c.dispose(); }
    super.dispose();
  }
}

// ── undo snapshot ─────────────────────────────────────────────────────────────

class _HandSnapshot {
  final List<HandAction> streetActions;
  final List<StreetData> completedStreets;
  final List<int> toAct;
  final List<int> activeSeats;
  final Map<int, int> runningStacks;
  final Map<int, int> contributions;
  final int currentBet;
  final Street currentStreet;
  final int pot;
  final int lastRaiseSize;
  final Set<int> allInSeats;
  final _Step step;
  final bool awaitingDeal;
  final List<String> flopCards;
  final String? turnCard;
  final String? riverCard;

  const _HandSnapshot({
    required this.streetActions,
    required this.completedStreets,
    required this.toAct,
    required this.activeSeats,
    required this.runningStacks,
    required this.contributions,
    required this.currentBet,
    required this.currentStreet,
    required this.pot,
    required this.lastRaiseSize,
    required this.allInSeats,
    required this.step,
    required this.awaitingDeal,
    required this.flopCards,
    required this.turnCard,
    required this.riverCard,
  });
}

// ── session linking widgets ────────────────────────────────────────────────────

class _LinkedSessionBanner extends StatelessWidget {
  final String? label;
  const _LinkedSessionBanner({this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.link_rounded,
              size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label != null ? 'Linked to: $label' : 'Linked to session',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionPickerTile extends ConsumerWidget {
  final String? selectedSessionId;
  final ValueChanged<String?> onChanged;

  const _SessionPickerTile({
    required this.selectedSessionId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(sessionsProvider);

    return sessionsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (sessions) {
        if (sessions.isEmpty) return const SizedBox.shrink();

        final sorted = [...sessions]
          ..sort((a, b) => b.date.compareTo(a.date));
        final recent = sorted.take(20).toList();

        final selected =
            selectedSessionId != null
                ? recent.where((s) => s.id == selectedSessionId).firstOrNull
                : null;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Link to Session (optional)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              initialValue: selectedSessionId,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              hint: const Text('None'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('None'),
                ),
                ...recent.map((s) {
                  final date = s.date.length >= 10 ? s.date.substring(0, 10) : s.date;
                  final loc = (s.location != null && s.location!.isNotEmpty)
                      ? '  ·  ${s.location}'
                      : '';
                  // Location distinguishes multiple same-day sessions at
                  // different venues.
                  final label = '$date  ·  ${s.gameType}  ·  ${s.stakes}$loc';
                  return DropdownMenuItem<String?>(
                    value: s.id,
                    child: Text(label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13)),
                  );
                }),
              ],
              onChanged: onChanged,
            ),
            if (selected != null)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  'Session: ${selected.date.substring(0, 10)}  ·  ${selected.stakes}'
                  '${selected.location != null && selected.location!.isNotEmpty ? '  ·  ${selected.location}' : ''}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ── oval table painter (recording) ─────────────────────────────────────────────
class _InputTablePainter extends CustomPainter {
  final double cx, cy, rx, ry;
  const _InputTablePainter(
      {required this.cx, required this.cy, required this.rx, required this.ry});

  @override
  void paint(Canvas canvas, Size size) {
    final railRx = rx + 18;
    final railRy = ry + 18;

    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx, cy), width: railRx * 2, height: railRy * 2),
      Paint()..color = const Color(0xFF4E2800),
    );

    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx, cy), width: rx * 2, height: ry * 2),
      Paint()
        ..shader = const RadialGradient(colors: [
          Color(0xFF1B5E20),
          Color(0xFF0A3D0A),
        ]).createShader(Rect.fromCenter(
            center: Offset(cx, cy), width: rx * 2, height: ry * 2)),
    );

    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx, cy), width: railRx * 2, height: railRy * 2),
      Paint()
        ..color = const Color(0xFF6D4C1F)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_InputTablePainter old) =>
      cx != old.cx || cy != old.cy || rx != old.rx || ry != old.ry;
}

// ── player panel widget (recording) ────────────────────────────────────────────
class _RecorderPlayerPanel extends StatelessWidget {
  final HandPlayer player;
  final String position;
  final int stack;
  final bool folded;
  final bool isActing;
  final bool isAllIn;
  final List<String>? heroCards;

  const _RecorderPlayerPanel({
    required this.player,
    required this.position,
    required this.stack,
    required this.folded,
    required this.isActing,
    this.isAllIn = false,
    this.heroCards,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = isActing
        ? const Color(0xFF1B5E20)
        : folded
            ? const Color(0xFF1A1A1A)
            : const Color(0xFF1E1E2E);
    final border = isActing
        ? const Color(0xFF66BB6A)
        : isAllIn && !folded
            ? Colors.orange.withAlpha(180)
            : player.isHero
                ? const Color(0xFF1565C0)
                : Colors.white12;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: border, width: isActing || (isAllIn && !folded) ? 2 : 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Position badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: player.isHero ? theme.colorScheme.primary : Colors.white12,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              position,
              style:
                  const TextStyle(fontSize: 8, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            folded ? 'FOLD' : player.name,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: folded ? Colors.white30 : Colors.white,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          if (!folded) ...[
            if (isAllIn)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.orange.withAlpha(40),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const Text('ALL IN',
                    style: TextStyle(
                        fontSize: 7,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange)),
              )
            else
              Text(
                stack >= 1000
                    ? '\$${(stack / 1000).toStringAsFixed(1)}k'
                    : '\$$stack',
                style: const TextStyle(fontSize: 8, color: Colors.white54),
              ),
            const SizedBox(height: 2),
            // Cards row
            if (heroCards != null && heroCards!.isNotEmpty)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: heroCards!
                    .map((c) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 1),
                          child: PlayingCard(card: c, width: 16, height: 22),
                        ))
                    .toList(),
              )
            else if (player.isHero)
              // Prompt hero to add cards
              const Text('tap to add cards',
                  style: TextStyle(fontSize: 7, color: Colors.white24),
                  textAlign: TextAlign.center)
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  PlayingCard(width: 16, height: 22),
                  SizedBox(width: 2),
                  PlayingCard(width: 16, height: 22),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

// ── card picker bottom sheet ────────────────────────────────────────────────────
class _CardPicker extends StatefulWidget {
  final int count;
  final Set<String> used;
  const _CardPicker({required this.count, required this.used});

  @override
  State<_CardPicker> createState() => _CardPickerState();
}

class _CardPickerState extends State<_CardPicker> {
  static const _ranks = [
    'A', 'K', 'Q', 'J', 'T', '9', '8', '7', '6', '5', '4', '3', '2'
  ];
  static const _suits = ['s', 'h', 'd', 'c'];
  static const _suitSymbols = {'s': '♠', 'h': '♥', 'd': '♦', 'c': '♣'};
  static const _suitColors = {
    's': Colors.white,
    'h': Color(0xFFEF5350),
    'd': Color(0xFFEF5350),
    'c': Colors.white,
  };

  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, sc) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(children: [
            Text(
              'Select ${widget.count} card${widget.count > 1 ? 's' : ''}',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            Text('${_selected.length}/${widget.count}',
                style: const TextStyle(color: Colors.white54)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [
            const SizedBox(width: 24),
            ..._suits.map((s) => Expanded(
                  child: Center(
                    child: Text(_suitSymbols[s]!,
                        style: TextStyle(
                            fontSize: 16,
                            color: _suitColors[s],
                            fontWeight: FontWeight.bold)),
                  ),
                )),
          ]),
        ),
        const Divider(height: 8),
        Expanded(
          child: ListView.builder(
            controller: sc,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: _ranks.length,
            itemBuilder: (_, ri) {
              final rank = _ranks[ri];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  SizedBox(
                    width: 24,
                    child: Text(rank == 'T' ? '10' : rank,
                        style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white54,
                            fontWeight: FontWeight.bold)),
                  ),
                  ..._suits.map((suit) {
                    final card = '$rank$suit';
                    final isUsed = widget.used.contains(card);
                    final isSel = _selected.contains(card);
                    return Expanded(
                      child: GestureDetector(
                        onTap: isUsed
                            ? null
                            : () {
                                setState(() {
                                  if (isSel) {
                                    _selected.remove(card);
                                  } else if (_selected.length <
                                      widget.count) {
                                    _selected.add(card);
                                  }
                                });
                              },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.all(2),
                          height: 44,
                          decoration: BoxDecoration(
                            color: isUsed
                                ? Colors.grey[900]
                                : isSel
                                    ? Theme.of(context).colorScheme.primary
                                    : const Color(0xFF2A2A3E),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isSel
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                rank == 'T' ? '10' : rank,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isUsed
                                      ? Colors.white12
                                      : _suitColors[suit],
                                ),
                              ),
                              Text(
                                _suitSymbols[suit]!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isUsed
                                      ? Colors.white12
                                      : _suitColors[suit],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ]),
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: FilledButton(
              onPressed: _selected.length == widget.count
                  ? () => Navigator.pop(context, _selected.toList())
                  : null,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48)),
              child: Text(
                _selected.length == widget.count
                    ? 'Confirm — ${_selected.join(' ')}'
                    : 'Select ${widget.count - _selected.length} more',
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
