import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/session_model.dart';
import '../utils/helpers.dart';

/// A session as a card: header (icon · stakes/date · result) over a metrics
/// strip (duration, win rate, and BB/100 for cash or ROI for tournaments).
/// Lower density than a plain row, but every metric is always visible.
class SessionTile extends StatelessWidget {
  final SessionModel session;
  final VoidCallback? onTap;

  const SessionTile({super.key, required this.session, this.onTap});

  /// Compact, signed hourly rate (e.g. "+CA$163/hr", "+CA$1.1k/hr").
  static String _fmtPerHr(double rate, String currency) {
    final sym = currencySymbol(currency);
    final abs = rate.abs();
    final body = abs >= 1000
        ? '${(abs / 1000).toStringAsFixed(1)}k'
        : abs.round().toString();
    return '${rate >= 0 ? '+' : '-'}$sym$body/hr';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plColor = session.profitLoss >= 0 ? Colors.green : Colors.red;
    final date = DateFormat('MMM d').format(DateTime.parse(session.date));
    final dur = formatDuration(session.durationMinutes);
    final isTournament = isTournamentType(session.gameType);
    final location = session.location ?? gameTypeLabel(session.gameType);

    // Metric strip — value, label, optional sign colour.
    final cells = <(String, String, Color?)>[('Duration', dur, null)];
    final hours = session.durationMinutes / 60.0;
    if (hours > 0) {
      final rate = session.profitLoss / hours;
      cells.add((
        'Win rate',
        _fmtPerHr(rate, session.currency),
        rate >= 0 ? Colors.green : Colors.red,
      ));
    }
    if (isTournament) {
      if (session.buyIn > 0) {
        final roi = calcROI(session.profitLoss, session.buyIn);
        cells.add(('ROI', formatROI(roi), roi >= 0 ? Colors.green : Colors.red));
      }
    } else {
      final bb = calcBB100([session]);
      if (bb != null) {
        cells.add((
          'BB/100',
          formatBB100(bb),
          bb >= 0 ? Colors.green : Colors.red,
        ));
      }
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 5, 12, 5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Green/red edge — win/loss at a glance.
              Container(width: 5, color: plColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: isTournament
                                ? theme.colorScheme.tertiaryContainer
                                : theme.colorScheme.secondaryContainer,
                            child: Icon(
                              isTournament
                                  ? Icons.emoji_events_outlined
                                  : Icons.style_outlined,
                              size: 18,
                              color: isTournament
                                  ? theme.colorScheme.onTertiaryContainer
                                  : theme.colorScheme.onSecondaryContainer,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isTournament
                                      ? '$date · Tournament'
                                      : '$date · ${session.stakes}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyLarge
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  location,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            formatPLWithCurrency(
                                session.profitLoss, session.currency),
                            style: TextStyle(
                              color: plColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Divider(
                        height: 1,
                        color: theme.colorScheme.outlineVariant
                            .withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          for (final c in cells)
                            Expanded(child: _metric(theme, c.$1, c.$2, c.$3)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metric(ThemeData theme, String label, String value, Color? color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(height: 2),
        Text(
          label.toUpperCase(),
          maxLines: 1,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}
