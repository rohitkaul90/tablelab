// The Edge Function returns the model's raw tool output. Claude occasionally
// MALFORMS the tool call (e.g. emits a street as a string containing the literal
// `<parameter name="decision">…` tag instead of an object, or `wasGto` as a
// non-bool), and a strict `as Map`/`as bool` cast then crashes the whole analysis
// screen — losing the user's quota + the API cost with nothing shown. These
// helpers degrade gracefully instead: a wrong-typed field is dropped, so the
// salvageable parts (summary / verdict / keyMistake / facts) still render.
String? _asString(dynamic v) => v is String ? v : null;
StreetFeedback? _asStreet(dynamic v) =>
    v is Map<String, dynamic> ? StreetFeedback.fromJson(v) : null;

class StreetFeedback {
  final String decision;
  final String optimal;
  final String rationale;
  final bool wasGto;

  /// 'high' | 'medium' | 'low' — model self-reported. Null on analyses cached
  /// before the field was added to the tool schema (render nothing then).
  final String? confidence;

  /// "Also defensible: …" — a second reasonable line for the spot. Null when
  /// the model considers the optimal play clearly unique, or on legacy
  /// cached analyses.
  final String? alternative;

  const StreetFeedback({
    required this.decision,
    required this.optimal,
    required this.rationale,
    required this.wasGto,
    this.confidence,
    this.alternative,
  });

  factory StreetFeedback.fromJson(Map<String, dynamic> j) => StreetFeedback(
        decision: _asString(j['decision']) ?? '',
        optimal: _asString(j['optimal']) ?? '',
        rationale: _asString(j['rationale']) ?? '',
        wasGto: j['wasGto'] is bool ? j['wasGto'] as bool : true,
        confidence: _asString(j['confidence']),
        alternative: _asString(j['alternative']),
      );
}

class HandCoachingAnalysis {
  final String summary;
  final String verdict; // 'highEV' | 'neutral' | 'leakDetected'
  final String? keyMistake;
  final StreetFeedback? preflop;
  final StreetFeedback? flop;
  final StreetFeedback? turn;
  final StreetFeedback? river;

  /// The deterministic `[FACT —]` ground-truth lines the Edge Function
  /// injected into the prompt — "what the AI was told". Empty for analyses
  /// cached before the function started returning them.
  final List<String> facts;

  const HandCoachingAnalysis({
    required this.summary,
    required this.verdict,
    this.keyMistake,
    this.preflop,
    this.flop,
    this.turn,
    this.river,
    this.facts = const [],
  });

  factory HandCoachingAnalysis.fromJson(Map<String, dynamic> j) =>
      HandCoachingAnalysis(
        summary: _asString(j['summary']) ?? '',
        verdict: _asString(j['verdict']) ?? 'neutral',
        keyMistake: _asString(j['keyMistake']),
        // whereType filters out any non-string element the model slipped in.
        facts: j['facts'] is List
            ? (j['facts'] as List).whereType<String>().toList()
            : const [],
        // A street the model malformed (string / non-object) drops to null
        // rather than crashing the screen — see _asStreet.
        preflop: _asStreet(j['preflop']),
        flop: _asStreet(j['flop']),
        turn: _asStreet(j['turn']),
        river: _asStreet(j['river']),
      );

  /// True when the response parsed to essentially nothing usable — every street
  /// dropped AND no summary/keyMistake — i.e. the model returned a malformed
  /// tool call. Callers can show a "couldn't read the response, re-analyze" hint
  /// instead of a blank but technically-valid analysis.
  bool get isEmpty =>
      preflop == null &&
      flop == null &&
      turn == null &&
      river == null &&
      summary.trim().isEmpty &&
      (keyMistake == null || keyMistake!.trim().isEmpty);
}

class SessionAnalysis {
  final String narrative;
  final List<String> leaksIdentified;
  final String actionableTip;

  const SessionAnalysis({
    required this.narrative,
    required this.leaksIdentified,
    required this.actionableTip,
  });

  factory SessionAnalysis.fromJson(Map<String, dynamic> j) => SessionAnalysis(
        narrative: j['narrative'] as String? ?? '',
        leaksIdentified:
            List<String>.from(j['leaksIdentified'] as List? ?? []),
        actionableTip: j['actionableTip'] as String? ?? '',
      );
}
