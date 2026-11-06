import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/models/reading_activity.dart';
import 'package:papyrus/models/reading_goal.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/book/private_book_cover.dart';
import 'package:provider/provider.dart';

class ReadingTimerHistory extends StatelessWidget {
  const ReadingTimerHistory({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DataStore>();
    final theme = Theme.of(context);

    final sessions =
        groupReadingActivities(
            store.effectiveReadingActivities,
          ).where((activity) => activity.kind == 'reading' && activity.seconds > 0).toList()
          ..sort((left, right) => right.endTime.compareTo(left.endTime));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text('Recent sessions', style: theme.textTheme.titleMedium),
        ),
        const SizedBox(height: Spacing.md),
        if (sessions.isEmpty)
          Text(
            'No saved sessions yet.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        for (final session in sessions.take(8)) ...[
          if (session != sessions.first) const Divider(height: Spacing.lg),
          _session(context, store, session),
        ],
      ],
    );
  }

  Widget _session(BuildContext context, DataStore store, ReadingActivity session) {
    final theme = Theme.of(context);
    final book = store.getBook(session.bookId);
    final title = book?.title ?? session.bookTitle;
    final date = DateFormat.yMMMd().add_jm().format(session.endTime.toLocal());
    final duration = session.seconds < 60 ? '${session.seconds}s' : formatDuration(session.seconds ~/ 60);

    return Row(
      key: ValueKey('recent-session-${session.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 36,
          height: 54,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: CoverImage(
              bookId: book?.id,
              imageUrl: book?.coverUrl,
              mediaId: book?.coverMediaId,
              placeholder: ColoredBox(
                color: theme.colorScheme.primaryContainer,
                child: Icon(Icons.menu_book_outlined, color: theme.colorScheme.onPrimaryContainer, size: 20),
              ),
            ),
          ),
        ),
        const SizedBox(width: Spacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Tooltip(
                message: title,
                child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
              ),
              const SizedBox(height: Spacing.xs),
              Text(date, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
        const SizedBox(width: Spacing.sm),
        Text(duration, style: theme.textTheme.labelLarge),
      ],
    );
  }
}
