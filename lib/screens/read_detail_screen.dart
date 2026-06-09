import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../models/player_read.dart';
import '../providers/reads_provider.dart';
import '../reads/insights_engine.dart';
import '../reads/tag_definitions.dart';
import '../widgets/reads/quick_add_sheet.dart';
import '../widgets/reads/archetype_glossary.dart';

class ReadDetailScreen extends ConsumerStatefulWidget {
  final PlayerRead read;
  const ReadDetailScreen({super.key, required this.read});

  @override
  ConsumerState<ReadDetailScreen> createState() => _ReadDetailScreenState();
}

class _ReadDetailScreenState extends ConsumerState<ReadDetailScreen> {
  late PlayerRead _read;
  List<PlayerReadNote> _notes = [];
  bool _loadingNotes = true;

  @override
  void initState() {
    super.initState();
    _read = widget.read;
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    setState(() => _loadingNotes = true);
    try {
      final notes = await ref.read(readsServiceProvider).fetchNotes(_read.id);
      if (mounted) { setState(() { _notes = notes; _loadingNotes = false; }); }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingNotes = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load notes: $e')),
        );
      }
    }
  }

  void _openAddNote() {
    final svc = ref.read(readsServiceProvider);
    final allPlayers = ref.read(readsProvider).valueOrNull ?? [];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => QuickAddSheet(
        existingPlayer: _read,
        allPlayers: allPlayers,
        onSaved: (label, tags, note) async {
          try {
            // Update label/tags if changed
            if (label != _read.playerLabel || !_tagsEqual(tags, _read.tags)) {
              await svc.updateRead(_read.id, playerLabel: label, tags: tags);
            }
            if (note != null &&
                (note.noteText?.isNotEmpty == true ||
                    note.position != null ||
                    note.action != null ||
                    note.street != null ||
                    note.sizing != null ||
                    note.cardsShown != null)) {
              await svc.addNote(
                _read.id,
                noteText: note.noteText,
                position: note.position,
                action: note.action,
                sizing: note.sizing,
                street: note.street,
                cardsShown: note.cardsShown,
              );
            }
            if (!mounted) return;
            ref.invalidate(readsProvider);
            await _loadNotes();
            if (!mounted) return;
            // Reflect label/tag edits locally — provider re-fetch is async.
            setState(() => _read = PlayerRead(
                  id: _read.id,
                  userId: _read.userId,
                  playerLabel: label,
                  tags: tags,
                  createdAt: _read.createdAt,
                  updatedAt: DateTime.now(),
                ));
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to save: $e')),
              );
            }
          }
        },
      ),
    );
  }

  void _editNote(PlayerReadNote note) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _EditNoteSheet(
        note: note,
        onSave: (noteText, position, action, sizing, street, cardsShown) async {
          try {
            await ref.read(readsServiceProvider).updateNote(
              note.id,
              noteText: noteText,
              position: position,
              action: action,
              sizing: sizing,
              street: street,
              cardsShown: cardsShown,
            );
            if (mounted) await _loadNotes();
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to update note: $e')),
              );
            }
          }
        },
      ),
    );
  }

  Future<void> _deleteNote(PlayerReadNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete note?'),
        content: const Text('This observation will be permanently removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ref.read(readsServiceProvider).deleteNote(note.id);
        _loadNotes();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete: $e')),
          );
        }
      }
    }
  }

  void _shareRead() {
    final buf = StringBuffer();
    buf.writeln('Player Read: ${_read.playerLabel}');
    if (_read.tags.isNotEmpty) {
      buf.writeln('Tags: ${_read.tags.map(tagDisplayName).join(', ')}');
    }
    if (_notes.isNotEmpty) {
      buf.writeln();
      buf.writeln('Observations:');
      for (final note in _notes) {
        final parts = <String>[];
        if (note.position != null) parts.add('Pos: ${note.position}');
        if (note.street != null) parts.add('Street: ${note.street}');
        if (note.action != null) parts.add('Action: ${note.action}');
        if (note.sizing != null) parts.add('Sizing: ${note.sizing}');
        if (note.cardsShown != null) parts.add('Cards: ${note.cardsShown}');
        if (note.noteText?.isNotEmpty == true) parts.add(note.noteText!);
        if (parts.isNotEmpty) buf.writeln('• ${parts.join(' · ')}');
      }
    }
    SharePlus.instance.share(
        ShareParams(subject: 'Player Read', text: buf.toString().trim()));
  }

  Future<void> _deleteRead() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${_read.playerLabel}?'),
        content: const Text('All observations for this player will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(readsServiceProvider).deleteRead(_read.id);
      if (!mounted) return;
      ref.invalidate(readsProvider);
      Navigator.pop(context);
    }
  }

  bool _tagsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) { return false; }
    final sa = a.toSet();
    return b.every(sa.contains);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final insights = getInsights(_read.tags);
    final archetypes = _read.tags.where(isArchetype).toList();
    final tendencies = _read.tags.where((t) => !isArchetype(t)).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_read.playerLabel),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined, size: 20),
            tooltip: 'Share notes',
            onPressed: _shareRead,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            color: Colors.redAccent,
            tooltip: 'Delete player',
            onPressed: _deleteRead,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Tags ─────────────────────────────────────────────────────────
          if (_read.tags.isNotEmpty) ...[
            Row(
              children: [
                _SectionLabel('Tags'),
                if (archetypes.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => showArchetypeGlossary(context),
                    child: Icon(Icons.info_outline,
                        size: 15, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            if (archetypes.isNotEmpty) ...[
              Wrap(
                spacing: 8, runSpacing: 8,
                children: archetypes.map((t) {
                  final c = tagColor(t);
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: c.withAlpha(50),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: c.withAlpha(120), width: 1.5),
                    ),
                    child: Text(tagDisplayName(t),
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: readableTagColor(context, c))),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
            ],
            if (tendencies.isNotEmpty)
              Wrap(
                spacing: 6, runSpacing: 6,
                children: tendencies.map((t) {
                  final c = tagColor(t);
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: c.withAlpha(45),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: c.withAlpha(110)),
                    ),
                    child: Text(tagDisplayName(t),
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: readableTagColor(context, c))),
                  );
                }).toList(),
              ),
            const SizedBox(height: 20),
          ],

          // ── Insights ──────────────────────────────────────────────────────
          if (insights.isNotEmpty) ...[
            _SectionLabel('Strategy Notes'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withAlpha(20),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: theme.colorScheme.primary.withAlpha(50)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: insights.map((ins) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.tips_and_updates_outlined,
                            size: 14,
                            color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(ins.tip,
                                  style: const TextStyle(fontSize: 13, height: 1.4)),
                              if (ins.basis != null)
                                Text('Based on: ${ins.basis}',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: theme.colorScheme.primary.withAlpha(180))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 20),
          ],

          // ── Observations ──────────────────────────────────────────────────
          Row(
            children: [
              _SectionLabel('Observations'),
              const Spacer(),
              Text('${_notes.length} total',
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.75))),
            ],
          ),
          const SizedBox(height: 8),

          if (_loadingNotes)
            const Center(child: CircularProgressIndicator())
          else if (_notes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'No observations yet.\nTap + to add one.',
                  style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.75)),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            for (final note in _notes)
              _NoteTile(
                note: note,
                onEdit: () => _editNote(note),
                onDelete: () => _deleteNote(note),
              ),

          const SizedBox(height: 80),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_read_detail',
        onPressed: _openAddNote,
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('Add Observation'),
      ),
    );
  }
}

// ── Note tile ──────────────────────────────────────────────────────────────

class _NoteTile extends StatelessWidget {
  final PlayerReadNote note;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _NoteTile({required this.note, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dismissible(
      key: Key(note.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: Colors.redAccent.withAlpha(60),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.redAccent),
      ),
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onEdit,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (note.position != null ||
                    note.street != null ||
                    note.action != null ||
                    note.sizing != null ||
                    note.cardsShown != null) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (note.position != null)
                        _MetaChip(note.position!, color: Colors.blue.shade300),
                      if (note.street != null)
                        _MetaChip(note.street!, color: Colors.orange.shade300),
                      if (note.action != null)
                        _MetaChip(note.action!,
                            color: theme.colorScheme.primary.withAlpha(200)),
                      if (note.sizing != null)
                        _MetaChip(note.sizing!,
                            color: theme.colorScheme.onSurfaceVariant),
                      if (note.cardsShown != null)
                        _MetaChip('🂠 ${note.cardsShown!}', color: Colors.amber),
                    ],
                  ),
                  if (note.noteText?.isNotEmpty == true) const SizedBox(height: 6),
                ],
                if (note.noteText?.isNotEmpty == true)
                  Text(note.noteText!,
                      style: const TextStyle(fontSize: 13, height: 1.4)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(_formatDate(note.createdAt),
                        style: TextStyle(
                            fontSize: 10,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.75))),
                    const Spacer(),
                    Icon(Icons.edit_outlined,
                        size: 12, color: theme.colorScheme.outline),
                    const SizedBox(width: 2),
                    Text('tap to edit',
                        style: TextStyle(
                            fontSize: 10, color: theme.colorScheme.outline)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) { return '${diff.inMinutes}m ago'; }
    if (diff.inHours < 24) { return '${diff.inHours}h ago'; }
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final Color color;
  const _MetaChip(this.label, {required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.withAlpha(40),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: readableTagColor(context, color))),
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

// ── Edit note sheet ────────────────────────────────────────────────────────

const List<String> _kPositions = ['UTG', 'UTG+1', 'UTG+2', 'MP', 'HJ', 'CO', 'BTN', 'SB', 'BB'];
const List<String> _kActions  = ['Limp', 'Open', 'Call', 'Cold-Call', '3-Bet', '4-Bet', 'Jam', 'Check', 'Bet', 'Check-Raise', 'Fold'];
const List<String> _kStreets  = ['Preflop', 'Flop', 'Turn', 'River'];

class _EditNoteSheet extends StatefulWidget {
  final PlayerReadNote note;
  final Future<void> Function(
    String? noteText,
    String? position,
    String? action,
    String? sizing,
    String? street,
    String? cardsShown,
  ) onSave;

  const _EditNoteSheet({required this.note, required this.onSave});

  @override
  State<_EditNoteSheet> createState() => _EditNoteSheetState();
}

class _EditNoteSheetState extends State<_EditNoteSheet> {
  late final TextEditingController _noteCtrl;
  late final TextEditingController _sizingCtrl;
  late final TextEditingController _cardsCtrl;
  String? _position;
  String? _action;
  String? _street;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _noteCtrl   = TextEditingController(text: widget.note.noteText ?? '');
    _sizingCtrl = TextEditingController(text: widget.note.sizing ?? '');
    _cardsCtrl  = TextEditingController(text: widget.note.cardsShown ?? '');
    _position   = widget.note.position;
    _action     = widget.note.action;
    _street     = widget.note.street;
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    _sizingCtrl.dispose();
    _cardsCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.onSave(
        _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        _position,
        _action,
        _sizingCtrl.text.trim().isEmpty ? null : _sizingCtrl.text.trim(),
        _street,
        _cardsCtrl.text.trim().isEmpty ? null : _cardsCtrl.text.trim(),
      );
      if (mounted) { Navigator.pop(context); }
    } catch (_) {
      if (mounted) { setState(() => _saving = false); }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        minChildSize: 0.5,
        maxChildSize: 0.92,
        builder: (context, scroll) {
          return Column(
            children: [
              // Handle
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.outline,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('Edit Observation',
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
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
                      const SizedBox(height: 14),

                      // Position + Street
                      Row(
                        children: [
                          Expanded(child: _DropField(
                            label: 'Position', value: _position, items: _kPositions,
                            onChanged: (v) => setState(() => _position = v),
                          )),
                          const SizedBox(width: 10),
                          Expanded(child: _DropField(
                            label: 'Street', value: _street, items: _kStreets,
                            onChanged: (v) => setState(() => _street = v),
                          )),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Action + Sizing
                      Row(
                        children: [
                          Expanded(child: _DropField(
                            label: 'Action', value: _action, items: _kActions,
                            onChanged: (v) => setState(() => _action = v),
                          )),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _sizingCtrl,
                              decoration: InputDecoration(
                                labelText: 'Sizing',
                                hintText: '4x / 75%',
                                filled: true, isDense: true,
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Cards shown
                      TextField(
                        controller: _cardsCtrl,
                        decoration: InputDecoration(
                          labelText: 'Cards shown',
                          hintText: 'AKo, JJ, 45s…',
                          filled: true, isDense: true,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Free text note
                      TextField(
                        controller: _noteCtrl,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: 'Note',
                          hintText: 'Any other observations…',
                          filled: true,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimary))
                              : const Icon(Icons.save_outlined),
                          label: Text(_saving ? 'Saving…' : 'Save Changes'),
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
        filled: true, isDense: true,
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
            ...items.map((i) => DropdownMenuItem(
                value: i, child: Text(i, style: const TextStyle(fontSize: 13)))),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}
