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

/// A street is MALFORMED when the model botched it — present but not a proper
/// object (a string/array), or an object whose `wasGto` isn't a bool. A street
/// the hand never reached is simply absent (null) and is NOT malformed. Used to
/// flag a degraded analysis so the screen prompts re-analyze rather than render
/// a coaching view that references a street whose card silently vanished.
bool _streetMalformed(dynamic v) {
  if (v == null) return false; // legitimately absent (e.g. folded pre-river)
  if (v is! Map<String, dynamic>) return true; // string / array / scalar
  final g = v['wasGto'];
  return g != null && g is! bool; // object, but a wrong-typed wasGto
}

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

  /// True when the model BOTCHED the tool call — any street arrived present but
  /// malformed (a string/array, or a wrong-typed `wasGto`). We then can't trust
  /// the coaching: the verdict/keyMistake may reference a street whose card was
  /// dropped, so the screen prompts a re-analyze rather than render a misleading
  /// partial view. (A legitimately-absent street does NOT set this.)
  final bool malformed;

  const HandCoachingAnalysis({
    required this.summary,
    required this.verdict,
    this.keyMistake,
    this.preflop,
    this.flop,
    this.turn,
    this.river,
    this.facts = const [],
    this.malformed = false,
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
        // rather than crashing the screen — see _asStreet — and flips `malformed`.
        preflop: _asStreet(j['preflop']),
        flop: _asStreet(j['flop']),
        turn: _asStreet(j['turn']),
        river: _asStreet(j['river']),
        malformed: _streetMalformed(j['preflop']) ||
            _streetMalformed(j['flop']) ||
            _streetMalformed(j['turn']) ||
            _streetMalformed(j['river']),
      );
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
        // Same defensive parse as HandCoachingAnalysis — analyze-session returns
        // the same kind of model tool output, so a botched call must not crash.
        narrative: _asString(j['narrative']) ?? '',
        leaksIdentified: j['leaksIdentified'] is List
            ? (j['leaksIdentified'] as List).whereType<String>().toList()
            : const [],
        actionableTip: _asString(j['actionableTip']) ?? '',
      );
}
