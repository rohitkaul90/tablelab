// GTO Explorer — display names for scenario keys + seat labels per position.
// Keys match the solve grid (tool/solver/freq_grid.dart kScenarios) and the
// live derivation (villain_range._deriveScenarioKey).

String scenarioDisplayName(String key) => switch (key) {
      'srp_late_v_bb' => 'BTN vs BB · single-raised',
      'srp_middle_v_bb' => 'CO vs BB · single-raised',
      'srp_early_v_bb' => 'EP vs BB · single-raised',
      'srp_sb_v_bb' => 'SB vs BB · single-raised',
      '3bp_bb_v_btn' => 'BTN vs BB · 3-bet pot',
      _ => key,
    };

/// Seat label for a position in a scenario. OOP is the BB in the bucketed-
/// opener scenarios — EXCEPT blind-vs-blind (srp_sb_v_bb), where the SB opener
/// is OOP and the BB caller is IP.
String seatLabel(String scenario, {required bool isOop}) => switch (scenario) {
      'srp_late_v_bb' || '3bp_bb_v_btn' => isOop ? 'BB' : 'BTN',
      'srp_middle_v_bb' => isOop ? 'BB' : 'CO',
      'srp_early_v_bb' => isOop ? 'BB' : 'EP',
      'srp_sb_v_bb' => isOop ? 'SB' : 'BB',
      _ => isOop ? 'OOP' : 'IP',
    };
