import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/hand_model.dart';
import '../../models/session_model.dart';
import '../../providers/providers.dart';
import '../../widgets/playing_card_widget.dart';
import '../../widgets/chip_stack_widget.dart';
import '../../theme/app_theme.dart';
import '../ai_analysis/hand_analysis_screen.dart';

// ── Replay data model ─────────────────────────────────────────────────────────

class _SeatState {
  final int seatIndex;
  final String name;
  final String position;
  final int stack;
  final int betThisStreet;
  final bool folded;
  final bool isAllIn;
  final List<String>? cards;
  final bool isHero;

  const _SeatState({
    required this.seatIndex,
    required this.name,
    required this.position,
    required this.stack,
    required this.betThisStreet,
    required this.folded,
    required this.isAllIn,
    this.cards,
    required this.isHero,
  });

  _SeatState copyWith({
    int? stack,
    int? betThisStreet,
    bool? folded,
    bool? isAllIn,
    List<String>? cards,
  }) =>
      _SeatState(
        seatIndex: seatIndex,
        name: name,
        position: position,
        stack: stack ?? this.stack,
        betThisStreet: betThisStreet ?? this.betThisStreet,
        folded: folded ?? this.folded,
        isAllIn: isAllIn ?? this.isAllIn,
        cards: cards ?? this.cards,
        isHero: isHero,
      );
}

class _Frame {
  final Map<int, _SeatState> seats;
  final List<String> communityCards;
  final int pot;
  final String message;
  final String streetLabel;
  final int? highlightedSeat;
  final String? actionLabel;

  const _Frame({
    required this.seats,
    required this.communityCards,
    required this.pot,
    required this.message,
    required this.streetLabel,
    this.highlightedSeat,
    this.actionLabel,
  });
}

// ── Screen ────────────────────────────────────────────────────────────────────

class HandReplayerScreen extends ConsumerStatefulWidget {
  final PokerHand hand;

  const HandReplayerScreen({super.key, required this.hand});

  @override
  ConsumerState<HandReplayerScreen> createState() => _HandReplayerScreenState();
}

class _HandReplayerScreenState extends ConsumerState<HandReplayerScreen> {
  late final List<_Frame> _frames;
  int _currentIndex = 0;
  bool _isPlaying = false;
  double _speed = 1.0;
  Timer? _timer;
  late String? _sessionId;

  @override
  void initState() {
    super.initState();
    _frames = _buildFrames();
    _sessionId = widget.hand.sessionId;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ── Frame construction ────────────────────────────────────────────────────

  List<_Frame> _buildFrames() {
    final hand = widget.hand;
    final setup = hand.tableSetup;
    final frames = <_Frame>[];

    var seats = <int, _SeatState>{};
    for (final p in hand.players) {
      seats[p.seatIndex] = _SeatState(
        seatIndex: p.seatIndex,
        name: p.name,
        position: setup.positionName(p.seatIndex),
        stack: p.startingStack,
        betThisStreet: 0,
        folded: false,
        isAllIn: false,
        cards: p.isHero ? p.holeCards : null,
        isHero: p.isHero,
      );
    }

    int potCollected = 0;
    final communityCards = <String>[];

    int currentPot() =>
        potCollected + seats.values.fold(0, (s, v) => s + v.betThisStreet);

    void addFrame(
      String msg,
      String streetLabel, {
      int? highlightedSeat,
      String? actionLabel,
    }) {
      frames.add(_Frame(
        seats: Map.fromEntries(seats.entries),
        communityCards: List.from(communityCards),
        pot: currentPot(),
        message: msg,
        streetLabel: streetLabel,
        highlightedSeat: highlightedSeat,
        actionLabel: actionLabel,
      ));
    }

    final isTournament = hand.tournamentStage != null || setup.ante != null;
    final heroStartStack = hand.players
        .where((p) => p.isHero)
        .map((p) => p.startingStack)
        .firstOrNull;
    final heroEffBb = (heroStartStack != null && setup.bigBlind > 0)
        ? heroStartStack ~/ setup.bigBlind
        : null;

    addFrame(
      isTournament
          ? 'Hand starts · ${setup.numSeats}-max · ${setup.smallBlind}/${setup.bigBlind}'
              '${setup.ante != null ? ' ante ${setup.ante}' : ''}'
              '${heroEffBb != null ? ' · Hero ${heroEffBb}bb' : ''}'
          : 'Hand starts · ${setup.numSeats}-max · '
              '\$${setup.smallBlind}/\$${setup.bigBlind}'
              '${setup.straddle != null ? '/\$${setup.straddle}' : ''}',
      'Pre-flop',
    );

    for (final streetData in hand.streets) {
      final streetLabel = streetData.street.label;

      // New street: collect bets, show community cards
      if (streetData.communityCards.isNotEmpty) {
        potCollected += seats.values.fold(0, (s, v) => s + v.betThisStreet);
        seats = seats.map(
          (k, v) => MapEntry(k, v.copyWith(betThisStreet: 0)),
        );
        communityCards.addAll(streetData.communityCards);
        addFrame('$streetLabel dealt', streetLabel);
      }

      for (final action in streetData.actions) {
        final seat = action.seat;
        final prev = seats[seat]!;
        final amt = action.amount ?? 0;

        switch (action.type) {
          case ActionType.post:
          case ActionType.postStraddle:
            seats[seat] = prev.copyWith(
              stack: prev.stack - amt,
              betThisStreet: prev.betThisStreet + amt,
            );
            break;
          case ActionType.fold:
            seats[seat] = prev.copyWith(folded: true);
            break;
          case ActionType.check:
            // no state change
            break;
          case ActionType.call:
            // amt is the total street contribution (not the additional amount)
            final additional = (amt - prev.betThisStreet).clamp(0, prev.stack);
            seats[seat] = prev.copyWith(
              stack: prev.stack - additional,
              betThisStreet: amt,
              isAllIn: action.isAllIn,
            );
            break;
          case ActionType.raise:
          case ActionType.allIn:
            // amt is the new total bet level
            final additional = (amt - prev.betThisStreet).clamp(0, prev.stack);
            seats[seat] = prev.copyWith(
              stack: prev.stack - additional,
              betThisStreet: amt,
              isAllIn: action.isAllIn,
            );
            break;
        }

        final bbAnnotation = (isTournament && action.amount != null && action.amount! > 0)
            ? ' (${(action.amount! / setup.bigBlind).round()}bb)'
            : '';
        addFrame(
          '${setup.positionName(seat)} ${action.label}$bbAnnotation',
          streetLabel,
          highlightedSeat: seat,
          actionLabel: action.label,
        );
      }
    }

    // Showdown: reveal any shown cards
    for (final p in hand.players) {
      if (!p.isHero && p.holeCards != null && p.holeCards!.isNotEmpty) {
        seats[p.seatIndex] = seats[p.seatIndex]!.copyWith(cards: p.holeCards);
      }
    }
    addFrame('Hand complete', 'Showdown');

    return frames;
  }

  // ── Playback ──────────────────────────────────────────────────────────────

  void _prev() =>
      setState(() => _currentIndex = (_currentIndex - 1).clamp(0, _frames.length - 1));

  void _next() {
    setState(() {
      _currentIndex = (_currentIndex + 1).clamp(0, _frames.length - 1);
    });
    if (_currentIndex == _frames.length - 1) _stopPlay();
  }

  void _togglePlay() => _isPlaying ? _stopPlay() : _startPlay();

  void _startPlay() {
    if (_currentIndex >= _frames.length - 1) return;
    setState(() => _isPlaying = true);
    _timer = Timer.periodic(
      Duration(milliseconds: (1200 / _speed).round()),
      (_) {
        if (_currentIndex < _frames.length - 1) {
          setState(() => _currentIndex++);
        } else {
          _stopPlay();
        }
      },
    );
  }

  void _stopPlay() {
    _timer?.cancel();
    _timer = null;
    if (mounted) setState(() => _isPlaying = false);
  }

  void _setSpeed(double s) {
    final wasPlaying = _isPlaying;
    _stopPlay();
    setState(() => _speed = s);
    if (wasPlaying) _startPlay();
  }

  // ── Geometry helpers ──────────────────────────────────────────────────────

  int _displayIndex(int seatIndex) {
    final setup = widget.hand.tableSetup;
    return (seatIndex - setup.heroSeat + setup.numSeats) % setup.numSeats;
  }

  // Clockwise from bottom in Flutter coords (y-down)
  double _angle(int seatIndex, int total) {
    return pi / 2 + (2 * pi * _displayIndex(seatIndex) / total);
  }

  Offset _seatPos(int seatIndex, int total, double cx, double cy, double rx, double ry) {
    final a = _angle(seatIndex, total);
    return Offset(cx + rx * cos(a), cy + ry * sin(a));
  }

  Offset _betPos(int seatIndex, int total, double cx, double cy, double rx, double ry) {
    final a = _angle(seatIndex, total);
    return Offset(cx + rx * 0.38 * cos(a), cy + ry * 0.38 * sin(a));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) =>
      // Immersive felt-table playback — always dark, independent of app theme.
      Theme(data: AppTheme.dark, child: _build(context));

  Widget _build(BuildContext context) {
    final frame = _frames[_currentIndex];
    final setup = widget.hand.tableSetup;
    final total = setup.numSeats;
    final seatList = frame.seats.values.toList()
      ..sort((a, b) => a.seatIndex.compareTo(b.seatIndex));

    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${frame.streetLabel} · $total-max',
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            if (widget.hand.tournamentStage != null)
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.amber.withAlpha(40),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: Colors.amber.withAlpha(120), width: 0.5),
                ),
                child: Text(
                  _stageBadgeLabel(widget.hand.tournamentStage!),
                  style: const TextStyle(
                      fontSize: 10,
                      color: Colors.amber,
                      fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome, size: 20),
            tooltip: 'AI Coaching',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => HandAnalysisScreen(hand: widget.hand),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined, size: 20),
            tooltip: 'Share hand',
            onPressed: _shareHand,
          ),
          IconButton(
            icon: Icon(
              Icons.link,
              size: 20,
              color: _sessionId != null ? Colors.green.shade400 : Colors.white54,
            ),
            tooltip: _sessionId != null ? 'Linked to session (tap to change)' : 'Link to session',
            onPressed: _showLinkSheet,
          ),
          if (widget.hand.notes?.isNotEmpty == true)
            IconButton(
              icon: const Icon(Icons.note_outlined, size: 20),
              onPressed: () => _showNotes(context),
            ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Action message ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            color: const Color(0xFF191919),
            child: Text(
              frame.message,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.green.shade300,
              ),
            ),
          ),
          // ── Controls ──
          Container(
            color: const Color(0xFF1C1C1C),
            child: SafeArea(
              top: false,
              left: false,
              right: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    Text(
                      '${_currentIndex + 1} / ${_frames.length}',
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.skip_previous_rounded, size: 28),
                      color: _currentIndex > 0 ? Colors.white70 : Colors.white24,
                      onPressed: _currentIndex > 0 ? _prev : null,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                    IconButton(
                      icon: Icon(
                        _isPlaying
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_filled,
                        size: 42,
                      ),
                      color: _currentIndex < _frames.length - 1
                          ? Colors.green.shade400
                          : Colors.white24,
                      onPressed: _currentIndex < _frames.length - 1
                          ? _togglePlay
                          : null,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 48, minHeight: 48),
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next_rounded, size: 28),
                      color: _currentIndex < _frames.length - 1
                          ? Colors.white70
                          : Colors.white24,
                      onPressed:
                          _currentIndex < _frames.length - 1 ? _next : null,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                    const Spacer(),
                    _SpeedBtn(speed: 0.5, current: _speed, onTap: _setSpeed),
                    const SizedBox(width: 4),
                    _SpeedBtn(speed: 1.0, current: _speed, onTap: _setSpeed),
                    const SizedBox(width: 4),
                    _SpeedBtn(speed: 2.0, current: _speed, onTap: _setSpeed),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(builder: (ctx, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final cx = w / 2;
        final cy = h / 2;
        final panelW = total > 6 ? 76.0 : 86.0;
        final panelH = total > 6 ? 92.0 : 96.0;
        final rx = (w * 0.36).clamp(0.0, (w - panelW) / 2 - 2);
        final ry = (h * 0.33).clamp(0.0, (h - panelH) / 2 - 2);

        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // Felt background
            CustomPaint(
              size: Size(w, h),
              painter: _TablePainter(cx: cx, cy: cy, rx: rx, ry: ry),
            ),

            // Center: community cards + pot
            Align(
              alignment: Alignment.center,
              child: SizedBox(
                width: (w - panelW * 2 - 16).clamp(160.0, 260.0),
                child: _CenterPanel(
                  pot: frame.pot,
                  communityCards: frame.communityCards,
                ),
              ),
            ),

            // Bet chips (inner ring) — positions clamped to screen
            for (final s in seatList)
              if (s.betThisStreet > 0 && !s.folded)
                Builder(builder: (_) {
                  final pos = _betPos(s.seatIndex, total, cx, cy, rx, ry);
                  return Positioned(
                    left: (pos.dx - 14).clamp(0.0, w - 30.0),
                    top: (pos.dy - 28).clamp(0.0, h - 46.0),
                    child: ChipStack(
                      amount: s.betThisStreet,
                      bigBlind: setup.bigBlind,
                      isAllIn: s.isAllIn,
                      chipDiameter: 16,
                    ),
                  );
                }),

            // Player panels — positions clamped to screen
            for (final s in seatList)
              Builder(builder: (_) {
                final pos = _seatPos(s.seatIndex, total, cx, cy, rx, ry);
                final isHighlighted = frame.highlightedSeat == s.seatIndex;
                return Positioned(
                  left: (pos.dx - panelW / 2).clamp(0.0, w - panelW),
                  top: (pos.dy - panelH / 2).clamp(0.0, h - panelH),
                  width: panelW,
                  height: panelH,
                  child: _PlayerPanel(
                    state: s,
                    isHighlighted: isHighlighted,
                    actionLabel: isHighlighted ? frame.actionLabel : null,
                  ),
                );
              }),
          ],
        );
      }),
    );
  }

  // ── Link to session ───────────────────────────────────────────────────────

  Future<void> _showLinkSheet() async {
    final sessions = ref.read(sessionsProvider).valueOrNull ?? [];
    if (sessions.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No sessions saved yet. Log a session first.')),
        );
      }
      return;
    }
    final sorted = [...sessions]..sort((a, b) => b.date.compareTo(a.date));
    final recent = sorted.take(20).toList();

    final result = await showModalBottomSheet<_LinkPick>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SessionLinkSheet(
        sessions: recent,
        currentSessionId: _sessionId,
      ),
    );

    if (result == null || !mounted) return;

    try {
      await ref
          .read(handServiceProvider)
          .updateHandSession(widget.hand.id, result.sessionId);
      if (!mounted) return;
      setState(() => _sessionId = result.sessionId);
      ref.invalidate(handsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.sessionId == null
              ? 'Session link removed.'
              : 'Hand linked to session.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update: $e')),
      );
    }
  }

  // ── Share ─────────────────────────────────────────────────────────────────

  Future<void> _shareHand() async {
    await SharePlus.instance.share(ShareParams(
      subject: 'Poker Hand',
      text: _formatHandAsText(),
    ));
  }

  String _formatHandAsText() {
    final hand = widget.hand;
    final setup = hand.tableSetup;
    final dt = hand.playedAt.toLocal();
    final dateStr =
        '${_monthName(dt.month)} ${dt.day}, ${dt.year}  '
        '${_hour12(dt.hour)}:${dt.minute.toString().padLeft(2, '0')} '
        '${dt.hour < 12 ? 'AM' : 'PM'}';

    final buf = StringBuffer();
    final stakes = '\$${setup.smallBlind}/\$${setup.bigBlind}'
        '${setup.straddle != null ? '/\$${setup.straddle}' : ''}';

    buf.writeln('Poker Hand — $stakes NL Hold\'em — ${setup.numSeats}-max');
    buf.writeln('Date: $dateStr');
    buf.writeln();

    for (final p in hand.players) {
      final heroMark = p.isHero ? ' ← Hero' : '';
      buf.writeln(
          '${setup.positionName(p.seatIndex)}: ${p.name} (\$${p.startingStack})$heroMark');
    }
    buf.writeln();

    final boardSoFar = <String>[];
    int runningPot = 0;

    for (final street in hand.streets) {
      boardSoFar.addAll(street.communityCards);

      if (street.street == Street.preflop) {
        buf.writeln('*** PRE-FLOP ***');
      } else {
        buf.writeln(
            '*** ${street.street.label.toUpperCase()} *** [${boardSoFar.join(' ')}]'
            '  ·  Pot: \$$runningPot');
      }

      for (final a in street.actions) {
        buf.writeln('  ${setup.positionName(a.seat)}: ${a.label}');
      }
      buf.writeln();

      // Accumulate pot: each seat's maximum contribution this street
      final seatMax = <int, int>{};
      for (final a in street.actions) {
        if (a.amount != null && a.amount! > (seatMax[a.seat] ?? 0)) {
          seatMax[a.seat] = a.amount!;
        }
      }
      runningPot += seatMax.values.fold(0, (s, v) => s + v);
    }

    final shown =
        hand.players.where((p) => p.holeCards?.isNotEmpty == true).toList();
    if (shown.isNotEmpty) {
      buf.writeln('*** SHOWDOWN ***  ·  Pot: \$$runningPot');
      for (final p in shown) {
        final heroMark = p.isHero ? ' (Hero)' : '';
        buf.writeln(
            '  ${setup.positionName(p.seatIndex)} ${p.name}$heroMark: [${p.holeCards!.join(' ')}]');
      }
      buf.writeln();
    }

    if (hand.notes?.isNotEmpty == true) {
      buf.writeln('Notes: ${hand.notes}');
    }

    return buf.toString().trim();
  }

  static String _monthName(int m) {
    const n = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return n[m];
  }

  static int _hour12(int h) => h == 0 ? 12 : h > 12 ? h - 12 : h;

  static String _stageBadgeLabel(String stage) => switch (stage) {
        'early' => 'EARLY STAGES',
        'middle' => 'MIDDLE STAGES',
        'late' => 'LATE STAGES',
        'bubble' => 'BUBBLE',
        'itm' => 'IN THE MONEY',
        'ft_bubble' => 'FT BUBBLE',
        'final_table' => 'FINAL TABLE',
        _ => stage.toUpperCase(),
      };

  void _showNotes(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Notes'),
        content: Text(widget.hand.notes!),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

// ── Subwidgets ─────────────────────────────────────────────────────────────────

class _TablePainter extends CustomPainter {
  final double cx, cy, rx, ry;

  const _TablePainter({
    required this.cx,
    required this.cy,
    required this.rx,
    required this.ry,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Rail (wood-toned outer band)
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, cy),
        width: (rx + 24) * 2,
        height: (ry + 24) * 2,
      ),
      Paint()
        ..color = const Color(0xFF3E2723)
        ..style = PaintingStyle.fill,
    );

    // Felt (green inner)
    final feltRect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: rx * 2,
      height: ry * 2,
    );
    canvas.drawOval(
      feltRect,
      Paint()
        ..shader = RadialGradient(
          colors: const [Color(0xFF2E7D32), Color(0xFF1B5E20)],
          center: Alignment.topCenter,
          radius: 1.2,
        ).createShader(feltRect)
        ..style = PaintingStyle.fill,
    );

    // Rail highlight ring
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, cy),
        width: (rx + 24) * 2,
        height: (ry + 24) * 2,
      ),
      Paint()
        ..color = const Color(0xFF6D4C41).withAlpha(160)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Inner felt glow line
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, cy),
        width: (rx - 10) * 2,
        height: (ry - 10) * 2,
      ),
      Paint()
        ..color = Colors.white.withAlpha(14)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_TablePainter old) => false;
}

class _CenterPanel extends StatelessWidget {
  final int pot;
  final List<String> communityCards;

  const _CenterPanel({required this.pot, required this.communityCards});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (communityCards.isNotEmpty) ...[
          LayoutBuilder(builder: (ctx, constraints) {
            final n = communityCards.length;
            // Scale cards down so all n cards fit within available width
            final cardW =
                ((constraints.maxWidth - n * 4) / n).clamp(20.0, 33.0);
            final cardH = (cardW * 46 / 33).roundToDouble();
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: communityCards
                  .map((c) => Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 2),
                        child:
                            PlayingCard(card: c, width: cardW, height: cardH),
                      ))
                  .toList(),
            );
          }),
          const SizedBox(height: 6),
        ],
        if (pot > 0)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white12),
            ),
            child: Text(
              'POT  \$$pot',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
                letterSpacing: 0.8,
              ),
            ),
          ),
      ],
    );
  }
}

class _PlayerPanel extends StatelessWidget {
  final _SeatState state;
  final bool isHighlighted;
  final String? actionLabel;

  const _PlayerPanel({
    required this.state,
    required this.isHighlighted,
    this.actionLabel,
  });

  String _fmt(int v) =>
      v >= 1000 ? '\$${(v / 1000).toStringAsFixed(1)}k' : '\$$v';

  @override
  Widget build(BuildContext context) {
    final dimmed = state.folded;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: dimmed
            ? Colors.black26
            : isHighlighted
                ? const Color(0xFF1B5E20).withAlpha(220)
                : Colors.black.withAlpha(185),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: dimmed
              ? Colors.white10
              : isHighlighted
                  ? Colors.green.shade400
                  : state.isHero
                      ? Colors.blue.shade700
                      : Colors.white24,
          width: isHighlighted ? 2 : 1,
        ),
        boxShadow: isHighlighted
            ? [
                BoxShadow(
                  color: Colors.green.shade800.withAlpha(150),
                  blurRadius: 12,
                  spreadRadius: 1,
                )
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Position badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: state.isHero ? Colors.blue.shade900 : Colors.white10,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  state.position,
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: state.isHero ? Colors.blue.shade300 : Colors.white60,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              // Name
              Text(
                state.name,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: dimmed ? Colors.white38 : Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              const SizedBox(height: 2),
              // Cards
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  PlayingCard(
                    card: dimmed ? null : state.cards?.isNotEmpty == true ? state.cards![0] : null,
                    width: 22,
                    height: 30,
                  ),
                  const SizedBox(width: 2),
                  PlayingCard(
                    card: dimmed
                        ? null
                        : state.cards?.length == 2
                            ? state.cards![1]
                            : null,
                    width: 22,
                    height: 30,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              // Action label or stack
              if (isHighlighted && actionLabel != null)
                _ActionBadge(label: actionLabel!)
              else if (dimmed)
                Text(
                  'FOLD',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade400,
                  ),
                )
              else
                Text(
                  _fmt(state.stack),
                  style: const TextStyle(fontSize: 9, color: Colors.white54),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionBadge extends StatelessWidget {
  final String label;

  const _ActionBadge({required this.label});

  Color get _color {
    if (label.startsWith('FOLD')) return Colors.red.shade300;
    if (label == 'CHECK') return Colors.white60;
    if (label.startsWith('ALL-IN')) return Colors.amber.shade300;
    if (label.startsWith('POST') || label.startsWith('STRADDLE')) {
      return Colors.orange.shade300;
    }
    return Colors.green.shade300;
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: _color.withAlpha(28),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _color.withAlpha(90), width: 0.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.bold,
            color: _color,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      );
}

// ── Session link sheet ────────────────────────────────────────────────────────

class _LinkPick {
  final String? sessionId;
  const _LinkPick(this.sessionId);
}

class _SessionLinkSheet extends StatelessWidget {
  final List<SessionModel> sessions;
  final String? currentSessionId;

  const _SessionLinkSheet({
    required this.sessions,
    required this.currentSessionId,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.85,
      builder: (ctx, scrollController) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Text(
              'Link to Session',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.link_off_outlined, color: Colors.white38, size: 20),
            title: const Text('None (remove link)'),
            selected: currentSessionId == null,
            selectedTileColor: Colors.white10,
            onTap: () => Navigator.of(ctx).pop(const _LinkPick(null)),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: sessions.length,
              itemBuilder: (_, i) {
                final s = sessions[i];
                final isLinked = s.id == currentSessionId;
                final date = s.date.length >= 10 ? s.date.substring(0, 10) : s.date;
                final pl = s.profitLoss;
                final plStr =
                    '${pl >= 0 ? '+' : ''}${pl.abs().toStringAsFixed(0)} ${s.currency}';
                // Location helps distinguish same-day sessions at different venues.
                final locPart = (s.location != null && s.location!.isNotEmpty)
                    ? '${s.location}  ·  '
                    : '';
                return ListTile(
                  leading: Icon(
                    isLinked ? Icons.link : Icons.calendar_today_outlined,
                    size: 18,
                    color: isLinked ? Colors.green.shade400 : Colors.white38,
                  ),
                  title: Text(
                    '$date · ${s.stakes} · ${s.gameType}',
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '$locPart$plStr',
                    style: TextStyle(
                      fontSize: 12,
                      color: pl >= 0 ? Colors.green.shade300 : Colors.red.shade300,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: isLinked
                      ? Icon(Icons.check, color: Colors.green.shade400, size: 16)
                      : null,
                  selected: isLinked,
                  selectedTileColor: Colors.white10,
                  onTap: () => Navigator.of(ctx).pop(_LinkPick(s.id)),
                );
              },
            ),
          ),
          SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
        ],
      ),
    );
  }
}

class _SpeedBtn extends StatelessWidget {
  final double speed;
  final double current;
  final void Function(double) onTap;

  const _SpeedBtn({
    required this.speed,
    required this.current,
    required this.onTap,
  });

  String get _label {
    if (speed == 0.5) return '½x';
    if (speed == 1.0) return '1x';
    if (speed == 2.0) return '2x';
    return '${speed}x';
  }

  @override
  Widget build(BuildContext context) {
    final selected = (speed - current).abs() < 0.01;
    return GestureDetector(
      onTap: () => onTap(speed),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? Colors.green.shade900 : Colors.white10,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? Colors.green.shade600 : Colors.transparent,
          ),
        ),
        child: Text(
          _label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? Colors.green.shade300 : Colors.white54,
          ),
        ),
      ),
    );
  }
}
