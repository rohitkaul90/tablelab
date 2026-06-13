// Single source of truth for "position + preflop line → GTO preset key".
//
// Both the Quick Hand synthesis classifier (quick_hand_synthesis.dart) and the
// trust-pack villain range model (villain_range.dart) map a player's seat and
// preflop action onto a `gtoPresets` chart key. These mappings used to be
// duplicated in both files and had already started to diverge — which would
// silently make the synthesized story and the equity cross-check disagree about
// the same villain's range. Keep that mapping here, once.
//
// `gtoPresets` keys are the contract; keep them stable (see CLAUDE.md).

import 'gto_ranges.dart';

/// All GTO presets indexed by their stable key.
final Map<String, Set<String>> presetByKey = {
  for (final p in gtoPresets) p.key: p.hands,
};

/// True when [hand] (e.g. "AKs") is in the chart at [key]. False for a null or
/// unknown key.
bool inChart(String? key, String hand) =>
    key != null && (presetByKey[key]?.contains(hand) ?? false);

/// Hero's seat class for response-chart lookup. The straddle is a blind post,
/// not a position — the straddler defends like a (wide) big blind.
String posClass(String label) => switch (label) {
      'BB' => 'bb',
      'SB' => 'sb',
      'STR' => 'bb',
      _ => 'ip',
    };

/// Buckets a KNOWN opener's position label: Early = UTG–MP, Middle = HJ/CO,
/// Late = BTN/SB (mirrors the bucketed response charts).
String openerBucketForLabel(String openerLabel) {
  switch (openerLabel) {
    case 'HJ':
    case 'CO':
      return 'middle';
    case 'BTN':
    case 'SB':
      return 'late';
    default:
      return 'early'; // UTG, UTG+1, UTG+2, MP, STR, exotic labels
  }
}

/// RFI (open-raise) chart key for a seat, or null for seats that never open
/// first (BB and exotic labels).
String? rfiKey(String label, bool trn) {
  const map = {
    'UTG': 'utg', 'UTG+1': 'utg1', 'UTG+2': 'utg2', 'MP': 'mp',
    'HJ': 'hj', 'CO': 'co', 'BTN': 'btn', 'SB': 'sb',
  };
  final pos = map[label];
  if (pos == null) return null;
  return '${trn ? 'trn' : 'cash'}_rfi_$pos';
}

/// Cold-call / defend chart key for a [posClass] facing an open from [bucket]
/// (the opener's bucket); [openerLabel] disambiguates the SB-open case.
String callKey(String posClass, String bucket, String openerLabel, bool trn) {
  if (trn) {
    if (posClass == 'bb') return 'trn_call_bb_vs_$bucket';
    return 'trn_call_ip_vs_early'; // only non-BB tournament call chart
  }
  switch (posClass) {
    case 'bb':
      if (openerLabel == 'SB') return 'cash_call_bb_vs_sb';
      return switch (bucket) {
        'early' => 'cash_call_bb_vs_utg',
        'middle' => 'cash_call_bb_vs_co',
        _ => 'cash_call_bb_vs_btn',
      };
    case 'sb':
      return 'cash_call_sb_vs_$bucket'; // early/middle/late charts all exist
    default:
      return switch (bucket) {
        'early' => 'cash_call_ip_vs_early',
        'middle' => 'cash_call_ip_vs_middle',
        _ => 'cash_call_btn_vs_co', // closest chart for IP vs a late open
      };
  }
}

/// 3-bet chart key for a [posClass] facing an open from [bucket].
String threeBetKey(String posClass, String bucket, bool trn) {
  if (trn) {
    return switch ((posClass, bucket)) {
      ('bb', 'late') => 'trn_3b_bb_vs_btn',
      ('bb', _) => 'trn_3b_bb_vs_early',
      ('sb', _) => 'trn_3b_sb_vs_late',
      ('ip', 'early') => 'trn_3b_ip_vs_early',
      _ => 'trn_3b_btn_vs_co',
    };
  }
  return switch ((posClass, bucket)) {
    ('bb', 'early') => 'cash_3b_bb_vs_utg',
    ('bb', 'middle') => 'cash_3b_bb_vs_co',
    ('bb', _) => 'cash_3b_bb_vs_btn',
    ('sb', 'early') => 'cash_3b_sb_vs_early',
    ('sb', 'middle') => 'cash_3b_sb_vs_middle',
    ('sb', _) => 'cash_3b_sb_vs_btn',
    ('ip', 'early') => 'cash_3b_ip_vs_early',
    _ => 'cash_3b_btn_vs_co',
  };
}

/// Continue-vs-3-bet (call) chart key.
String call3BetKey(String posClass, bool trn) => trn
    ? 'trn_call_3b'
    : (posClass == 'ip' ? 'cash_call_3b_ip' : 'cash_call_3b_oop');

/// 4-bet (value) chart key.
String fourBetKey(bool trn) => trn ? 'trn_4b_value' : 'cash_4b_value';
