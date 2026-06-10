import 'package:flutter/material.dart';
import '../../models/player_read.dart';
import '../../reads/tag_definitions.dart';
import 'archetype_glossary.dart';

const List<String> _kPositions = ['UTG', 'UTG+1', 'UTG+2', 'MP', 'HJ', 'CO', 'BTN', 'SB', 'BB'];
const List<String> _kActions = ['Limp', 'Open', 'Call', 'Cold-Call', '3-Bet', '4-Bet', 'Jam', 'Check', 'Bet', 'Check-Raise', 'Fold'];
const List<String> _kStreets = ['Preflop', 'Flop', 'Turn', 'River'];

/// Fast capture sheet.  Pass [existingPlayer] when adding to a known opponent.
class QuickAddSheet extends StatefulWidget {
  final PlayerRead? existingPlayer;
  final List<PlayerRead> allPlayers;
  final Future<void> Function(
    String label,
    List<String> tags,
    NoteData? note,
  ) onSaved;

  const QuickAddSheet({
    super.key,
    required this.allPlayers,
    required this.onSaved,
    this.existingPlayer,
  });

  @override
  State<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<QuickAddSheet> {
  final _labelCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _sizingCtrl = TextEditingController();
  final _cardsCtrl = TextEditingController();

  Set<String> _tags = {};
  String? _position;
  String? _action;
  String? _street;
  bool _showHandDetails = false;
  bool _saving = false;

  // Autocomplete suggestions
  List<PlayerRead> _suggestions = [];
  PlayerRead? _pickedPlayer; // set when user taps a suggestion

  @override
  void initState() {
    super.initState();
    if (widget.existingPlayer != null) {
      _labelCtrl.text = widget.existingPlayer!.playerLabel;
      _pickedPlayer = widget.existingPlayer;
      _tags = widget.existingPlayer!.tags.toSet();
    }
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _noteCtrl.dispose();
    _sizingCtrl.dispose();
    _cardsCtrl.dispose();
    super.dispose();
  }

  void _onLabelChanged(String v) {
    if (_pickedPlayer != null && v != _pickedPlayer!.playerLabel) {
      setState(() { _pickedPlayer = null; _tags = {}; });
    }
    if (v.trim().isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    final lower = v.toLowerCase();
    setState(() {
      _suggestions = widget.allPlayers
          .where((p) => p.playerLabel.toLowerCase().contains(lower))
          .take(5)
          .toList();
    });
  }

  void _pickSuggestion(PlayerRead p) {
    setState(() {
      _pickedPlayer = p;
      _tags = p.tags.toSet();
      _labelCtrl.text = p.playerLabel;
      _suggestions = [];
    });
    FocusScope.of(context).unfocus();
  }

  void _toggleTag(String tag) => setState(() {
    if (_tags.contains(tag)) { _tags.remove(tag); } else { _tags.add(tag); }
  });

  bool get _canSave => _labelCtrl.text.trim().isNotEmpty;

  Future<void> _save() async {
    if (!_canSave) { return; }
    setState(() => _saving = true);

    final noteText = _noteCtrl.text.trim();
    final sizing = _sizingCtrl.text.trim();
    final cards = _cardsCtrl.text.trim();
    final hasNote = noteText.isNotEmpty || _position != null || _action != null ||
        _street != null || sizing.isNotEmpty || cards.isNotEmpty;

    final note = hasNote
        ? NoteData(
            noteText: noteText.isEmpty ? null : noteText,
            position: _position,
            action: _action,
            sizing: sizing.isEmpty ? null : sizing,
            street: _street,
            cardsShown: cards.isEmpty ? null : cards,
          )
        : null;

    try {
      await widget.onSaved(_labelCtrl.text.trim(), _tags.toList(), note);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExisting = widget.existingPlayer != null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.78,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scroll) {
        return Column(
          children: [
            _Handle(),
            Expanded(
              child: SingleChildScrollView(
                controller: scroll,
                padding: EdgeInsets.fromLTRB(
                    16, 8, 16, 24 + MediaQuery.paddingOf(context).bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header ─────────────────────────────────────────────
                    Row(
                      children: [
                        Text(
                          isExisting ? 'Add Observation' : 'New Player Read',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: _saving ? null : _save,
                          child: _saving
                              ? const SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Save'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // ── Player label ───────────────────────────────────────
                    if (!isExisting) ...[
                      TextField(
                        controller: _labelCtrl,
                        autofocus: true,
                        onChanged: _onLabelChanged,
                        decoration: InputDecoration(
                          labelText: 'Player name / label',
                          hintText: 'e.g. Seat 3, John, Red hat',
                          filled: true,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none),
                          prefixIcon: const Icon(Icons.person_outline, size: 20),
                        ),
                      ),
                      // Autocomplete dropdown
                      if (_suggestions.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          // Use Material (not a colored Container/DecoratedBox) so the
                          // ListTiles paint their background + ink splashes on a Material
                          // ancestor. A colored DecoratedBox between the ListTile and the
                          // nearest Material hides those effects and trips ListTile's
                          // _debugCheckBackgroundIsHidden assert in debug builds.
                          child: Material(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              children: _suggestions.map((p) => ListTile(
                                dense: true,
                                leading: const Icon(Icons.history, size: 16),
                                title: Text(p.playerLabel),
                                subtitle: p.tags.isNotEmpty
                                    ? Text(p.tags.map(tagDisplayName).take(3).join(' · '),
                                        style: const TextStyle(fontSize: 11))
                                    : null,
                                onTap: () => _pickSuggestion(p),
                              )).toList(),
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                    ] else ...[
                      Row(
                        children: [
                          Icon(Icons.person,
                              size: 18,
                              color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Text(
                            widget.existingPlayer!.playerLabel,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ── Archetype tags ─────────────────────────────────────
                    Row(
                      children: [
                        _SectionLabel('Player Type'),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => showArchetypeGlossary(context),
                          child: Icon(Icons.info_outline,
                              size: 15,
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: kArchetypeTags.entries.map((e) {
                        final selected = _tags.contains(e.key);
                        // Single-select: once one player type is picked, the
                        // others grey out (tap the selected one to switch).
                        final disabled = tagDisabled(e.key, _tags);
                        final color = tagColor(e.key);
                        return Opacity(
                          opacity: disabled ? 0.4 : 1.0,
                          child: GestureDetector(
                            onTap: disabled ? null : () => _toggleTag(e.key),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: selected ? color.withAlpha(50) : theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: selected
                                      ? color
                                      : theme.colorScheme.outlineVariant,
                                  width: selected ? 1.5 : 1,
                                ),
                              ),
                              child: Text(
                                e.value,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                                  color: selected
                                      ? color
                                      : theme.colorScheme.onSurface
                                          .withValues(alpha: 0.70),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // ── Tendency tags ──────────────────────────────────────
                    for (final group in kTendencyGroups.entries) ...[
                      _SectionLabel(group.key),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: group.value.entries.map((e) {
                          final selected = _tags.contains(e.key);
                          // null onSelected greys + disables the chip when a
                          // contradictory tendency is already selected.
                          final disabled = tagDisabled(e.key, _tags);
                          return FilterChip(
                            label: Text(e.value, style: const TextStyle(fontSize: 11)),
                            selected: selected,
                            onSelected:
                                disabled ? null : (_) => _toggleTag(e.key),
                            selectedColor: Colors.teal.withAlpha(60),
                            checkmarkColor: Colors.tealAccent,
                            side: BorderSide(
                              color: selected
                                  ? Colors.tealAccent.withAlpha(180)
                                  : theme.colorScheme.outline),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            visualDensity: VisualDensity.compact,
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // ── Quick note ─────────────────────────────────────────
                    _SectionLabel('Quick Note'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _noteCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'e.g. opened 4x UTG with 45o, triple-barrel bluffed',
                        filled: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Hand details (collapsible) ─────────────────────────
                    InkWell(
                      onTap: () => setState(() => _showHandDetails = !_showHandDetails),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                              _showHandDetails ? Icons.expand_less : Icons.expand_more,
                              size: 18,
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.75),
                            ),
                            const SizedBox(width: 4),
                            Text('Hand Details',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.75))),
                          ],
                        ),
                      ),
                    ),
                    if (_showHandDetails) ...[
                      const SizedBox(height: 8),
                      // Position + Street
                      Row(
                        children: [
                          Expanded(
                            child: _DropField(
                              label: 'Position',
                              value: _position,
                              items: _kPositions,
                              onChanged: (v) => setState(() => _position = v),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _DropField(
                              label: 'Street',
                              value: _street,
                              items: _kStreets,
                              onChanged: (v) => setState(() => _street = v),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Action + Sizing
                      Row(
                        children: [
                          Expanded(
                            child: _DropField(
                              label: 'Action',
                              value: _action,
                              items: _kActions,
                              onChanged: (v) => setState(() => _action = v),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _sizingCtrl,
                              decoration: InputDecoration(
                                labelText: 'Sizing',
                                hintText: '4x / 75%',
                                filled: true,
                                isDense: true,
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _cardsCtrl,
                        decoration: InputDecoration(
                          labelText: 'Cards shown',
                          hintText: 'AKo, JJ, 45s...',
                          filled: true,
                          isDense: true,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),

                    // ── Save button ────────────────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _canSave && !_saving ? _save : null,
                        icon: _saving
                            ? SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: theme.colorScheme.onPrimary))
                            : const Icon(Icons.save_outlined),
                        label: Text(_saving ? 'Saving…' : 'Save'),
                        style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    ),
    );
  }
}

// ── Internal helper widgets ────────────────────────────────────────────────

class _Handle extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Center(
          child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outline,
                borderRadius: BorderRadius.circular(2)),
          ),
        ),
      );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
          color: Theme.of(context).colorScheme.primary,
        ),
      );
}

class _DropField extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  const _DropField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        isDense: true,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          isExpanded: true,
          hint: Text('—',
              style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withValues(alpha: 0.75),
                  fontSize: 13)),
          items: [
            DropdownMenuItem<String>(
              value: null,
              child: Text('—',
                  style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.75))),
            ),
            ...items.map((i) => DropdownMenuItem(value: i, child: Text(i, style: const TextStyle(fontSize: 13)))),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ── Data class for note payload ────────────────────────────────────────────

class NoteData {
  final String? noteText;
  final String? position;
  final String? action;
  final String? sizing;
  final String? street;
  final String? cardsShown;

  const NoteData({
    this.noteText,
    this.position,
    this.action,
    this.sizing,
    this.street,
    this.cardsShown,
  });
}
