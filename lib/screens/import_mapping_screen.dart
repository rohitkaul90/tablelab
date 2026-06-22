import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../data/poker_rooms.dart';
import '../services/analytics_service.dart';
import '../providers/providers.dart';
import '../utils/helpers.dart';

// ─── Field definitions ────────────────────────────────────────────────────────

class _AppField {
  final String key;
  final String label;
  final bool required;
  final String? hint;

  const _AppField(this.key, this.label, {this.required = false, this.hint});
}

const _appFields = [
  _AppField('date',             'Date',                   required: true),
  _AppField('buy_in',           'Buy-in',                 required: true),
  _AppField('game_type',        'Game Type',              hint: 'cash / tournament'),
  _AppField('stakes',           'Stakes',                 hint: 'e.g. 1/2, 2/5'),
  _AppField('cash_out',         'Cash-out'),
  _AppField('prize_won',        'Prize Won'),
  _AppField('profit_loss',      'Profit',                 hint: 'used to derive cash-out if absent'),
  _AppField('duration_minutes', 'Duration (minutes)'),
  _AppField('duration_hours',   'Duration (hours)',       hint: 'also accepts "1h 30m", "1:30" etc.'),
  _AppField('start_time',       'Start Time'),
  _AppField('end_time',         'End Time'),
  _AppField('location',         'Location / Venue'),
  _AppField('currency',         'Currency',               hint: 'CAD, USD, GBP…'),
  _AppField('country',          'Country',                hint: 'Canada, USA, UK…'),
  _AppField('hands_per_hour',   'Hands per Hour'),
  _AppField('notes',            'Notes'),
  _AppField('rake_paid',        'Rake / Fees'),
  _AppField('finish_position',  'Finish Position'),
  _AppField('total_entrants',   'Total Entrants'),
  _AppField('table_quality',    'Table Quality (1–5)'),
];

const _notMapped = '-- Not in file --';

// ─── Import presets ───────────────────────────────────────────────────────────

class _Preset {
  final String id;
  final String name;
  // Per-field ordered candidate header patterns (case-insensitive, normalized).
  final Map<String, List<String>> columns;

  const _Preset({required this.id, required this.name, required this.columns});
}

const _presets = [
  // ── TableLab own export ──────────────────────────────────────────────────
  _Preset(
    id: 'tablelab',
    name: 'TableLab',
    columns: {
      'date':             ['date'],
      'buy_in':           ['buy_in'],
      'game_type':        ['game_type'],
      'stakes':           ['stakes'],
      'cash_out':         ['cash_out'],
      'prize_won':        ['prize_won'],
      'profit_loss':      ['profit_loss'],
      'duration_minutes': ['duration_minutes'],
      'start_time':       ['start_time'],
      'end_time':         ['end_time'],
      'location':         ['location'],
      'currency':         ['currency'],
      'country':          ['country'],
      'notes':            ['notes'],
      'rake_paid':        ['rake_paid'],
      'finish_position':  ['finish_position'],
      'total_entrants':   ['total_entrants'],
      'table_quality':    ['table_quality'],
    },
  ),

  // ── Mobile / web bankroll tracking apps ──────────────────────────────────

  // Confirmed columns: game format, stake, location, time, profit, notes
  _Preset(
    id: 'poker_income',
    name: 'Poker Income',
    columns: {
      'date':           ['date'],
      'game_type':      ['game format', 'game type', 'gametype', 'format', 'type'],
      'stakes':         ['stake', 'stakes', 'game name', 'level'],
      'buy_in':         ['buy-in', 'buyin', 'buy in', 'investment'],
      'cash_out':       ['cash out', 'cashout', 'cash-out', 'winnings'],
      'profit_loss':    ['profit', 'net', 'result'],
      'start_time':     ['time', 'start time', 'session start'],
      'duration_hours': ['duration (hours)', 'duration', 'hours played', 'session length', 'length'],
      'location':       ['location', 'venue', 'casino', 'room'],
      'notes':          ['notes', 'note', 'comments'],
    },
  ),
  _Preset(
    id: 'bankrollmob',
    name: 'BankrollMob',
    columns: {
      'date':           ['date'],
      'game_type':      ['game type', 'type', 'gametype'],
      'stakes':         ['stakes', 'blinds', 'limit'],
      'buy_in':         ['buy in', 'buyin', 'buy-in', 'investment'],
      'cash_out':       ['cash out', 'cashout', 'ending amount'],
      'profit_loss':    ['net profit/loss', 'profit/loss', 'profit', 'net result', 'result'],
      'duration_hours': ['session length', 'duration', 'hours'],
      'location':       ['location', 'casino', 'site', 'venue'],
      'notes':          ['notes'],
    },
  ),
  _Preset(
    id: 'simply_poker',
    name: 'Simply Poker',
    columns: {
      'date':           ['date'],
      'game_type':      ['type', 'game type', 'format'],
      'stakes':         ['stakes', 'blinds'],
      'buy_in':         ['buyin', 'buy-in', 'buy in'],
      'cash_out':       ['cashout', 'cash-out', 'cash out'],
      'duration_hours': ['duration', 'session length', 'time played', 'length'],
      'location':       ['venue', 'location', 'casino'],
      'notes':          ['notes', 'comment'],
    },
  ),
  _Preset(
    id: 'poker_analytics',
    name: 'Poker Analytics',
    columns: {
      'date':             ['date'],
      'game_type':        ['type', 'game type', 'variant'],
      'stakes':           ['stakes', 'blinds', 'level'],
      'buy_in':           ['buy in', 'buy-in', 'buyin'],
      'cash_out':         ['cash out', 'cashout', 'cash-out'],
      'duration_minutes': ['length (minutes)', 'duration (min)', 'minutes', 'duration minutes'],
      'duration_hours':   ['length (hours)', 'duration (hours)', 'duration', 'length', 'hours'],
      'location':         ['venue', 'location', 'room', 'casino'],
      'notes':            ['notes', 'comments'],
    },
  ),
  _Preset(
    id: 'poker_journal',
    name: 'Poker Journal',
    columns: {
      'date':           ['date', 'session date'],
      'game_type':      ['game', 'game type', 'type', 'format'],
      'stakes':         ['stakes', 'blinds', 'level'],
      'buy_in':         ['buy-in', 'buy in', 'buyin'],
      'cash_out':       ['cash-out', 'cash out', 'cashout'],
      'duration_hours': ['duration', 'time', 'hours', 'session length'],
      'location':       ['location', 'venue', 'casino', 'room'],
      'notes':          ['notes', 'session notes', 'memo'],
    },
  ),
  // Confirmed columns: date, location, expense (=buy_in), currency, profit (=P&L)
  // Optional manual columns: buyin, cashout, type, game, limit
  _Preset(
    id: 'pokerbase',
    name: 'PokerBase',
    columns: {
      'date':        ['date'],
      'buy_in':      ['expense', 'buyin', 'buy-in', 'buy in'],
      'game_type':   ['type', 'game', 'game type'],
      'stakes':      ['limit', 'stakes', 'game', 'blinds'],
      'cash_out':    ['cashout', 'cash out', 'cash-out'],
      'profit_loss': ['profit', 'net', 'result', 'profit/loss'],
      'location':    ['location', 'venue', 'casino'],
      'currency':    ['currency'],
      'notes':       ['notes'],
    },
  ),
  _Preset(
    id: 'splendid_poker',
    name: 'Splendid Poker',
    columns: {
      'date':           ['date'],
      'game_type':      ['game type', 'type'],
      'stakes':         ['stakes', 'blinds'],
      'buy_in':         ['buy-in', 'buyin', 'buy in'],
      'cash_out':       ['cash out', 'cashout', 'cash-out'],
      'duration_hours': ['duration', 'session length', 'length'],
      'location':       ['venue', 'location', 'casino'],
      'notes':          ['notes', 'tags'],
    },
  ),
  _Preset(
    id: 'my_poker_log',
    name: 'My Poker Log',
    columns: {
      'date':           ['date'],
      'game_type':      ['type', 'game', 'game type'],
      'stakes':         ['stakes', 'blinds', 'level'],
      'buy_in':         ['buy-in', 'buyin', 'buy in'],
      'cash_out':       ['cash-out', 'cashout', 'cash out'],
      'duration_hours': ['duration', 'hours', 'session length', 'length'],
      'location':       ['venue', 'location', 'casino', 'room'],
      'notes':          ['notes', 'memo'],
    },
  ),
  _Preset(
    id: 'poker_sessions',
    name: 'Poker Sessions',
    columns: {
      'date':           ['date'],
      'game_type':      ['game type', 'game', 'type'],
      'stakes':         ['stakes', 'blinds', 'limit'],
      'buy_in':         ['buy-in', 'buyin', 'buy in'],
      'cash_out':       ['cash out', 'cashout', 'cash-out'],
      'duration_hours': ['duration (hrs)', 'duration', 'hours', 'session length', 'length'],
      'location':       ['venue', 'location', 'casino', 'room'],
      'notes':          ['notes', 'comments'],
    },
  ),
  // Special: first CSV line is "—PBT Bankroll Export—" (handled by file parser)
  _Preset(
    id: 'poker_bankroll_tracker',
    name: 'Poker Bankroll Tracker',
    columns: {
      'date':             ['date'],
      'game_type':        ['game', 'game type', 'type'],
      'stakes':           ['stakes', 'blinds', 'level'],
      'buy_in':           ['buy-in', 'buyin', 'buy in'],
      'cash_out':         ['cash-out', 'cashout', 'cash out'],
      'duration_minutes': ['duration', 'duration (minutes)', 'minutes', 'session length'],
      'location':         ['venue', 'venue type', 'location', 'casino'],
      'notes':            ['notes', 'comment'],
    },
  ),

  // ── Desktop HUD / tracking software ──────────────────────────────────────
  // These export P&L (Net Won), not cash-out — cash-out is derived automatically.

  _Preset(
    id: 'pokertracker',
    name: 'PokerTracker 4',
    columns: {
      'date':             ['session start time', 'date', 'session date'],
      'game_type':        ['game type', 'game', 'type'],
      'stakes':           ['blinds', 'stakes', 'limit'],
      'buy_in':           ['buy in', 'buyin', 'buy-in'],
      'cash_out':         ['cash out', 'cashout'],
      'profit_loss':      ['net won', 'net', 'profit', 'net profit', 'net amount'],
      'duration_minutes': ['duration (min)', 'session length (min)', 'duration'],
      'start_time':       ['session start time', 'start time', 'start'],
      'end_time':         ['session end time', 'end time', 'end'],
      'location':         ['table', 'room', 'site', 'location'],
      'notes':            ['notes'],
    },
  ),
  _Preset(
    id: 'hm3',
    name: "Hold'em Manager 3",
    columns: {
      'date':             ['session date', 'date', 'start date', 'start time', 'session start'],
      'game_type':        ['game type', 'game', 'type', 'limit type'],
      'stakes':           ['stakes', 'blinds', 'limit', 'game'],
      'profit_loss':      ['net won', 'net won (usd)', 'net won (\$)', 'net amount', 'net'],
      'duration_minutes': ['duration (min)', 'duration', 'session length (min)', 'length (min)'],
      'location':         ['site', 'network', 'room', 'poker site'],
      'notes':            ['notes'],
    },
  ),
  _Preset(
    id: 'hand2note',
    name: 'Hand2Note',
    columns: {
      'date':             ['date', 'session date'],
      'game_type':        ['game type', 'game', 'type'],
      'stakes':           ['stakes', 'blinds', 'level'],
      'profit_loss':      ['net won', 'net won (\$)', 'net', 'won', 'profit'],
      'duration_minutes': ['duration (min)', 'duration', 'minutes', 'session length'],
      'location':         ['site', 'room', 'network'],
      'notes':            ['notes'],
    },
  ),
  _Preset(
    id: 'drivehud',
    name: 'DriveHUD',
    columns: {
      'date':             ['date', 'session date', 'start date'],
      'game_type':        ['game type', 'game', 'type'],
      'stakes':           ['stakes', 'blinds', 'limit'],
      'profit_loss':      ['net won', 'net', 'profit', 'win/loss'],
      'duration_minutes': ['duration (min)', 'duration', 'session length', 'length'],
      'location':         ['site', 'room', 'network', 'location'],
      'notes':            ['notes'],
    },
  ),
  _Preset(
    id: 'poker_copilot',
    name: 'Poker Copilot',
    columns: {
      'date':             ['date', 'session date', 'start'],
      'game_type':        ['game type', 'game', 'type'],
      'stakes':           ['stakes', 'blinds', 'small blind'],
      'profit_loss':      ['net won', 'net', 'profit', 'winnings', 'won'],
      'duration_minutes': ['duration', 'duration (min)', 'session length'],
      'location':         ['site', 'room', 'network', 'location'],
      'notes':            ['notes'],
    },
  ),

  // ── Tournament result databases ───────────────────────────────────────────
  // These export tournament history (no cash-out; use prize_won + finish_position).

  _Preset(
    id: 'sharkscope',
    name: 'Sharkscope',
    columns: {
      'date':            ['date', 'finished', 'tournament date', 'end date'],
      'buy_in':          ['buy-in', 'stake', 'entry fee', 'entry', 'buyin'],
      'prize_won':       ['prize', 'winnings', 'payout', 'won', 'prize won'],
      'profit_loss':     ['profit', 'net', 'profit/loss', 'result'],
      'finish_position': ['position', 'finish', 'place', 'final position'],
      'total_entrants':  ['entries', 'entrants', 'field size', 'players', 'total'],
      'location':        ['site', 'network', 'poker site'],
      'notes':           ['tournament', 'event', 'tournament name', 'name'],
    },
  ),
  _Preset(
    id: 'pokerstars_history',
    name: 'PokerStars History',
    columns: {
      'date':            ['date', 'tournament date', 'finish date', 'start date'],
      'buy_in':          ['buy-in', 'total buy-in', 'entry', 'buyin'],
      'prize_won':       ['prize', 'winnings', 'payout', 'won'],
      'profit_loss':     ['profit', 'net', 'profit/loss'],
      'finish_position': ['position', 'finish', 'place', 'finishing position'],
      'total_entrants':  ['entries', 'entrants', 'field', 'players', 'registered'],
      'location':        ['site', 'tournament name', 'event', 'game name'],
      'stakes':          ['buy-in', 'level', 'stake'],
    },
  ),
];

// ─── Preview model ────────────────────────────────────────────────────────────

class _RowIssue {
  final int rowNum;
  final String message;
  const _RowIssue(this.rowNum, this.message);
}

class _ImportPreview {
  final int valid;
  final int total;
  final String? dateMin;
  final String? dateMax;
  final List<_RowIssue> issues;
  // Non-fatal: cash rows whose stakes can't be parsed for BB/100.
  final String? stakesWarning;

  const _ImportPreview({
    required this.valid,
    required this.total,
    this.dateMin,
    this.dateMax,
    this.issues = const [],
    this.stakesWarning,
  });
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class ImportMappingScreen extends ConsumerStatefulWidget {
  final List<String> fileHeaders;
  final List<List<dynamic>> rows;
  final String? initialPresetId;

  const ImportMappingScreen({
    super.key,
    required this.fileHeaders,
    required this.rows,
    this.initialPresetId,
  });

  @override
  ConsumerState<ImportMappingScreen> createState() =>
      _ImportMappingScreenState();
}

class _ImportMappingScreenState extends ConsumerState<ImportMappingScreen> {
  late Map<String, String?> _mapping;
  String? _selectedPreset;
  bool _overwrite = false;
  bool _skipDuplicates = true;
  bool _importing = false;
  String? _error;
  late _ImportPreview _preview;

  @override
  void initState() {
    super.initState();
    // Use preset from source screen if provided; otherwise auto-detect from headers.
    _selectedPreset = widget.initialPresetId ?? _autoDetectPreset();
    _mapping = _buildMapping(_selectedPreset);
    _preview = _computePreview();
    // Reaching the mapping step means the file parsed; pairs with
    // import_completed for a mapping→done funnel.
    AnalyticsService.importStarted(source: _selectedPreset ?? 'custom');
  }

  // ─── Preset detection & application ──────────────────────────────────────

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^\w]'), '');

  String? _autoDetectPreset() {
    final normHeaders = widget.fileHeaders.map(_norm).toSet();

    String? best;
    int bestScore = 2; // require at least 3 fields to match

    for (final preset in _presets) {
      int score = 0;
      for (final patterns in preset.columns.values) {
        final matched = patterns.any((pat) {
          final normPat = _norm(pat);
          return normHeaders.any((h) =>
              h == normPat ||
              (normPat.length >= 5 && h.contains(normPat)));
        });
        if (matched) score++;
      }
      if (score > bestScore) {
        bestScore = score;
        best = preset.id;
      }
    }
    return best;
  }

  Map<String, String?> _buildMapping(String? presetId) {
    if (presetId == null) {
      return {for (final f in _appFields) f.key: _autoMap(f.key)};
    }
    final preset = _presets.firstWhere((p) => p.id == presetId);
    return {
      for (final f in _appFields)
        f.key: preset.columns.containsKey(f.key)
            ? (_matchHeader(preset.columns[f.key]!) ?? _autoMap(f.key))
            : _autoMap(f.key),
    };
  }

  String? _matchHeader(List<String> patterns) {
    for (final pat in patterns) {
      final normPat = _norm(pat);
      for (final h in widget.fileHeaders) {
        final normH = _norm(h);
        if (normH == normPat ||
            (normPat.length >= 5 && normH.contains(normPat))) {
          return h;
        }
      }
    }
    return null;
  }

  void _selectPreset(String? presetId) {
    setState(() {
      _selectedPreset = presetId;
      _mapping = _buildMapping(presetId);
      _preview = _computePreview();
    });
  }

  // ─── Auto-mapping ────────────────────────────────────────────────────────

  String? _autoMap(String key) {
    final candidates = _candidates(key);
    for (final h in widget.fileHeaders) {
      final norm = h.toLowerCase().replaceAll(RegExp(r'[\s_\-\(\)\$£€#]'), '');
      for (final c in candidates) {
        final cn = c.replaceAll(RegExp(r'[\s_\-]'), '');
        if (norm == cn || (cn.length >= 8 && norm.startsWith(cn))) return h;
      }
    }
    return null;
  }

  List<String> _candidates(String key) {
    switch (key) {
      case 'date':
        return [
          'date', 'sessiondate', 'session_date', 'day', 'playdate',
          'gamedate', 'game_date', 'played', 'eventdate',
        ];
      case 'buy_in':
        return [
          'buyin', 'buy_in', 'cashin', 'cash_in', 'investment', 'entry',
          'entryamount', 'buyin\$', 'buyinfee', 'buyinamount',
          'totalbuyin', 'totalinvestment', 'expense',
        ];
      case 'game_type':
        return [
          'gametype', 'game_type', 'type', 'format', 'sessiontype',
          'variant', 'gameformat', 'pokertype',
        ];
      case 'stakes':
        return [
          'stakes', 'level', 'blinds', 'limit', 'gamestakes', 'game',
          'gamelevel', 'tablesize', 'smallblind', 'structure',
        ];
      case 'cash_out':
        return [
          'cashout', 'cash_out', 'cashedout', 'walkaway', 'endup',
          'ending', 'endamount', 'finalchips', 'total', 'out',
          'endstack', 'finishstack', 'chipcount',
        ];
      case 'prize_won':
        return [
          'prizewon', 'prize_won', 'prize', 'winnings', 'payout',
          'winning', 'award', 'earnings', 'cashed',
        ];
      case 'profit_loss':
        return [
          'netprofitlossinhomecurrency', 'netprofitlosslocalcurrency',
          'profitlossinhomecurrency', 'netprofitlosshomecurrency',
          'profitloss', 'profit_loss', 'pl', 'profit', 'loss',
          'result', 'net', 'netsession', 'netresult', 'gain',
          'netgain', 'delta', 'netscore', 'netprofit', 'netwon',
          'sessionpl', 'sessionresult', 'sessionprofit',
        ];
      case 'duration_minutes':
        return [
          'durationminutes', 'duration_minutes', 'minutes',
          'sessionminutes', 'lengthminutes', 'playtimeminutes',
        ];
      case 'duration_hours':
        return [
          'durationhours', 'duration_hours', 'hours', 'sessionhours',
          'lengthhours', 'timeplayed', 'sessionlength', 'length',
          'hoursplayed', 'hrsplayed', 'hrplayed', 'duration', 'playtime',
        ];
      case 'start_time':
        return [
          'starttime', 'start_time', 'start', 'startsat', 'timestart',
          'began', 'begin', 'startedsat', 'time',
        ];
      case 'end_time':
        return [
          'endtime', 'end_time', 'end', 'endsat', 'timeend',
          'finished', 'finish', 'endedat',
        ];
      case 'location':
        return [
          'location', 'venue', 'casino', 'room', 'place',
          'cardroom', 'pokerroom', 'where', 'site', 'club',
        ];
      case 'currency':
        return ['currency', 'curr', 'ccy', 'moneytype', 'currencycode'];
      case 'country':
        return ['country', 'nation', 'locationcountry', 'country_played', 'jurisdiction'];
      case 'hands_per_hour':
        return ['handsperhour', 'hands_per_hour', 'hph', 'handshr', 'handrate'];
      case 'notes':
        return [
          'notes', 'note', 'comments', 'memo', 'comment',
          'remarks', 'description', 'tags',
        ];
      case 'rake_paid':
        return [
          'rake', 'rake_paid', 'fee', 'fees', 'juice', 'commission',
          'house', 'rakefee',
        ];
      case 'finish_position':
        return [
          'finish', 'finish_position', 'position', 'place',
          'finishplace', 'finishpos', 'rank', 'placed', 'finishedpos',
        ];
      case 'total_entrants':
        return [
          'entrants', 'total_entrants', 'field', 'players',
          'fieldsize', 'totalplayers', 'entries', 'startingfield',
        ];
      case 'table_quality':
        return [
          'tablequality', 'table_quality', 'quality', 'tablerating',
          'softness', 'gamerating', 'fishrating',
        ];
      default:
        return [key];
    }
  }

  // ─── Live preview ─────────────────────────────────────────────────────────

  _ImportPreview _computePreview() {
    int valid = 0;
    String? dateMin, dateMax;
    final issues = <_RowIssue>[];

    final headers = widget.fileHeaders;
    int colIdx(String? col) => col == null ? -1 : headers.indexOf(col);

    final dateIdx      = colIdx(_mapping['date']);
    final buyInIdx     = colIdx(_mapping['buy_in']);
    final cashOutIdx   = colIdx(_mapping['cash_out']);
    final prizeWonIdx  = colIdx(_mapping['prize_won']);
    final plIdx        = colIdx(_mapping['profit_loss']);
    final stakesIdx    = colIdx(_mapping['stakes']);
    final gameTypeIdx  = colIdx(_mapping['game_type']);

    var unparseableStakes = 0;
    String? unparseableExample;

    for (int i = 0; i < widget.rows.length; i++) {
      final row = widget.rows[i];
      String cell(int idx) =>
          idx >= 0 && idx < row.length ? row[idx].toString().trim() : '';

      final dateRaw = cell(dateIdx);
      if (dateRaw.isEmpty) {
        if (issues.length < 5) issues.add(_RowIssue(i + 2, 'Missing date'));
        continue;
      }
      final dateStr = _parseDate(dateRaw);
      if (dateStr == null) {
        if (issues.length < 5) {
          issues.add(_RowIssue(i + 2, 'Unrecognised date: "$dateRaw"'));
        }
        continue;
      }

      final buyInStr =
          cell(buyInIdx).replaceAll(RegExp(r'[\$,£€₹]'), '').trim();
      if (buyInStr.isEmpty || double.tryParse(buyInStr) == null) {
        if (issues.length < 5) {
          issues.add(_RowIssue(i + 2, 'Invalid buy-in: "${cell(buyInIdx)}"'));
        }
        continue;
      }

      final hasResult = (cashOutIdx >= 0 && cell(cashOutIdx).isNotEmpty) ||
          (prizeWonIdx >= 0 && cell(prizeWonIdx).isNotEmpty) ||
          (plIdx >= 0 && cell(plIdx).isNotEmpty);
      if (!hasResult && issues.length < 5) {
        issues.add(_RowIssue(i + 2, 'No result column — will record \$0 profit'));
      }

      if (dateMin == null || dateStr.compareTo(dateMin) < 0) dateMin = dateStr;
      if (dateMax == null || dateStr.compareTo(dateMax) > 0) dateMax = dateStr;

      // Stakes that can't be read for BB/100 (cash games only). Non-fatal —
      // the row still imports, it just won't contribute to BB/100.
      if (stakesIdx >= 0) {
        final stakesRaw = cell(stakesIdx);
        final gt = gameTypeIdx >= 0 ? cell(gameTypeIdx).toLowerCase() : '';
        final isCash = !gt.contains('tourn') &&
            !gt.contains('sng') &&
            !gt.contains('sit');
        if (isCash &&
            stakesRaw.isNotEmpty &&
            parseBBFromStakes(stakesRaw) == null) {
          unparseableStakes++;
          unparseableExample ??= stakesRaw;
        }
      }

      valid++;
    }

    final stakesWarning = unparseableStakes == 0
        ? null
        : '$unparseableStakes cash session${unparseableStakes == 1 ? '' : 's'} '
            'have stakes that can\'t be read for BB/100 (e.g. "$unparseableExample") '
            '— they\'ll still import, but won\'t count toward BB/100.';

    return _ImportPreview(
      valid: valid,
      total: widget.rows.length,
      dateMin: dateMin,
      dateMax: dateMax,
      issues: issues,
      stakesWarning: stakesWarning,
    );
  }

  // ─── Import ───────────────────────────────────────────────────────────────

  Future<void> _import() async {
    final hasResult = _mapping['cash_out'] != null ||
        _mapping['prize_won'] != null ||
        _mapping['profit_loss'] != null;

    if (!hasResult) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('No result column mapped'),
          content: const Text(
            'You haven\'t mapped Cash-out, Prize Won, or Profit.\n\n'
            'All imported sessions will show \$0 profit.\n\n'
            'Import anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Go back'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Import anyway'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() {
      _importing = true;
      _error = null;
    });

    try {
      final service = ref.read(supabaseServiceProvider);
      final headers = widget.fileHeaders;
      int colIdx(String? col) => col == null ? -1 : headers.indexOf(col);

      final dateIdx      = colIdx(_mapping['date']);
      final buyInIdx     = colIdx(_mapping['buy_in']);
      final gameTypeIdx  = colIdx(_mapping['game_type']);
      final stakesIdx    = colIdx(_mapping['stakes']);
      final cashOutIdx   = colIdx(_mapping['cash_out']);
      final prizeWonIdx  = colIdx(_mapping['prize_won']);
      final plIdx        = colIdx(_mapping['profit_loss']);
      final durMIdx      = colIdx(_mapping['duration_minutes']);
      final durHIdx      = colIdx(_mapping['duration_hours']);
      final startIdx     = colIdx(_mapping['start_time']);
      final endIdx       = colIdx(_mapping['end_time']);
      final locationIdx  = colIdx(_mapping['location']);
      final currencyIdx  = colIdx(_mapping['currency']);
      final countryIdx   = colIdx(_mapping['country']);
      final hphIdx       = colIdx(_mapping['hands_per_hour']);
      final notesIdx     = colIdx(_mapping['notes']);
      final rakeIdx      = colIdx(_mapping['rake_paid']);
      final fpIdx        = colIdx(_mapping['finish_position']);
      final teIdx        = colIdx(_mapping['total_entrants']);
      final tqIdx        = colIdx(_mapping['table_quality']);

      Set<String>? existingKeys;
      if (_skipDuplicates && !_overwrite) {
        final existing = await service.fetchAllSessions();
        existingKeys = existing
            .map((s) =>
                '${s.date}_${s.buyIn.toStringAsFixed(2)}_${s.cashOut.toStringAsFixed(2)}')
            .toSet();
      }

      final sessions = <Map<String, dynamic>>[];

      for (final row in widget.rows) {
        if (row.isEmpty) continue;
        String cell(int idx) =>
            idx >= 0 && idx < row.length ? row[idx].toString().trim() : '';

        final dateRaw = cell(dateIdx);
        if (dateRaw.isEmpty) continue;
        final dateStr = _parseDate(dateRaw);
        if (dateStr == null) continue;

        final buyInStr =
            cell(buyInIdx).replaceAll(RegExp(r'[\$,£€₹]'), '').trim();
        final buyIn = double.tryParse(buyInStr) ?? 0;

        // Game type — infer tournament when tournament-specific columns are
        // mapped but the file has no explicit game_type column (e.g. Sharkscope,
        // PokerStars tournament history exports).
        final String gameType;
        if (gameTypeIdx >= 0 && cell(gameTypeIdx).isNotEmpty) {
          gameType = _normalizeGameType(cell(gameTypeIdx));
        } else if (prizeWonIdx >= 0 || fpIdx >= 0 || teIdx >= 0) {
          gameType = 'tournament';
        } else {
          gameType = 'cash';
        }

        // Stakes
        final stakesRaw = cell(stakesIdx).trim();
        final stakes = stakesRaw.isNotEmpty
            ? stakesRaw
            : isTournamentType(gameType) ? 'N/A' : 'Cash';

        // Location (before currency so country inference works)
        final location = locationIdx >= 0 && cell(locationIdx).isNotEmpty
            ? cell(locationIdx)
            : null;

        // Country
        String? country;
        if (countryIdx >= 0 && cell(countryIdx).isNotEmpty) {
          country = cell(countryIdx);
        } else if (location != null) {
          country = countryFromLocation(location);
          if (country == null) {
            final locLower = location.toLowerCase();
            final match = kPokerRooms
                .where((r) => r.name.toLowerCase() == locLower)
                .firstOrNull;
            country = match?.country;
          }
        }

        // Currency
        const validCurrencies = ['CAD', 'USD', 'GBP', 'EUR', 'AUD', 'NZD', 'INR'];
        String currency;
        final currencyRaw =
            cell(currencyIdx).toUpperCase().replaceAll(RegExp(r'\s'), '');
        if (validCurrencies.contains(currencyRaw)) {
          currency = currencyRaw;
        } else {
          final fromCountry = currencyFromCountry(country);
          if (fromCountry != null) {
            currency = fromCountry;
          } else if (location != null) {
            final locLower = location.toLowerCase();
            final roomCurrency = kPokerRooms
                .where((r) =>
                    r.storageKey == location ||
                    r.name.toLowerCase() == locLower)
                .firstOrNull
                ?.currency;
            if (roomCurrency != null) {
              currency = roomCurrency;
            } else if (isOnlineSession(location)) {
              currency = 'USD';
            } else {
              currency = 'CAD';
            }
          } else {
            currency = 'CAD';
          }
        }

        // P&L from file (used to derive cash-out when cash-out is absent)
        final plRaw = plIdx >= 0 && cell(plIdx).isNotEmpty
            ? double.tryParse(
                cell(plIdx)
                    .replaceAll(RegExp(r'[\$£€₹,\s]'), '')
                    .replaceAll('+', ''))
            : null;

        // Cash out / prize
        final cashOutRaw = cashOutIdx >= 0
            ? double.tryParse(
                cell(cashOutIdx).replaceAll(RegExp(r'[\$,£€₹]'), ''))
            : null;
        final prizeWonRaw = prizeWonIdx >= 0
            ? double.tryParse(
                cell(prizeWonIdx).replaceAll(RegExp(r'[\$,£€₹]'), ''))
            : null;

        // Derive cash-out from P&L if cash-out column is absent
        double cashOut;
        if (isTournamentType(gameType)) {
          cashOut = prizeWonRaw ??
              cashOutRaw ??
              (plRaw != null ? buyIn + plRaw : 0);
        } else {
          cashOut = cashOutRaw ?? (plRaw != null ? buyIn + plRaw : 0);
        }

        final double pl = cashOut - buyIn;

        // Skip duplicates on (date + buy-in + cash-out). Checked here — not at
        // the top of the loop — because it needs the derived cash-out. Adding
        // the result makes two same-day, same-buy-in sessions with different
        // outcomes distinct, while a true re-import still yields an identical
        // key (cash-out round-trips as a number).
        if (existingKeys != null &&
            existingKeys.contains(
                '${dateStr}_${buyIn.toStringAsFixed(2)}_${cashOut.toStringAsFixed(2)}')) {
          continue;
        }

        // Duration — handles "1h 30m", "1:30", "1:30:00", decimal hours, plain minutes
        int durationMinutes = 0;
        if (durMIdx >= 0 && cell(durMIdx).isNotEmpty) {
          durationMinutes =
              _parseDurationToMinutes(cell(durMIdx), isHours: false);
        } else if (durHIdx >= 0 && cell(durHIdx).isNotEmpty) {
          durationMinutes =
              _parseDurationToMinutes(cell(durHIdx), isHours: true);
        } else if (startIdx >= 0 && endIdx >= 0) {
          durationMinutes = calcDurationMinutes(
            _normalizeTime(cell(startIdx)),
            _normalizeTime(cell(endIdx)),
          );
        }

        final startTime = startIdx >= 0 && cell(startIdx).isNotEmpty
            ? _normalizeTime(cell(startIdx))
            : '00:00';
        final endTime = endIdx >= 0 && cell(endIdx).isNotEmpty
            ? _normalizeTime(cell(endIdx))
            : '00:00';

        final notes =
            notesIdx >= 0 && cell(notesIdx).isNotEmpty ? cell(notesIdx) : null;
        final rake = rakeIdx >= 0 && cell(rakeIdx).isNotEmpty
            ? double.tryParse(
                cell(rakeIdx).replaceAll(RegExp(r'[\$,£€₹]'), ''))
            : null;
        final fp = fpIdx >= 0 && cell(fpIdx).isNotEmpty
            ? int.tryParse(cell(fpIdx))
            : null;
        final te = teIdx >= 0 && cell(teIdx).isNotEmpty
            ? int.tryParse(cell(teIdx))
            : null;
        final tq = tqIdx >= 0 && cell(tqIdx).isNotEmpty
            ? int.tryParse(cell(tqIdx))
            : null;
        final hph = hphIdx >= 0 && cell(hphIdx).isNotEmpty
            ? int.tryParse(cell(hphIdx))
            : null;

        sessions.add({
          'date': dateStr,
          'stakes': stakes,
          'game_type': gameType,
          'buy_in': buyIn,
          'cash_out': cashOut,
          'profit_loss': pl,
          'start_time': startTime,
          'end_time': endTime,
          'duration_minutes': durationMinutes,
          'currency': currency,
          'location': location,
          'notes': notes,
          'created_at': DateTime.now().toIso8601String(),
          'rake_paid': rake,
          'finish_position': fp,
          'total_entrants': te,
          'prize_won': prizeWonIdx >= 0
              ? prizeWonRaw
              : (isTournamentType(gameType) ? cashOutRaw : null),
          'table_quality': tq,
          'hands_per_hour': hph,
          'country': country,
        });
      }

      if (sessions.isEmpty) {
        throw Exception('No valid rows found to import.');
      }

      if (_overwrite) await service.clearAllSessions();
      await service.bulkInsertSessions(sessions);
      AnalyticsService.importCompleted(
        source: _selectedPreset ?? 'custom',
        rowCount: sessions.length,
        mode: _overwrite ? 'overwrite' : 'dedup',
      );
      ref.invalidate(sessionsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Imported ${sessions.length} session${sessions.length == 1 ? '' : 's'}.'),
        ));
        Navigator.pop(context);
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  // ─── Parsing helpers ──────────────────────────────────────────────────────

  String _normalizeGameType(String raw) {
    final s = raw.toLowerCase().trim();
    if (s.isEmpty) return 'cash';

    // Tournament
    if (s.contains('tournament') ||
        s == 'mtt' || s.startsWith('mtt ') || s.startsWith('mtt-') ||
        s == 'tourney' || s == 'multi-table' || s.contains('multitable') ||
        s.contains('bounty') || s.contains('knockout') || s.contains('pko') ||
        s.contains('satellite') || s.contains('shootout')) {
      return 'tournament';
    }

    // Sit & Go (including Spin & Go, Jackpot)
    if (s.contains('sit') ||
        s.contains('sng') || s.contains('s&g') ||
        s.contains('spin') || s.contains('jackpot') ||
        s == 'hyper' || s.contains('hyper-turbo') ||
        s == 'turbo sng' || s == 'double or nothing') {
      return 'sit_and_go';
    }

    return 'cash';
  }

  int _parseDurationToMinutes(String raw, {required bool isHours}) {
    final s = raw.trim();
    if (s.isEmpty) return 0;

    // "2h 30m", "2h30m", "2 hr 30 min", "2hours 30mins", "2h", "30m"
    final hm = RegExp(
      r'(\d+)\s*h(?:rs?|ours?)?\s*(?:(\d+)\s*m(?:ins?|inutes?)?)?',
      caseSensitive: false,
    ).firstMatch(s);
    if (hm != null) {
      return int.parse(hm.group(1)!) * 60 +
          (int.tryParse(hm.group(2) ?? '') ?? 0);
    }

    // "45m", "45 min", "45 minutes" (pure minutes, no hours part)
    final mOnly = RegExp(
      r'^(\d+)\s*m(?:ins?|inutes?)?$',
      caseSensitive: false,
    ).firstMatch(s);
    if (mOnly != null) return int.parse(mOnly.group(1)!);

    // "1:30" or "1:30:00" — leading segment is hours
    final hms = RegExp(r'^(\d+):(\d{2})(?::(\d{2}))?$').firstMatch(s);
    if (hms != null) {
      return int.parse(hms.group(1)!) * 60 + int.parse(hms.group(2)!);
    }

    // Plain number — context determines unit
    final n = double.tryParse(s.replaceAll(RegExp(r'[^\d.]'), ''));
    if (n == null) return 0;
    return isHours ? (n * 60).round() : n.round();
  }

  String? _parseDate(String raw) {
    final cleaned = raw
        .replaceAll(
            RegExp(
                r'^(Mon|Tue|Wed|Thu|Fri|Sat|Sun)[a-z]*(,\s*|\s+)',
                caseSensitive: false),
            '')
        .trim();

    final asNum = double.tryParse(cleaned);
    if (asNum != null && asNum >= 36526 && asNum <= 73050) {
      final serial = asNum.truncate();
      final effectiveDays = serial > 59 ? serial - 1 : serial;
      final dt = DateTime.utc(1899, 12, 30).add(Duration(days: effectiveDays));
      return '${dt.year.toString().padLeft(4, '0')}-'
          '${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')}';
    }

    const formats = [
      'yyyy-MM-dd', 'MM/dd/yyyy', 'dd/MM/yyyy', 'M/d/yyyy',
      'd/M/yyyy', 'MMM d, yyyy', 'MMMM d, yyyy', 'dd-MM-yyyy',
      'MM-dd-yyyy', 'd MMM yyyy', 'MMM dd yyyy', 'yyyy/MM/dd',
      'dd.MM.yyyy', 'M/d/yy', 'd/M/yy', 'MMM-dd-yyyy',
    ];
    for (final fmt in formats) {
      try {
        return DateFormat('yyyy-MM-dd')
            .format(DateFormat(fmt).parseStrict(cleaned));
      } catch (_) {}
    }
    try {
      final dt = DateTime.parse(cleaned).toUtc();
      return '${dt.year.toString().padLeft(4, '0')}-'
          '${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {}
    return null;
  }

  String _normalizeTime(String raw) {
    if (raw.isEmpty) return '00:00';
    try {
      if (RegExp(r'^\d{1,2}:\d{2}(:\d{2})?$').hasMatch(raw)) {
        final parts = raw.split(':');
        return '${parts[0].padLeft(2, '0')}:${parts[1]}';
      }
      return DateFormat('HH:mm').format(DateFormat('h:mm a').parseLoose(raw));
    } catch (_) {
      return '00:00';
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dropdownItems = <DropdownMenuItem<String>>[
      DropdownMenuItem<String>(
        value: null,
        child: Text(_notMapped,
            style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withValues(alpha: 0.75))),
      ),
      ...widget.fileHeaders.map(
        (h) => DropdownMenuItem(
          value: h,
          child: Text(h, overflow: TextOverflow.ellipsis),
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Map Columns')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Import preview ───────────────────────────────────────────
                _PreviewCard(preview: _preview),
                const SizedBox(height: 12),
                Text(
                  'Match your file\'s columns to app fields. '
                  'Only Date and Buy-in are required — everything else is inferred or optional.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
                const SizedBox(height: 16),

                // ── Source App preset chips ──────────────────────────────────
                Text('Source App',
                    style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _PresetChip(
                        label: 'Auto',
                        selected: _selectedPreset == null,
                        onTap: () => _selectPreset(null),
                      ),
                      for (final p in _presets)
                        _PresetChip(
                          label: p.name,
                          selected: _selectedPreset == p.id,
                          onTap: () => _selectPreset(p.id),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Data preview ─────────────────────────────────────────────
                if (widget.rows.isNotEmpty) ...[
                  Text('First row preview',
                      style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 16,
                      headingRowHeight: 32,
                      dataRowMinHeight: 28,
                      dataRowMaxHeight: 28,
                      columns: widget.fileHeaders
                          .map((h) => DataColumn(
                                label: Text(h,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold)),
                              ))
                          .toList(),
                      rows: [
                        DataRow(
                          cells: List.generate(
                            widget.fileHeaders.length,
                            (i) => DataCell(Text(
                              i < widget.rows[0].length
                                  ? widget.rows[0][i].toString()
                                  : '',
                              style: const TextStyle(fontSize: 11),
                            )),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 24),
                ],

                // ── Mapping rows ─────────────────────────────────────────────
                for (final field in _appFields) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              field.required
                                  ? '${field.label} *'
                                  : field.label,
                              style:
                                  Theme.of(context).textTheme.bodySmall?.copyWith(
                                        fontWeight: field.required
                                            ? FontWeight.bold
                                            : null,
                                      ),
                            ),
                            if (field.hint != null)
                              Text(
                                field.hint!,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      fontSize: 10,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outline,
                                    ),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: _mapping[field.key],
                          items: dropdownItems,
                          onChanged: (v) => setState(() {
                            _mapping[field.key] = v;
                            _preview = _computePreview();
                          }),
                          hint: Text(_notMapped,
                              style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant
                                      .withValues(alpha: 0.75))),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 8),
                ],

                const SizedBox(height: 8),

                // ── Options ──────────────────────────────────────────────────
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Skip duplicate sessions'),
                  subtitle: const Text(
                      'Skip rows whose date, buy-in, and cash-out match an existing session.'),
                  value: _skipDuplicates,
                  onChanged: _overwrite
                      ? null
                      : (v) => setState(() => _skipDuplicates = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Overwrite existing sessions'),
                  subtitle: const Text(
                      'Delete all current sessions before importing.'),
                  value: _overwrite,
                  onChanged: (v) => setState(() {
                    _overwrite = v;
                    if (v) _skipDuplicates = false;
                  }),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withAlpha(30),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withAlpha(80)),
                    ),
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.red)),
                  ),
                ],
              ],
            ),
          ),

          // ── Import button ────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed:
                      (_importing || _preview.valid == 0) ? null : _import,
                  child: _importing
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Theme.of(context).colorScheme.onPrimary),
                        )
                      : Text(_overwrite
                          ? 'Import & overwrite  (${_preview.valid} rows)'
                          : 'Import ${_preview.valid} rows'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Preset chip ─────────────────────────────────────────────────────────────

class _PresetChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

// ─── Preview Card ─────────────────────────────────────────────────────────────

class _PreviewCard extends StatelessWidget {
  final _ImportPreview preview;

  const _PreviewCard({required this.preview});

  @override
  Widget build(BuildContext context) {
    final pct = preview.total > 0
        ? (preview.valid / preview.total * 100).round()
        : 0;
    final color =
        pct >= 90 ? Colors.green : pct >= 50 ? Colors.amber : Colors.red;

    String dateRange = '';
    if (preview.dateMin != null && preview.dateMax != null) {
      final fmt = DateFormat('MMM d, yyyy');
      final min = fmt.format(DateTime.parse(preview.dateMin!));
      final max = fmt.format(DateTime.parse(preview.dateMax!));
      dateRange = preview.dateMin == preview.dateMax ? min : '$min – $max';
    }

    final extraIssues =
        preview.total - preview.valid - preview.issues.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  preview.valid > 0
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                  size: 18,
                  color: color,
                ),
                const SizedBox(width: 8),
                Text(
                  '${preview.valid} of ${preview.total} rows ready to import',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                ),
              ],
            ),
            if (dateRange.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Sessions: $dateRange',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            ],
            if (preview.issues.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final issue in preview.issues)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Row ${issue.rowNum}: ${issue.message}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.orange,
                        ),
                  ),
                ),
              if (extraIssues > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '… and $extraIssues more',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.orange,
                        ),
                  ),
                ),
            ],
            if (preview.stakesWarning != null) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      size: 15, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      preview.stakesWarning!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
