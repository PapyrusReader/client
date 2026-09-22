import 'package:flutter/material.dart';
import 'package:papyrus/opds/opds_models.dart';
import 'package:papyrus/opds/opds_publication_content.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/book_details/book_details_sections.dart';

class OpdsPublicationInformation extends StatelessWidget {
  const OpdsPublicationInformation({super.key, required this.catalog, required this.publication});
  final OpdsCatalog catalog;
  final OpdsPublication publication;

  @override
  Widget build(BuildContext context) {
    final content = OpdsPublicationContent.from(catalog, publication);
    final theme = Theme.of(context);
    final description = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BookDetailsSectionTitle('Description'),
        const SizedBox(height: Spacing.sm),
        Text(
          content.description?.isNotEmpty == true ? content.description! : 'No description available.',
          key: const Key('opds-description'),
          style: content.description?.isNotEmpty == true
              ? theme.textTheme.bodyLarge?.copyWith(height: 1.6)
              : theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
        ),
      ],
    );
    final additionalDetails = <Widget>[
      if (content.subjects.isNotEmpty) ...[
        const SizedBox(height: Spacing.lg),
        const BookDetailsSectionTitle('Subjects'),
        const SizedBox(height: Spacing.sm),
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.xs,
          children: [
            for (final subject in content.subjects) Chip(label: Text(subject), visualDensity: VisualDensity.compact),
          ],
        ),
      ],
    ];
    final information = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BookDetailsSectionTitle('Information'),
        const SizedBox(height: Spacing.sm),
        BookMetadataRows(entries: content.information.entries.map((entry) => (entry.key, entry.value)).toList()),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.md),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (content.information.isEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [description, ...additionalDetails],
            );
          }
          if (constraints.maxWidth >= 700 * MediaQuery.textScalerOf(context).scale(1)) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 6,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [description, ...additionalDetails],
                  ),
                ),
                const SizedBox(width: Spacing.xxl),
                Expanded(flex: 4, child: information),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              description,
              const SizedBox(height: Spacing.lg),
              information,
              ...additionalDetails,
            ],
          );
        },
      ),
    );
  }
}
