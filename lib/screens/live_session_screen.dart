import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/poker_rooms.dart';
import '../models/session_model.dart';
import '../providers/providers.dart';
import '../services/analytics_service.dart';
import '../services/supabase_service.dart';
import '../utils/helpers.dart';
import '../widgets/expense_dialog.dart';
import 'hand_input/record_hand_sheet.dart';
import 'log_session_screen.dart';
import 'session_detail_screen.dart';

String _formatElapsed(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$h:$m:$s';
}

String _sessionLabel(SessionModel s) {
  final date = s.date.length >= 10 ? s.date.substring(0, 10) : s.date;
  final stakes = s.stakes == 'N/A' ? s.gameType : s.stakes;
  return '$date · $stakes';
}

/// Entry chooser shown by the "Log Session" FAB. Offers the live recorder and
/// the classic post-hoc form; if a session is already live it resumes that
/// instead of allowing a second concurrent live session.
Future<void> showLogSessionChooser(BuildContext context, WidgetRef ref) async {
  final live = ref.read(liveSessionProvider).valueOrNull;

  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          if (live != null)
            ListTile(
              leading: const Icon(Icons.circle, color: Colors.red, size: 14),
              title: const Text('Resume live session'),
              subtitle: Text(_sessionLabel(live)),
              onTap: () => Navigator.pop(ctx, 'resume'),
            )
          else
            ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: const Text('Start live session'),
              subtitle: const Text('Running clock, rebuys, hands as you play'),
              onTap: () => Navigator.pop(ctx, 'live'),
            ),
          ListTile(
            leading: const Icon(Icons.edit_note),
            title: const Text('Log a past session'),
            subtitle: const Text('Enter buy-in, cash-out and times by hand'),
            onTap: () => Navigator.pop(ctx, 'past'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  if (choice == null || !context.mounted) return;
  switch (choice) {
    case 'resume':
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const LiveSessionScreen()));
    case 'live':
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const LiveSessionStartScreen()));
    case 'past':
      Navigator.push(
          context, MaterialPageRoute(builder: (_) => const LogSessionScreen()));
  }
}

/// A "Live now" banner shown atop the Sessions list and Stats overview while a
/// session is in progress. Renders nothing when there is no live session.
class LiveSessionCard extends ConsumerWidget {
  const LiveSessionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(liveSessionProvider).valueOrNull;
    if (live == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Material(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: const Icon(Icons.circle, color: Colors.red, size: 14),
          title: const Text('Live session in progress',
              style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            '${_sessionLabel(live)}'
            '${live.location != null && live.location!.isNotEmpty ? ' · ${live.location}' : ''}',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const LiveSessionScreen()),
          ),
        ),
      ),
    );
  }
}

// ─── Start form ───────────────────────────────────────────────────────────────

class LiveSessionStartScreen extends ConsumerStatefulWidget {
  const LiveSessionStartScreen({super.key});

  @override
  ConsumerState<LiveSessionStartScreen> createState() =>
      _LiveSessionStartScreenState();
}

class _LiveSessionStartScreenState
    extends ConsumerState<LiveSessionStartScreen> {
  final _formKey = GlobalKey<FormState>();
  String _gameType = 'cash';
  String _selectedStake = kStakeOptions[0];
  bool _isCustomStake = false;
  final _customStakeCtrl = TextEditingController();
  final _buyInCtrl = TextEditingController();
  String _locationName = '';
  String _currency = 'CAD';
  String? _country;
  int? _tableSize;
  bool _submitted = false;
  bool _saving = false;

  bool get _isTournament => _gameType == 'tournament';

  @override
  void dispose() {
    _customStakeCtrl.dispose();
    _buyInCtrl.dispose();
    super.dispose();
  }

  Future<void> _selectLocation() async {
    final result = await showDialog<(PokerRoom?, String)>(
      context: context,
      builder: (_) => LocationPickerDialog(currentKey: _locationName),
    );
    if (result == null) return;
    final (room, name) = result;
    setState(() {
      _locationName = name;
      if (room != null) {
        _currency = room.currency;
        _country = room.country;
      }
    });
  }

  Future<void> _start() async {
    setState(() => _submitted = true);
    if (_locationName.isEmpty) return;
    if (!_formKey.currentState!.validate()) return;
    if (_saving) return;

    // One live session at a time — guard against a stale second start.
    if (ref.read(liveSessionProvider).valueOrNull != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('A live session is already in progress.')));
      return;
    }

    setState(() => _saving = true);
    final now = DateTime.now();
    final buyIn = double.parse(_buyInCtrl.text);
    final stakesVal = _isTournament
        ? 'N/A'
        : (_isCustomStake ? _customStakeCtrl.text.trim() : _selectedStake);
    final nowIso = now.toIso8601String();

    final data = {
      'date': DateFormat('yyyy-MM-dd').format(now),
      'stakes': stakesVal,
      'game_type': _gameType,
      'buy_in': buyIn,
      'cash_out': 0,
      'profit_loss': 0,
      'start_time': formatClockTime(now),
      'end_time': formatClockTime(now),
      'duration_minutes': 0,
      'location': _locationName,
      'created_at': nowIso,
      'currency': _currency,
      'country': _country,
      'table_size': _isTournament ? null : _tableSize,
      'status': 'live',
      // started_at is a timestamptz used for the elapsed clock + finalize
      // duration, so it must be a true UTC instant. A naive local string
      // (toIso8601String on a local DateTime has no offset) gets reinterpreted
      // as UTC by Postgres, skewing the clock by the local offset.
      'started_at': now.toUtc().toIso8601String(),
      'buyin_events': [
        {'amount': buyIn, 'ts': nowIso, 'kind': 'buyin'}
      ],
    };

    try {
      await ref.read(supabaseServiceProvider).insertSessionReturningId(data);
      AnalyticsService.liveSessionStarted(
        gameType: _gameType,
        currency: _currency,
      );
      ref.invalidate(sessionsProvider);
      if (!mounted) return;
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const LiveSessionScreen()));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start session: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sym = currencySymbol(_currency);

    return Scaffold(
      appBar: AppBar(title: const Text('Start Live Session')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'cash', label: Text('Cash Game')),
                ButtonSegment(value: 'tournament', label: Text('Tournament')),
              ],
              selected: {_gameType},
              onSelectionChanged: (v) => setState(() => _gameType = v.first),
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
            ),
            const SizedBox(height: 16),

            // Location (required)
            InkWell(
              onTap: _selectLocation,
              borderRadius: BorderRadius.circular(4),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Location',
                  border: const OutlineInputBorder(),
                  suffixIcon: const Icon(Icons.search),
                  errorText: (_submitted && _locationName.isEmpty)
                      ? 'Select a location'
                      : null,
                ),
                child: Text(
                  _locationName.isEmpty
                      ? 'Select poker room...'
                      : _locationName,
                  style: _locationName.isEmpty
                      ? theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.outline)
                      : theme.textTheme.bodyMedium,
                ),
              ),
            ),
            const SizedBox(height: 16),

            DropdownButtonFormField<String>(
              key: ValueKey(_currency),
              initialValue: _currency,
              decoration: const InputDecoration(
                labelText: 'Currency',
                border: OutlineInputBorder(),
              ),
              items: kCurrencies
                  .map((c) => DropdownMenuItem(
                      value: c, child: Text('$c  (${currencySymbol(c)})')))
                  .toList(),
              onChanged: (v) => setState(() => _currency = v!),
            ),
            const SizedBox(height: 16),

            if (!_isTournament) ...[
              DropdownButtonFormField<String>(
                key: ValueKey(_selectedStake),
                initialValue: _selectedStake,
                decoration: const InputDecoration(
                  labelText: 'Stakes',
                  border: OutlineInputBorder(),
                ),
                items: kStakeOptions
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setState(() {
                  _selectedStake = v!;
                  _isCustomStake = v == 'Other';
                }),
              ),
              if (_isCustomStake) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _customStakeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Custom Stakes',
                    hintText: 'e.g. 3/6',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (_isCustomStake && (v == null || v.trim().isEmpty))
                          ? 'Enter stakes'
                          : null,
                ),
              ],
              const SizedBox(height: 16),
              DropdownButtonFormField<int?>(
                key: ValueKey(_tableSize),
                initialValue: _tableSize,
                decoration: const InputDecoration(
                  labelText: 'Table Size (optional)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Not specified',
                        style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.75))),
                  ),
                  for (var n = 2; n <= 9; n++)
                    DropdownMenuItem<int?>(
                        value: n, child: Text(tableSizeLabel(n))),
                ],
                onChanged: (v) => setState(() => _tableSize = v),
              ),
              const SizedBox(height: 16),
            ],

            TextFormField(
              controller: _buyInCtrl,
              autofocus: false,
              decoration: InputDecoration(
                labelText: _isTournament ? 'Buy-in (entry fee)' : 'Buy-in',
                prefixText: '$sym ',
                border: const OutlineInputBorder(),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                final n = double.tryParse(v);
                if (n == null) return 'Invalid';
                if (n <= 0) return 'Must be > 0';
                return null;
              },
            ),
            const SizedBox(height: 24),

            FilledButton.icon(
              onPressed: _saving ? null : _start,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              icon: const Icon(Icons.play_arrow),
              label: Text(_saving ? 'Starting…' : 'Start Session'),
            ),
            const SizedBox(height: 8),
            Text(
              'The clock starts now. You can add rebuys, your current stack, '
              'and record hands while you play, then cash out at the end.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Live screen ──────────────────────────────────────────────────────────────

class LiveSessionScreen extends ConsumerStatefulWidget {
  const LiveSessionScreen({super.key});

  @override
  ConsumerState<LiveSessionScreen> createState() => _LiveSessionScreenState();
}

class _LiveSessionScreenState extends ConsumerState<LiveSessionScreen> {
  Timer? _timer;
  final _stackCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _busy = false;
  bool _leaving = false; // suppress auto-pop while navigating away on end

  @override
  void initState() {
    super.initState();
    // Tick the elapsed clock once a second (local only — no DB traffic).
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stackCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  SupabaseService get _service => ref.read(supabaseServiceProvider);

  Future<void> _persist(SessionModel s, Map<String, dynamic> data) async {
    setState(() => _busy = true);
    try {
      await _service.updateSession(s.id, data);
      ref.invalidate(sessionsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Update failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addBuyin(SessionModel s, String kind) async {
    final amount = await _promptAmount(
      title: kind == 'rebuy' ? 'Add rebuy' : 'Add add-on',
      currency: s.currency,
    );
    if (amount == null || amount <= 0) return;
    final now = DateTime.now();
    final events = [
      ...s.buyinEvents.map((e) => e.toJson()),
      {'amount': amount, 'ts': now.toIso8601String(), 'kind': kind},
    ];
    await _persist(s, {
      'buyin_events': events,
      'buy_in': s.totalBuyIn + amount,
    });
  }

  Future<void> _addExpense(SessionModel s) async {
    final expense = await showExpenseDialog(context, s.currency);
    if (expense == null) return;
    final events = [
      ...s.expenseEvents.map((e) => e.toJson()),
      expense.toJson(),
    ];
    await _persist(s, {'expense_events': events});
  }

  Future<void> _toggleBreak(SessionModel s) async {
    if (s.isOnBreak) {
      // Resume: bank the elapsed break time.
      final mins = DateTime.now().difference(s.breakStartedAt!).inMinutes;
      await _persist(s, {
        'break_minutes': (s.breakMinutes ?? 0) + (mins < 0 ? 0 : mins),
        'break_started_at': null,
      });
    } else {
      // Pause: anchor in UTC so the break clock survives an app kill.
      await _persist(
          s, {'break_started_at': DateTime.now().toUtc().toIso8601String()});
    }
  }

  Future<void> _setStack(SessionModel s) async {
    final v = double.tryParse(_stackCtrl.text.trim());
    if (v == null) return;
    await _persist(s, {'current_stack': v});
  }

  Future<void> _addNote(SessionModel s) async {
    final text = _noteCtrl.text.trim();
    if (text.isEmpty) return;
    final stamp = formatClockTime(DateTime.now());
    final line = '$stamp — $text';
    final notes = (s.notes == null || s.notes!.isEmpty)
        ? line
        : '${s.notes}\n$line';
    _noteCtrl.clear();
    await _persist(s, {'notes': notes});
  }

  Future<double?> _promptAmount(
      {required String title, required String currency}) async {
    final ctrl = TextEditingController();
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            prefixText: '${currencySymbol(currency)} ',
            labelText: 'Amount',
          ),
          onSubmitted: (_) =>
              Navigator.pop(ctx, double.tryParse(ctrl.text.trim())),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, double.tryParse(ctrl.text.trim())),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  Future<void> _recordHand(SessionModel s) async {
    await showRecordHandSheet(
      context,
      prefilledSessionId: s.id,
      prefilledStakes: s.stakes == 'N/A' ? null : s.stakes,
      prefilledSessionLabel: _sessionLabel(s),
      isTournamentSession: s.gameType != 'cash',
    );
    if (!mounted) return;
    ref.invalidate(handsProvider);
  }

  Future<void> _endSession(SessionModel s) async {
    final ctrl = TextEditingController(
      text: s.currentStack != null
          ? s.currentStack!.toStringAsFixed(0)
          : '',
    );
    final cashOut = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End session'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Total bought in: ${formatPLWithCurrency(s.totalBuyIn, s.currency)}',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                prefixText: '${currencySymbol(s.currency)} ',
                labelText: s.gameType == 'cash' ? 'Final cash-out' : 'Prize won',
                hintText: '0 if busted',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, double.tryParse(ctrl.text.trim()) ?? 0),
            child: const Text('End & Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (cashOut == null || !mounted) return;

    final now = DateTime.now();
    final start = s.startedAt ?? now;
    final grossMin = now.difference(start).inMinutes;
    // Close out an in-progress break, then store PLAYED time as the duration
    // (gross − breaks) so hourly stats stay accurate; keep break minutes as
    // metadata.
    final liveBreakMin =
        s.isOnBreak ? now.difference(s.breakStartedAt!).inMinutes : 0;
    final totalBreakMin =
        (s.breakMinutes ?? 0) + (liveBreakMin < 0 ? 0 : liveBreakMin);
    final playedMin = playedMinutes(grossMin, totalBreakMin);
    final pl = cashOut - s.totalBuyIn;
    final isCash = s.gameType == 'cash';

    setState(() {
      _busy = true;
      _leaving = true;
    });
    try {
      await _service.updateSession(s.id, {
        'status': 'completed',
        'cash_out': cashOut,
        'profit_loss': pl,
        'prize_won': isCash ? null : cashOut,
        'end_time': formatClockTime(now),
        'duration_minutes': playedMin,
        'break_minutes': totalBreakMin,
        'break_started_at': null,
        'current_stack': null,
      });
      AnalyticsService.sessionLogged(
        gameType: s.gameType,
        currency: s.currency,
        hasNotes: (s.notes ?? '').trim().isNotEmpty,
        source: 'live',
      );
      ref.invalidate(sessionsProvider);
      final fresh = await ref.read(sessionsProvider.future);
      final finalized = fresh.where((x) => x.id == s.id).firstOrNull;
      if (!mounted) return;
      if (finalized != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => SessionDetailScreen(session: finalized)),
        );
      } else {
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _leaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to end session: $e')),
      );
    }
  }

  Future<void> _discard(SessionModel s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard live session?'),
        content: const Text(
            'This deletes the session and any buy-ins recorded. Hands you '
            'recorded during it are kept but unlinked. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _leaving = true;
    });
    try {
      await _service.deleteSession(s.id);
      ref.invalidate(sessionsProvider);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _leaving = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to discard: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final liveAsync = ref.watch(liveSessionProvider);
    final session = liveAsync.valueOrNull;

    if (session == null) {
      // Ended, discarded elsewhere, or still loading — leave the screen.
      if (!_leaving && liveAsync.hasValue) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).maybePop();
        });
      }
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return _buildLive(context, session);
  }

  Widget _buildLive(BuildContext context, SessionModel s) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final now = DateTime.now();
    final grossElapsed =
        s.startedAt != null ? now.difference(s.startedAt!) : Duration.zero;
    final liveBreak =
        s.isOnBreak ? now.difference(s.breakStartedAt!) : Duration.zero;
    final breaksTotal = Duration(minutes: s.breakMinutes ?? 0) + liveBreak;
    // The main clock shows PLAYED time (gross − breaks); it naturally freezes
    // while on break since gross and breaks then grow in lockstep.
    var played = grossElapsed - breaksTotal;
    if (played.isNegative) played = Duration.zero;
    final net = s.currentStack != null ? s.currentStack! - s.totalBuyIn : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Session'),
        actions: [
          IconButton(
            tooltip: 'Discard',
            icon: const Icon(Icons.delete_outline),
            onPressed: _busy ? null : () => _discard(s),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
        children: [
          // Clock + context
          Card(
            color: s.isOnBreak ? cs.tertiaryContainer : cs.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        s.isOnBreak ? Icons.pause_circle : Icons.circle,
                        color: s.isOnBreak ? cs.onTertiaryContainer : Colors.red,
                        size: s.isOnBreak ? 18 : 12,
                      ),
                      const SizedBox(width: 8),
                      Text(_formatElapsed(played),
                          style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.isOnBreak
                        ? 'On break — clock paused'
                        : 'Time played'
                            '${breaksTotal.inMinutes > 0 ? ' · ${formatDuration(breaksTotal.inMinutes)} on break' : ''}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_sessionLabel(s)}'
                    '${s.location != null && s.location!.isNotEmpty ? ' · ${s.location}' : ''}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _toggleBreak(s),
                    icon: Icon(
                        s.isOnBreak ? Icons.play_arrow : Icons.pause,
                        size: 18),
                    label: Text(s.isOnBreak ? 'Resume' : 'Take a break'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Buy-ins
          _sectionLabel(context, 'BUY-INS'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total bought in', style: theme.textTheme.bodyMedium),
                      Text(
                        formatPLWithCurrency(s.totalBuyIn, s.currency),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const Divider(),
                  for (final e in s.buyinEvents)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${_kindLabel(e.kind)} · ${formatClockTime(e.ts.toLocal())}',
                            style: theme.textTheme.bodySmall,
                          ),
                          Text(formatPLWithCurrency(e.amount, s.currency),
                              style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : () => _addBuyin(s, 'rebuy'),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Rebuy'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : () => _addBuyin(s, 'addon'),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add-on'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Expenses (tracked separately from the poker result)
          _sectionLabel(context, 'EXPENSES'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total expenses', style: theme.textTheme.bodyMedium),
                      Text(
                        formatPLWithCurrency(s.totalExpenses, s.currency),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  if (s.expenseEvents.isNotEmpty) const Divider(),
                  for (final e in s.expenseEvents)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '${expenseCategoryLabel(e.category)} · ${formatClockTime(e.ts.toLocal())}'
                              '${e.note != null && e.note!.isNotEmpty ? ' · ${e.note}' : ''}',
                              style: theme.textTheme.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(formatPLWithCurrency(e.amount, s.currency),
                              style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => _addExpense(s),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add expense'),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Kept separate from your poker result — shown as a net '
                      'after the session ends.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Current stack / live net
          _sectionLabel(context, 'CURRENT STACK'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _stackCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    prefixText: '${currencySymbol(s.currency)} ',
                    labelText: 'Stack now',
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _setStack(s),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _busy ? null : () => _setStack(s),
                child: const Text('Set'),
              ),
            ],
          ),
          if (net != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Live net (stack − bought in)',
                      style: theme.textTheme.bodySmall),
                  Text(
                    formatPLWithCurrency(net, s.currency),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: net >= 0 ? Colors.green : Colors.red,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),

          // Quick note
          _sectionLabel(context, 'QUICK NOTE'),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _noteCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Reads, dynamics, a spot to revisit…',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _addNote(s),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _busy ? null : () => _addNote(s),
                child: const Text('Add'),
              ),
            ],
          ),
          if (s.notes != null && s.notes!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(s.notes!, style: theme.textTheme.bodySmall),
            ),
          ],
          const SizedBox(height: 24),

          OutlinedButton.icon(
            onPressed: _busy ? null : () => _recordHand(s),
            style:
                OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            icon: const Icon(Icons.add_card),
            label: const Text('Record a Hand'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : () => _endSession(s),
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('End Session'),
          ),
        ],
      ),
    );
  }

  static String _kindLabel(String kind) => switch (kind) {
        'rebuy' => 'Rebuy',
        'addon' => 'Add-on',
        _ => 'Buy-in',
      };

  Widget _sectionLabel(BuildContext context, String text) => Padding(
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
}
