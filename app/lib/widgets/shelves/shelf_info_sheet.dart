import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/providers/enums/library_reading_status.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/shared/app_bottom_sheet.dart';
import 'package:provider/provider.dart';

class ShelfInfoSheet extends StatelessWidget {
  const ShelfInfoSheet({super.key, required this.shelfId});

  final String shelfId;

  static Future<void> show(BuildContext context, {required String shelfId}) {
    final store = context.read<DataStore>();

    return showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: AppMotion.animationStyle(context),
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (_) => ChangeNotifierProvider.value(
        value: store,
        child: ShelfInfoSheet(shelfId: shelfId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DataStore>();
    final shelf = store.getShelf(shelfId);

    if (shelf == null) {
      return const AppBottomSheet(title: 'Details', body: Text('This shelf is no longer available.'));
    }

    final books = store.getBooksInShelf(shelfId);
    final description = shelf.description?.trim();
    final textTheme = Theme.of(context).textTheme;

    final counts = {
      for (final status in LibraryReadingStatus.values)
        status: books.where((book) => book.readingStatus == status).length,
    };

    return AppBottomSheet(
      title: 'Details',
      contentPadding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.md),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(shelf.name, style: textTheme.headlineSmall),
              Text(
                '${books.length} ${books.length == 1 ? 'book' : 'books'}',
                style: textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),

          const SizedBox(height: Spacing.md),
          Text('Description', style: textTheme.titleMedium),
          const SizedBox(height: Spacing.xs),
          Text(description == null || description.isEmpty ? 'No description yet.' : description),
          if (books.isNotEmpty) ...[
            const SizedBox(height: Spacing.md),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.xs,
              children: [
                for (final entry in counts.entries)
                  if (entry.value > 0) Chip(label: Text('${entry.value} ${entry.key.label.toLowerCase()}')),
              ],
            ),
          ],
          const SizedBox(height: Spacing.md),
          Text('Created', style: textTheme.titleMedium),
          const SizedBox(height: Spacing.xs),
          Text(DateFormat.yMMMd().format(shelf.createdAt.toLocal())),
        ],
      ),
    );
  }
}
