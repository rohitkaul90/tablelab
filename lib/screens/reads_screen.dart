import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/player_read.dart';
import '../services/analytics_service.dart';
import '../providers/reads_provider.dart';
import '../reads/tag_definitions.dart';
import '../widgets/app_drawer.dart';
import '../widgets/reads/quick_add_sheet.dart';
import 'read_detail_screen.dart';

class ReadsScreen extends ConsumerStatefulWidget {
  const ReadsScreen({super.key});

  @override
  ConsumerState<ReadsScreen> createState() => _ReadsScreenState();
}

class _ReadsScreenState extends ConsumerState<ReadsScreen> {
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openQuickAdd(List<PlayerRead> allPlayers) {
    final svc = ref.read(readsServiceProvider);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => QuickAddSheet(
        allPlayers: allPlayers,
        onSaved: (label, tags, note) async {
          try {
            final read = await svc.createRead(playerLabel: label, tags: tags);
            AnalyticsService.readCreated(tagCount: tags.length);
            if (note != null &&
                (note.noteText?.isNotEmpty == true ||
                    note.position != null ||
                    note.action != null ||
                    note.street != null ||
                    note.sizing != null ||
                    note.cardsShown != null)) {
              await svc.addNote(
                read.id,
                noteText: note.noteText,
                position: note.position,
                action: note.action,
                sizing: note.sizing,
                street: note.street,
                cardsShown: note.cardsShown,
              );
            }
            if (mounted) ref.invalidate(readsProvider);
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to save read: $e')),
              );
            }
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final readsAsync = ref.watch(readsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => mainScaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text('Player Reads'),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search players…',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _search = '');
                        },
                      )
                    : null,
              ),
            ),
          ),

          // List
          Expanded(
            child: readsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (reads) {
                final filtered = _search.isEmpty
                    ? reads
                    : reads
                        .where((r) => r.playerLabel.toLowerCase().contains(_search))
                        .toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.psychology_outlined,
                              size: 52,
                              color: Theme.of(context).colorScheme.outline),
                          const SizedBox(height: 12),
                          Text(
                            _search.isEmpty
                                ? 'No reads yet.\nTap + to log your first opponent.'
                                : 'No players match "$_search".',
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withValues(alpha: 0.75)),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: filtered.length,
                  separatorBuilder: (ctx, i) => const SizedBox(height: 6),
                  itemBuilder: (_, i) => _ReadTile(
                    read: filtered[i],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => ReadDetailScreen(read: filtered[i])),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: readsAsync.maybeWhen(
        data: (reads) => FloatingActionButton.extended(
          heroTag: 'fab_reads',
          onPressed: () => _openQuickAdd(reads),
          icon: const Icon(Icons.person_add_outlined),
          label: const Text('Add Read'),
        ),
        orElse: () => null,
      ),
    );
  }
}

// ── List tile ──────────────────────────────────────────────────────────────

class _ReadTile extends StatelessWidget {
  final PlayerRead read;
  final VoidCallback onTap;

  const _ReadTile({required this.read, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final archetypes = read.tags.where(isArchetype).toList();
    final tendencies = read.tags.where((t) => !isArchetype(t)).toList();
    final displayTags = [...archetypes, ...tendencies].take(4).toList();
    final ago = _timeAgo(read.updatedAt);

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 20,
                backgroundColor: archetypes.isNotEmpty
                    ? tagColor(archetypes.first).withAlpha(60)
                    : theme.colorScheme.primary.withAlpha(40),
                child: Text(
                  read.playerLabel.isNotEmpty
                      ? read.playerLabel[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: archetypes.isNotEmpty
                        ? readableTagColor(context, tagColor(archetypes.first))
                        : theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Name + tags
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(read.playerLabel,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    if (displayTags.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 4,
                        runSpacing: 2,
                        children: displayTags.map((t) {
                          final c = tagColor(t);
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: c.withAlpha(40),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(tagDisplayName(t),
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: readableTagColor(context, c))),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),

              // Timestamp
              Text(ago,
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.75))),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right,
                  size: 18, color: Theme.of(context).colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) { return '${diff.inMinutes}m ago'; }
    if (diff.inHours < 24) { return '${diff.inHours}h ago'; }
    if (diff.inDays < 7) { return '${diff.inDays}d ago'; }
    if (diff.inDays < 30) { return '${(diff.inDays / 7).floor()}w ago'; }
    return '${(diff.inDays / 30).floor()}mo ago';
  }
}

