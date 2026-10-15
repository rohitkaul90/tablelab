import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/poker_rooms.dart';
import '../l10n/l10n.dart';
import '../l10n/labels.dart';
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

String _sessionLabel(AppLocalizations l10n, SessionModel s) {
  final date = s.date.length >= 10 ? s.date.substring(0, 10) : s.date;
  // Tournaments carry no stakes — show the localized game type, never the
  // raw DB enum ('sit_and_go').
  final stakes = s.stakes == 'N/A'
      ? gameTypeKeyLabel(
          l10n, isTournamentType(s.gameType) ? 'tournament' : s.gameType)
      : s.stakes;
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
              title: Text(ctx.l10n.liveChooserResume),
              subtitle: Text(_sessionLabel(context.l10n, live)),
              onTap: () => Navigator.pop(ctx, 'resume'),
            )
          else
            ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: Text(ctx.l10n.liveChooserStart),
              subtitle: Text(ctx.l10n.liveChooserStartHint),
              onTap: () => Navigator.pop(ctx, 'live'),
            ),
          ListTile(
            leading: const Icon(Icons.edit_note),
            title: Text(ctx.l10n.liveChooserPast),
            subtitle: Text(ctx.l10n.liveChooserPastHint),
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
          title: Text(context.l10n.liveCardTitle,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            '${_sessionLabel(context.l10n, live)}'
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

  /// True once the one-time carry-over defaults for the initial game type have
  /// been applied (guards the async provider-resolves path from re-firing).
  bool _initialDefaultsApplied = false;

  bool get _isTournament => _gameType == 'tournament';

  @override
  void initState() {
    super.initState();
    _applyInitialDefaults();
  }

  @override
  void dispose() {
    _customStakeCtrl.dispose();
    _buyInCtrl.dispose();
    super.dispose();
  }

  /// Apply the one-time carry-over defaults for the initial game type, waiting
  /// for the sessions provider to resolve if the screen opened on a cold start
  /// (so the pre-fill isn't silently skipped before the first fetch completes).
  void _applyInitialDefaults() {
    final async = ref.read(completedSessionsProvider);
    final sessions = async.valueOrNull;
    if (sessions != null) {
      _applyCarryOverDefaults(sessions, _gameType);
      _initialDefaultsApplied = true;
      return;
    }
    ref.listenManual<AsyncValue<List<SessionModel>>>(completedSessionsProvider,
        (prev, next) {
      if (_initialDefaultsApplied) return;
      final loaded = next.valueOrNull;
      if (loaded == null) return;
      _initialDefaultsApplied = true;
      setState(() => _applyCarryOverDefaults(loaded, _gameType));
    });
  }

  /// Carry venue/stakes/currency/table-size/buy-in over from the most recent
  /// completed session of [gameType]'s family. Re-applied on every game-type
  /// toggle so each type shows ITS OWN last session; when the family has no
  /// prior session the carry-over fields reset to a clean slate.
  void _applyCarryOverDefaults(List<SessionModel> sessions, String gameType) {
    final d = sessionDefaultsFor(sessions, gameType);
    if (d == null) {
      _resetCarryOverFields();
      return;
    }
    _locationName = d.location ?? '';
    _currency = d.currency;
    _country = d.country;
    _tableSize = d.tableSize;
    final stake = d.stakes;
    if (stake.isNotEmpty && stake != 'N/A') {
      _isCustomStake = !kStakeOptions.contains(stake);
      // A custom stake selects the 'Other' sentinel so the dropdown and the
      // custom-stakes field agree.
      _selectedStake = _isCustomStake ? 'Other' : stake;
      _customStakeCtrl.text = _isCustomStake ? stake : '';
    }
    _buyInCtrl.text = d.buyIn.toStringAsFixed(0);
  }

  /// Reset only the carry-over fields to their blank/new-session defaults.
  void _resetCarryOverFields() {
    _locationName = '';
    _currency = 'CAD';
    _country = null;
    _tableSize = null;
    _isCustomStake = false;
    _selectedStake = kStakeOptions[0];
    _customStakeCtrl.clear();
    _buyInCtrl.clear();
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
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.liveStartAlreadyLive)));
      return;
    }

    setState(() => _saving = true);
    final l10n = context.l10n;
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
        SnackBar(content: Text(l10n.liveStartFailed('$e'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final sym = currencySymbol(_currency);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.liveStartTitle)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
          children: [
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'cash', label: Text(l10n.gameTypeCash)),
                ButtonSegment(
                    value: 'tournament', label: Text(l10n.gameTypeTournament)),
              ],
              selected: {_gameType},
              onSelectionChanged: (v) => setState(() {
                _gameType = v.first;
                // Re-default this type's fields from ITS last session so
                // toggling never leaves the other type's buy-in/currency behind.
                final sessions =
                    ref.read(completedSessionsProvider).valueOrNull ??
                        const <SessionModel>[];
                _applyCarryOverDefaults(sessions, _gameType);
              }),
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
            ),
            const SizedBox(height: 16),

            // Location (required)
            InkWell(
              onTap: _selectLocation,
              borderRadius: BorderRadius.circular(4),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: l10n.logSessionLocation,
                  border: const OutlineInputBorder(),
                  suffixIcon: const Icon(Icons.search),
                  errorText: (_submitted && _locationName.isEmpty)
                      ? l10n.logSessionSelectLocation
                      : null,
                ),
                child: Text(
                  _locationName.isEmpty
                      ? l10n.logSessionSelectRoomHint
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
              decoration: InputDecoration(
                labelText: l10n.logSessionCurrency,
                border: const OutlineInputBorder(),
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
                decoration: InputDecoration(
                  labelText: l10n.logSessionStakes,
                  border: const OutlineInputBorder(),
                ),
                items: kStakeOptions
                    .map((s) => DropdownMenuItem(
                        value: s,
                        child: Text(
                            s == 'Other' ? l10n.logSessionStakesOther : s)))
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
                  decoration: InputDecoration(
                    labelText: l10n.logSessionCustomStakes,
                    hintText: l10n.logSessionCustomStakesHint,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (_isCustomStake && (v == null || v.trim().isEmpty))
                          ? l10n.logSessionEnterStakes
                          : null,
                ),
              ],
              const SizedBox(height: 16),
              DropdownButtonFormField<int?>(
                key: ValueKey(_tableSize),
                initialValue: _tableSize,
                // Fill the field width — the intrinsic-width dropdown overflowed
                // by a few px on 360dp phones (caught by the l10n smoke test).
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.logSessionTableSize,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem<int?>(
                    value: null,
                    child: Text(l10n.logSessionNotSpecified,
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
                labelText: _isTournament
                    ? l10n.logSessionBuyInTournament
                    : l10n.logSessionBuyIn,
                prefixText: '$sym ',
                border: const OutlineInputBorder(),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return l10n.commonRequired;
                final n = double.tryParse(v);
                if (n == null) return l10n.commonInvalid;
                if (n <= 0) return l10n.liveStartMustBePositive;
                return null;
              },
            ),
            const SizedBox(height: 24),

            FilledButton.icon(
              onPressed: _saving ? null : _start,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              icon: const Icon(Icons.play_arrow),
              label: Text(_saving ? l10n.liveStartStarting : l10n.liveStartButton),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.liveStartHint,
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
    final l10n = context.l10n;
    setState(() => _busy = true);
    try {
      await _service.updateSession(s.id, data);
      ref.invalidate(sessionsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.liveUpdateFailed('$e'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addBuyin(SessionModel s, String kind) async {
    final amount = await _promptAmount(
      title: kind == 'rebuy' ? context.l10n.liveAddRebuy : context.l10n.liveAddAddon,
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
    AnalyticsService.liveRebuyAdded(kind: kind);
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
    final l10n = context.l10n;
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
            labelText: l10n.expenseDialogAmount,
          ),
          onSubmitted: (_) =>
              Navigator.pop(ctx, double.tryParse(ctrl.text.trim())),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.commonCancel)),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, double.tryParse(ctrl.text.trim())),
            child: Text(l10n.commonAdd),
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
      prefilledSessionLabel: _sessionLabel(context.l10n, s),
      isTournamentSession: s.gameType != 'cash',
    );
    if (!mounted) return;
    ref.invalidate(handsProvider);
  }

  Future<void> _endSession(SessionModel s) async {
    final l10n = context.l10n;
    final ctrl = TextEditingController(
      text: s.currentStack != null
          ? s.currentStack!.toStringAsFixed(0)
          : '',
    );
    final cashOut = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.liveEndTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.liveTotalBoughtIn(
                  formatPLWithCurrency(s.totalBuyIn, s.currency)),
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
                labelText: s.gameType == 'cash'
                    ? l10n.liveFinalCashOut
                    : l10n.livePrizeWon,
                hintText: l10n.liveBustedHint,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.commonCancel)),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, double.tryParse(ctrl.text.trim()) ?? 0),
            child: Text(l10n.liveEndSave),
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
        SnackBar(content: Text(l10n.liveEndFailed('$e'))),
      );
    }
  }

  Future<void> _discard(SessionModel s) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.liveDiscardTitle),
        content: Text(l10n.liveDiscardBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.commonCancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.liveDiscard,
                style: const TextStyle(color: Colors.red)),
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
      AnalyticsService.liveSessionAbandoned();
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
          .showSnackBar(SnackBar(content: Text(l10n.liveDiscardFailed('$e'))));
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
    final l10n = context.l10n;
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
        title: Text(l10n.liveTitle),
        actions: [
          IconButton(
            tooltip: l10n.liveDiscard,
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
                        ? l10n.liveOnBreak
                        : breaksTotal.inMinutes > 0
                            ? l10n.liveTimePlayedWithBreak(
                                formatDuration(breaksTotal.inMinutes))
                            : l10n.liveTimePlayed,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_sessionLabel(context.l10n, s)}'
                    '${s.location != null && s.location!.isNotEmpty ? ' · ${s.location}' : ''}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _toggleBreak(s),
                    icon: Icon(
                        s.isOnBreak ? Icons.play_arrow : Icons.pause,
                        size: 18),
                    label: Text(s.isOnBreak ? l10n.liveResume : l10n.liveTakeBreak),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Buy-ins
          _sectionLabel(context, l10n.liveBuyInsHeader),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(l10n.liveTotalBoughtInLabel,
                            style: theme.textTheme.bodyMedium,
                            overflow: TextOverflow.ellipsis),
                      ),
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
                            '${_kindLabel(l10n, e.kind)} · ${formatClockTime(e.ts.toLocal())}',
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
                          label: Text(l10n.liveRebuy),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : () => _addBuyin(s, 'addon'),
                          icon: const Icon(Icons.add, size: 18),
                          label: Text(l10n.liveAddon),
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
          _sectionLabel(context, l10n.liveExpensesHeader),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(l10n.liveTotalExpenses,
                            style: theme.textTheme.bodyMedium,
                            overflow: TextOverflow.ellipsis),
                      ),
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
                              '${expenseCategoryLabel(l10n, e.category)} · ${formatClockTime(e.ts.toLocal())}'
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
                      label: Text(l10n.logSessionAddExpense),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      l10n.liveExpensesNote,
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
          _sectionLabel(context, l10n.liveStackHeader),
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
                    labelText: l10n.liveStackNow,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _setStack(s),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _busy ? null : () => _setStack(s),
                child: Text(l10n.liveSet),
              ),
            ],
          ),
          if (net != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(l10n.liveNet,
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis),
                  ),
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
          _sectionLabel(context, l10n.liveNoteHeader),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _noteCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: l10n.liveNoteHint,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _addNote(s),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _busy ? null : () => _addNote(s),
                child: Text(l10n.commonAdd),
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
            label: Text(l10n.sessionDetailRecordHand),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : () => _endSession(s),
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            icon: const Icon(Icons.stop_circle_outlined),
            label: Text(l10n.liveEndSession),
          ),
        ],
      ),
    );
  }

  static String _kindLabel(AppLocalizations l10n, String kind) =>
      switch (kind) {
        'rebuy' => l10n.liveRebuy,
        'addon' => l10n.liveAddon,
        _ => l10n.liveKindBuyIn,
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
