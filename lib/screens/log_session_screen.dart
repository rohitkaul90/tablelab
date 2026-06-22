import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../data/poker_rooms.dart';
import '../models/session_model.dart';
import '../providers/providers.dart';
import '../services/analytics_service.dart';
import '../utils/helpers.dart';
import '../widgets/expense_dialog.dart';
import '../widgets/star_rating_widget.dart';

/// Session stakes presets and supported currencies. Public so the live
/// recorder's start form reuses the exact same lists (single source of truth).
const kStakeOptions = ['1/2', '1/3', '2/5', '5/10', '10/20', '25/50', 'Other'];
const kCurrencies = ['CAD', 'USD', 'GBP', 'EUR', 'AUD', 'NZD', 'INR'];
const _countries = [
  'Canada', 'USA', 'United Kingdom', 'Australia', 'New Zealand',
  'India', 'France', 'Germany', 'Spain', 'Italy', 'Netherlands', 'Belgium',
  'Czech Republic', 'Monaco', 'Online',
];

class LogSessionScreen extends ConsumerStatefulWidget {
  final SessionModel? session;

  const LogSessionScreen({super.key, this.session});

  @override
  ConsumerState<LogSessionScreen> createState() => _LogSessionScreenState();
}

class _LogSessionScreenState extends ConsumerState<LogSessionScreen> {
  final _formKey = GlobalKey<FormState>();

  late DateTime _date;
  late String _gameType;
  late String _selectedStake;
  bool _isCustomStake = false;
  final _customStakeCtrl = TextEditingController();
  final _buyInCtrl = TextEditingController();
  final _cashOutCtrl = TextEditingController();
  final _prizeWonCtrl = TextEditingController();
  final _finishPositionCtrl = TextEditingController();
  final _totalEntrantsCtrl = TextEditingController();
  final _rakeCtrl = TextEditingController();
  final _handsPerHourCtrl = TextEditingController();
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  String _locationName = '';
  PokerRoom? _selectedRoom;
  late String _currency;
  String? _country;
  final _notesCtrl = TextEditingController();
  final _breakMinutesCtrl = TextEditingController();
  final List<ExpenseEvent> _expenses = [];
  int? _tableQuality;
  int? _tableSize;
  bool _rakePresetLoaded = false;
  bool _submitted = false;
  bool _saving = false;

  double? _livePL;
  late int _liveDuration;

  bool get _isTournament => _gameType == 'tournament';
  bool get _isOnline =>
      _selectedRoom?.isOnline ?? isOnlineSession(_locationName);
  bool get _showTableQuality => !_isTournament && !_isOnline;

  @override
  void initState() {
    super.initState();
    final s = widget.session;
    if (s != null) {
      _date = DateTime.parse(s.date);
      _gameType = (s.gameType == 'sit_and_go') ? 'tournament' : s.gameType;
      final existingStake = s.stakes;
      _isCustomStake =
          !kStakeOptions.contains(existingStake) && existingStake != 'N/A';
      _selectedStake =
          (_isCustomStake || existingStake == 'N/A') ? kStakeOptions[0] : existingStake;
      if (_isCustomStake) _customStakeCtrl.text = existingStake;
      _buyInCtrl.text = s.buyIn.toStringAsFixed(0);
      _cashOutCtrl.text = s.cashOut.toStringAsFixed(0);
      if (s.prizeWon != null) {
        _prizeWonCtrl.text = s.prizeWon!.toStringAsFixed(0);
      }
      if (s.finishPosition != null) {
        _finishPositionCtrl.text = s.finishPosition!.toString();
      }
      if (s.totalEntrants != null) {
        _totalEntrantsCtrl.text = s.totalEntrants!.toString();
      }
      if (s.rakePaid != null) {
        _rakeCtrl.text = s.rakePaid!.toStringAsFixed(0);
      }
      if (s.handsPerHour != null) {
        _handsPerHourCtrl.text = s.handsPerHour!.toString();
      }
      _startTime = _parseTime(s.startTime);
      _endTime = _parseTime(s.endTime);
      _locationName = s.location ?? '';
      _selectedRoom =
          kPokerRooms.where((r) => r.storageKey == s.location).firstOrNull;
      _currency = s.currency;
      _country = s.country;
      _notesCtrl.text = s.notes ?? '';
      _tableQuality = s.tableQuality;
      _tableSize = s.tableSize;
      if ((s.breakMinutes ?? 0) > 0) {
        _breakMinutesCtrl.text = s.breakMinutes.toString();
      }
      _expenses.addAll(s.expenseEvents);
      _livePL = s.profitLoss;
      _liveDuration = s.durationMinutes;
    } else {
      _date = DateTime.now();
      _gameType = 'cash';
      _selectedStake = kStakeOptions[0];
      _startTime = TimeOfDay.now();
      _endTime = TimeOfDay.now();
      _liveDuration = 0;
      _currency = 'CAD';
      _handsPerHourCtrl.text = '25';
    }
    _buyInCtrl.addListener(_updateLive);
    _cashOutCtrl.addListener(_updateLive);
    _prizeWonCtrl.addListener(_updateLive);
    // Keep the duration card in sync as the break field changes so it shows
    // played time (gross − break) consistently, never a gross/played flip.
    _breakMinutesCtrl.addListener(_updateLive);
  }

  @override
  void dispose() {
    _customStakeCtrl.dispose();
    _buyInCtrl.dispose();
    _cashOutCtrl.dispose();
    _prizeWonCtrl.dispose();
    _finishPositionCtrl.dispose();
    _totalEntrantsCtrl.dispose();
    _rakeCtrl.dispose();
    _handsPerHourCtrl.dispose();
    _notesCtrl.dispose();
    _breakMinutesCtrl.dispose();
    super.dispose();
  }

  double get _totalExpenses =>
      _expenses.fold(0.0, (sum, e) => sum + e.amount);

  Future<void> _addExpense() async {
    final e = await showExpenseDialog(context, _currency);
    if (e == null) return;
    setState(() => _expenses.add(e));
  }

  Future<void> _editExpense(int index) async {
    final e = await showExpenseDialog(context, _currency,
        existing: _expenses[index]);
    if (e == null) return;
    setState(() => _expenses[index] = e);
  }

  TimeOfDay _parseTime(String t) {
    final parts = t.split(':');
    final h = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
    return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
  }

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// Gross window minutes from the start/end pickers.
  int get _grossDuration =>
      calcDurationMinutes(_formatTime(_startTime), _formatTime(_endTime));

  /// Break minutes entered, clamped to the session window so a typo can't
  /// produce more break than the session itself.
  int get _breakInput =>
      (int.tryParse(_breakMinutesCtrl.text.trim()) ?? 0).clamp(0, _grossDuration);

  void _updateLive() {
    final buyIn = double.tryParse(_buyInCtrl.text);
    setState(() {
      if (_isTournament) {
        final prizeWon = double.tryParse(_prizeWonCtrl.text);
        _livePL =
            (buyIn != null && prizeWon != null) ? prizeWon - buyIn : null;
      } else {
        final cashOut = double.tryParse(_cashOutCtrl.text);
        _livePL =
            (buyIn != null && cashOut != null) ? cashOut - buyIn : null;
      }
      // Show PLAYED time (gross − break) so the card matches what's stored.
      _liveDuration = playedMinutes(_grossDuration, _breakInput);
    });
  }

  Future<void> _selectLocation() async {
    final result = await showDialog<(PokerRoom?, String)>(
      context: context,
      builder: (_) => LocationPickerDialog(currentKey: _locationName),
    );
    if (result == null) return;
    final (room, name) = result;
    setState(() {
      _selectedRoom = room;
      _locationName = name;
      if (room != null) {
        _currency = room.currency;
        _country = room.country;
        if (room.isOnline) {
          if (_handsPerHourCtrl.text == '25') _handsPerHourCtrl.clear();
        } else if (_handsPerHourCtrl.text.isEmpty) {
          _handsPerHourCtrl.text = '25';
        }
      }
    });
    _fetchRakePreset();
  }

  Future<void> _fetchRakePreset() async {
    if (_locationName.isEmpty) return;
    final stakes =
        _isTournament ? 'N/A' : (_isCustomStake ? _customStakeCtrl.text.trim() : _selectedStake);
    final preset = await ref
        .read(supabaseServiceProvider)
        .getRakePreset(_locationName, _gameType, stakes);
    if (preset != null && mounted) {
      setState(() {
        _rakeCtrl.text = (preset['rake_amount'] as num).toStringAsFixed(0);
        _rakePresetLoaded = true;
      });
    } else if (mounted) {
      setState(() => _rakePresetLoaded = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickStartTime() async {
    final picked =
        await showTimePicker(context: context, initialTime: _startTime);
    if (picked != null) {
      setState(() => _startTime = picked);
      _updateLive();
    }
  }

  Future<void> _pickEndTime() async {
    final picked =
        await showTimePicker(context: context, initialTime: _endTime);
    if (picked != null) {
      setState(() => _endTime = picked);
      _updateLive();
    }
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (_locationName.isEmpty) return;
    if (!_formKey.currentState!.validate()) return;
    if (_saving) return;
    setState(() => _saving = true);

    final stakesVal = _isTournament
        ? 'N/A'
        : (_isCustomStake ? _customStakeCtrl.text.trim() : _selectedStake);
    final buyIn = double.parse(_buyInCtrl.text);
    final startStr = _formatTime(_startTime);
    final endStr = _formatTime(_endTime);
    final grossDur = calcDurationMinutes(startStr, endStr);
    // duration_minutes is PLAYED time (gross − breaks) so hourly stats stay
    // accurate; break_minutes is kept separately as metadata. Break is clamped
    // to the window so it can never exceed the session length.
    final breakMin = _breakInput; // already clamped to [0, grossDur]
    final dur = playedMinutes(grossDur, breakMin);
    final dateStr = DateFormat('yyyy-MM-dd').format(_date);
    final now = DateTime.now().toIso8601String();

    double cashOut;
    double pl;
    double? prizeWon;
    if (_isTournament) {
      prizeWon = double.tryParse(_prizeWonCtrl.text) ?? 0;
      cashOut = prizeWon;
      pl = prizeWon - buyIn;
    } else {
      cashOut = double.parse(_cashOutCtrl.text);
      pl = cashOut - buyIn;
    }

    final rakeText = _rakeCtrl.text.trim();
    final double? rakeValue = rakeText.isEmpty ? null : double.tryParse(rakeText);
    final fpText = _finishPositionCtrl.text.trim();
    final teText = _totalEntrantsCtrl.text.trim();
    final hphText = _handsPerHourCtrl.text.trim();

    final data = {
      'date': dateStr,
      'stakes': stakesVal,
      'game_type': _gameType,
      'buy_in': buyIn,
      'cash_out': cashOut,
      'profit_loss': pl,
      'start_time': startStr,
      'end_time': endStr,
      'duration_minutes': dur,
      'location': _locationName.isEmpty ? null : _locationName,
      'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      'created_at': now,
      'rake_paid': rakeValue,
      'finish_position': fpText.isEmpty ? null : int.tryParse(fpText),
      'total_entrants': teText.isEmpty ? null : int.tryParse(teText),
      'prize_won': _isTournament ? prizeWon : null,
      'table_quality': _showTableQuality ? _tableQuality : null,
      'table_size': _isTournament ? null : _tableSize,
      'currency': _currency,
      'hands_per_hour': hphText.isEmpty ? null : int.tryParse(hphText),
      'country': _country,
      'break_minutes': breakMin == 0 ? null : breakMin,
      'expense_events':
          _expenses.isEmpty ? null : _expenses.map((e) => e.toJson()).toList(),
    };

    final service = ref.read(supabaseServiceProvider);
    try {
      if (rakeValue != null && _locationName.isNotEmpty) {
        await service.upsertRakePreset(_locationName, _gameType, stakesVal, rakeValue);
      }
      if (widget.session == null) {
        await service.insertSession(data);
        AnalyticsService.sessionLogged(
          gameType: _gameType,
          currency: _currency,
          hasNotes: _notesCtrl.text.trim().isNotEmpty,
          source: 'past',
        );
      } else {
        await service.updateSession(widget.session!.id, data);
      }
      ref.invalidate(sessionsProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save session: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sym = currencySymbol(_currency);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.session == null ? 'Log Session' : 'Edit Session'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          // Bottom inset: Android 15 (targetSdk 35) forces edge-to-edge, and an
          // explicit `padding` disables ListView's automatic safe-area handling
          // — without this the Save button lands under the system nav bar.
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
          children: [
            // Date
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today),
              title: const Text('Date'),
              subtitle: Text(DateFormat('EEEE, MMM d, yyyy').format(_date)),
              onTap: _pickDate,
            ),
            const Divider(),
            const SizedBox(height: 12),

            // Game Type
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'cash', label: Text('Cash Game')),
                ButtonSegment(value: 'tournament', label: Text('Tournament')),
              ],
              selected: {_gameType},
              onSelectionChanged: (v) {
                setState(() {
                  _gameType = v.first;
                  _updateLive();
                });
                _fetchRakePreset();
              },
              style: const ButtonStyle(
                  visualDensity: VisualDensity.compact),
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
                  errorText:
                      (_submitted && _locationName.isEmpty) ? 'Select a location' : null,
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

            // Country
            DropdownButtonFormField<String?>(
              key: ValueKey(_country),
              initialValue: _countries.contains(_country) ? _country : null,
              decoration: const InputDecoration(
                labelText: 'Country',
                border: OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Not specified',
                      style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: 0.75))),
                ),
                ..._countries.map((c) =>
                    DropdownMenuItem<String?>(value: c, child: Text(c))),
              ],
              onChanged: (v) => setState(() => _country = v),
            ),
            const SizedBox(height: 16),

            // Currency
            DropdownButtonFormField<String>(
              key: ValueKey(_currency),
              initialValue: _currency,
              decoration: const InputDecoration(
                labelText: 'Currency',
                border: OutlineInputBorder(),
              ),
              items: kCurrencies
                  .map((c) => DropdownMenuItem(
                      value: c,
                      child: Text('$c  (${currencySymbol(c)})')))
                  .toList(),
              onChanged: (v) => setState(() => _currency = v!),
            ),
            const SizedBox(height: 16),

            // Stakes (cash only)
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
                onChanged: (v) {
                  setState(() {
                    _selectedStake = v!;
                    _isCustomStake = v == 'Other';
                  });
                  _fetchRakePreset();
                },
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
                  onChanged: (_) => _fetchRakePreset(),
                  validator: (v) =>
                      (_isCustomStake && (v == null || v.trim().isEmpty))
                          ? 'Enter stakes'
                          : null,
                ),
              ],
              const SizedBox(height: 16),

              // Table size (optional — common cash games run 6, 8, or 9 handed)
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

            // Buy-in
            TextFormField(
              controller: _buyInCtrl,
              decoration: InputDecoration(
                labelText:
                    _isTournament ? 'Buy-in (entry fee)' : 'Buy-in',
                prefixText: '$sym ',
                border: const OutlineInputBorder(),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                if (double.tryParse(v) == null) return 'Invalid';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Cash-out or Prize Won
            if (_isTournament) ...[
              TextFormField(
                controller: _prizeWonCtrl,
                decoration: InputDecoration(
                  labelText: 'Prize Won',
                  prefixText: '$sym ',
                  hintText: '0 if no cash',
                  border: const OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (double.tryParse(v) == null) return 'Invalid';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _finishPositionCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Finish Position',
                        hintText: 'e.g. 3',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _totalEntrantsCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Total Entrants',
                        hintText: 'e.g. 120',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
            ] else
              TextFormField(
                controller: _cashOutCtrl,
                decoration: InputDecoration(
                  labelText: 'Cash-out',
                  prefixText: '$sym ',
                  border: const OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (!_isTournament) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    if (double.tryParse(v) == null) return 'Invalid';
                  }
                  return null;
                },
              ),
            const SizedBox(height: 16),

            // Rake / Fees
            TextFormField(
              controller: _rakeCtrl,
              decoration: InputDecoration(
                labelText: 'Rake / Fees (optional)',
                prefixText: '$sym ',
                hintText: 'Informational — does not affect profit',
                border: const OutlineInputBorder(),
                suffixText: _rakePresetLoaded ? 'auto-filled' : null,
                suffixStyle: TextStyle(
                    color: theme.colorScheme.primary, fontSize: 11),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) {
                if (_rakePresetLoaded) {
                  setState(() => _rakePresetLoaded = false);
                }
              },
            ),
            const SizedBox(height: 16),

            // Hands per hour
            TextFormField(
              controller: _handsPerHourCtrl,
              decoration: InputDecoration(
                labelText: 'Hands per Hour',
                hintText: _isOnline ? '25/table (e.g. 2 tables = 50)' : '25',
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),

            // Start / End time
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.access_time),
                    title: const Text('Start'),
                    subtitle: Text(_startTime.format(context)),
                    onTap: _pickStartTime,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.access_time_filled),
                    title: const Text('End'),
                    subtitle: Text(_endTime.format(context)),
                    onTap: _pickEndTime,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Break time (optional) — excluded from played hours / hourly rate
            TextFormField(
              controller: _breakMinutesCtrl,
              decoration: const InputDecoration(
                labelText: 'Break time (minutes, optional)',
                hintText: 'Excluded from hours played',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),

            // Live summary card
            Card(
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    vertical: 12, horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(children: [
                      Text('Duration',
                          style: theme.textTheme.bodySmall),
                      const SizedBox(height: 4),
                      Text(formatDuration(_liveDuration),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold)),
                    ]),
                    if (_livePL != null) ...[
                      Column(children: [
                        Text('Result',
                            style: theme.textTheme.bodySmall),
                        const SizedBox(height: 4),
                        Text(
                          formatPLWithCurrency(_livePL!, _currency),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _livePL! >= 0
                                ? Colors.green
                                : Colors.red,
                          ),
                        ),
                      ]),
                      if (_isTournament &&
                          double.tryParse(_buyInCtrl.text) != null &&
                          double.parse(_buyInCtrl.text) > 0)
                        Column(children: [
                          Text('ROI',
                              style: theme.textTheme.bodySmall),
                          const SizedBox(height: 4),
                          Text(
                            formatROI(calcROI(
                                _livePL!,
                                double.parse(_buyInCtrl.text))),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _livePL! >= 0
                                  ? Colors.green
                                  : Colors.red,
                            ),
                          ),
                        ]),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Table Quality (live cash only)
            if (_showTableQuality) ...[
              StarRatingWidget(
                value: _tableQuality,
                onChanged: (v) => setState(() => _tableQuality = v),
              ),
              const SizedBox(height: 16),
            ],

            // Expenses (optional)
            _buildExpensesSection(theme),
            const SizedBox(height: 16),

            // Notes
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48)),
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save Session'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpensesSection(ThemeData theme) {
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Expenses (optional)', style: theme.textTheme.titleSmall),
            Text(formatPLWithCurrency(_totalExpenses, _currency),
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Tips, food, massage, travel — tracked separately from your result.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < _expenses.length; i++)
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              dense: true,
              title: Text(expenseCategoryLabel(_expenses[i].category)),
              subtitle:
                  (_expenses[i].note != null && _expenses[i].note!.isNotEmpty)
                      ? Text(_expenses[i].note!)
                      : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(formatPLWithCurrency(_expenses[i].amount, _currency)),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Remove',
                    onPressed: () => setState(() => _expenses.removeAt(i)),
                  ),
                ],
              ),
              onTap: () => _editExpense(i),
            ),
          ),
        OutlinedButton.icon(
          onPressed: _addExpense,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add expense'),
        ),
        if (_totalExpenses > 0 && _livePL != null) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Net after expenses', style: theme.textTheme.bodyMedium),
              Text(
                formatPLWithCurrency(_livePL! - _totalExpenses, _currency),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: (_livePL! - _totalExpenses) >= 0
                      ? Colors.green
                      : Colors.red,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ─── Location Picker Dialog ───────────────────────────────────────────────────

class LocationPickerDialog extends StatefulWidget {
  final String currentKey;

  const LocationPickerDialog({super.key, required this.currentKey});

  @override
  State<LocationPickerDialog> createState() => _LocationPickerDialogState();
}

class _LocationPickerDialogState extends State<LocationPickerDialog> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? kPokerRooms
        : kPokerRooms
            .where((r) =>
                r.name.toLowerCase().contains(_query) ||
                r.city.toLowerCase().contains(_query) ||
                r.region.toLowerCase().contains(_query))
            .toList();

    final grouped = <String, List<PokerRoom>>{};
    for (final room in filtered) {
      grouped.putIfAbsent(room.region, () => []).add(room);
    }

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search by name, city, or region...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) =>
                    setState(() => _query = v.toLowerCase().trim()),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final entry in grouped.entries) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                      child: Text(
                        entry.key,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    for (final room in entry.value)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          room.isOnline
                              ? Icons.computer_outlined
                              : Icons.casino_outlined,
                          size: 20,
                        ),
                        title: Text(room.name),
                        subtitle: Text(room.subtitle),
                        trailing: Text(
                          room.currency,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        selected: room.storageKey == widget.currentKey,
                        onTap: () => Navigator.pop(
                            context, (room, room.storageKey)),
                      ),
                  ],
                  if (_query.isNotEmpty && filtered.isEmpty) ...[
                    const SizedBox(height: 12),
                    ListTile(
                      leading: const Icon(Icons.add_location_alt_outlined),
                      title: Text(
                          'Use "${_searchCtrl.text.trim()}" as custom location'),
                      onTap: () => Navigator.pop(
                          context, (null, _searchCtrl.text.trim())),
                    ),
                  ] else if (_query.isNotEmpty) ...[
                    const Divider(height: 16),
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.add_location_alt_outlined),
                      title: Text(
                          'Use "${_searchCtrl.text.trim()}" as custom location'),
                      onTap: () => Navigator.pop(
                          context, (null, _searchCtrl.text.trim())),
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
