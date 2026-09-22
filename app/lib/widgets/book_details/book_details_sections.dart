import 'package:flutter/material.dart';
import 'package:papyrus/themes/design_tokens.dart';

class BookDetailsSectionTitle extends StatelessWidget {
  const BookDetailsSectionTitle(this.title, {super.key});
  final String title;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: Spacing.xs),
      Divider(height: 1, thickness: 1, color: Theme.of(context).colorScheme.outlineVariant),
    ],
  );
}

/// Presentation only: usable by both local books and remote publications.
class BookMetadataRows extends StatelessWidget {
  const BookMetadataRows({super.key, required this.entries});
  final List<(String, String)> entries;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final (label, value) in entries)
        Padding(
          padding: const EdgeInsets.only(bottom: Spacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 100,
                child: Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
              Expanded(child: Text(value, style: Theme.of(context).textTheme.bodyMedium)),
            ],
          ),
        ),
    ],
  );
}
