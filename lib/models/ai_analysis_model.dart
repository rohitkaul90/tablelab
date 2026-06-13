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
        decision: j['decision'] as String? ?? '',
        optimal: j['optimal'] as String? ?? '',
        rationale: j['rationale'] as String? ?? '',
        wasGto: j['wasGto'] as bool? ?? true,
        confidence: j['confidence'] as String?,
        alternative: j['alternative'] as String?,
      );
}

class HandAnalysis {
  final int handIndex;
  final String summary;
  final StreetFeedback? preflop;
  final StreetFeedback? flop;
  final StreetFeedback? turn;
  final StreetFeedback? river;
  final String verdict; // 'highEV' | 'neutral' | 'leakDetected'

  const HandAnalysis({
    required this.handIndex,
    required this.summary,
    this.preflop,
    this.flop,
    this.turn,
    this.river,
    required this.verdict,
  });

  factory HandAnalysis.fromJson(Map<String, dynamic> j) => HandAnalysis(
        handIndex: j['handIndex'] as int? ?? 0,
        summary: j['summary'] as String? ?? '',
        preflop: j['preflop'] != null
            ? StreetFeedback.fromJson(j['preflop'] as Map<String, dynamic>)
            : null,
        flop: j['flop'] != null
            ? StreetFeedback.fromJson(j['flop'] as Map<String, dynamic>)
            : null,
        turn: j['turn'] != null
            ? StreetFeedback.fromJson(j['turn'] as Map<String, dynamic>)
            : null,
        river: j['river'] != null
            ? StreetFeedback.fromJson(j['river'] as Map<String, dynamic>)
            : null,
        verdict: j['verdict'] as String? ?? 'neutral',
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
        summary: j['summary'] as String? ?? '',
        verdict: j['verdict'] as String? ?? 'neutral',
        keyMistake: j['keyMistake'] as String?,
        facts: List<String>.from(j['facts'] as List? ?? const []),
        preflop: j['preflop'] != null
            ? StreetFeedback.fromJson(j['preflop'] as Map<String, dynamic>)
            : null,
        flop: j['flop'] != null
            ? StreetFeedback.fromJson(j['flop'] as Map<String, dynamic>)
            : null,
        turn: j['turn'] != null
            ? StreetFeedback.fromJson(j['turn'] as Map<String, dynamic>)
            : null,
        river: j['river'] != null
            ? StreetFeedback.fromJson(j['river'] as Map<String, dynamic>)
            : null,
      );
}

class SessionAnalysis {
  final String narrative;
  final List<String> keyThemes;
  final List<String> leaksIdentified;
  final String actionableTip;
  final List<HandAnalysis> handAnalyses;

  const SessionAnalysis({
    required this.narrative,
    required this.keyThemes,
    required this.leaksIdentified,
    required this.actionableTip,
    required this.handAnalyses,
  });

  factory SessionAnalysis.fromJson(Map<String, dynamic> j) => SessionAnalysis(
        narrative: j['narrative'] as String? ?? '',
        keyThemes:
            List<String>.from(j['keyThemes'] as List? ?? []),
        leaksIdentified:
            List<String>.from(j['leaksIdentified'] as List? ?? []),
        actionableTip: j['actionableTip'] as String? ?? '',
        handAnalyses: (j['handAnalyses'] as List? ?? [])
            .map((h) => HandAnalysis.fromJson(h as Map<String, dynamic>))
            .toList(),
      );
}
