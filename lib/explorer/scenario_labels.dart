// GTO Explorer — display names for scenario keys + seat labels per position.
// Keys match the solve grid (tool/solver/freq_grid.dart kScenarios) and the
// live derivation (villain_range._deriveScenarioKey).

String scenarioDisplayName(String key) => switch (key) {
      'srp_late_v_bb' => 'BTN vs BB · single-raised',
      '3bp_bb_v_btn' => 'BTN vs BB · 3-bet pot',
      _ => key,
    };

/// Seat label for a position in a scenario (both current scenarios are
/// BB (OOP) vs BTN (IP); fall back to the generic position).
String seatLabel(String scenario, {required bool isOop}) => switch (scenario) {
      'srp_late_v_bb' || '3bp_bb_v_btn' => isOop ? 'BB' : 'BTN',
      _ => isOop ? 'OOP' : 'IP',
    };
