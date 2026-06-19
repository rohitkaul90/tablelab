import 'package:flutter/material.dart';
import '../models/session_model.dart';
import '../utils/helpers.dart';

/// Single-select Cash / Tournament filter pills (with toggle-off).
///
/// Two [FilterChip]s, each wrapped in [Expanded] so they fill the row width
/// (no trailing dead space) and never wrap to a second line. There is no "All"
/// chip. Selection is shown via the fill colour (`showCheckmark: false`) so a
/// selected chip doesn't widen and overflow.
///
/// Behaviour: tapping a chip selects *exactly* that type. Tapping the
/// already-selected chip clears the selection. An **empty** `Set<String>` means
/// "all game types" (neither chip highlighted) — so the user can swing from
/// cash → tournament → all with single taps.
class GameTypeFilterChips extends StatelessWidget {
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  const GameTypeFilterChips({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  void _toggle(String key) {
    // Single-select with toggle-off: re-tapping the selected chip → all.
    onChanged(selected.contains(key) ? <String>{} : {key});
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final entry in const [('cash', 'Cash'), ('tournament', 'Tournament')])
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: entry.$1 == 'cash' ? 8 : 0),
              child: FilterChip(
                label: SizedBox(
                  width: double.infinity,
                  child: Text(entry.$2, textAlign: TextAlign.center),
                ),
                selected: selected.contains(entry.$1),
                showCheckmark: false,
                onSelected: (_) => _toggle(entry.$1),
              ),
            ),
          ),
      ],
    );
  }
}

/// Default game-type selection for the filter pills: the game type of the
/// most-recently-played session. Returns a single-element set so the view opens
/// focused on the format the user last played. When there are **no sessions**
/// (a brand-new user) it returns an **empty set** — both pills deselected
/// (= all) — so the default "triggers" to the last-played type only once the
/// user starts recording.
Set<String> defaultGameTypes(List<SessionModel> sessions) {
  final mostRecent = mostRecentSession(sessions);
  if (mostRecent == null) return <String>{};
  return {isTournamentType(mostRecent.gameType) ? 'tournament' : 'cash'};
}

/// The game-type key ('cash' | 'tournament') a session falls under.
String gameTypeKey(SessionModel s) =>
    isTournamentType(s.gameType) ? 'tournament' : 'cash';

/// Narrows [sessions] to the selected game-type [types]. An empty set means
/// "all game types" (no filtering). Shared by the Overview and Analytics tabs
/// so the two never drift on how game type is matched.
List<SessionModel> filterByGameTypes(
    List<SessionModel> sessions, Set<String> types) {
  if (types.isEmpty) return sessions;
  return sessions.where((s) => types.contains(gameTypeKey(s))).toList();
}

/// The active game-type filter as a chip label ('Cash' | 'Tournament'), or null
/// when no single type is selected (= all).
String? gameTypeChipLabel(Set<String> types) {
  if (types.isEmpty) return null;
  return types.contains('tournament') ? 'Tournament' : 'Cash';
}
