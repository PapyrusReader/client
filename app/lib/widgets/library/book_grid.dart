import 'dart:async';

import 'package:papyrus/utils/book_actions.dart';
import 'package:flutter/material.dart';
import 'package:papyrus/acquisition/acquisition_models.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/providers/enums/library_view_mode.dart';
import 'package:papyrus/providers/library_provider.dart';
import 'package:papyrus/providers/book_storage_status_controller.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/library/acquisition_placeholder_card.dart';
import 'package:papyrus/widgets/library/acquisition_status_text.dart';
import 'package:papyrus/widgets/library/book_card.dart';
import 'package:papyrus/widgets/library/collection_grid.dart';
import 'package:provider/provider.dart';

class BookGrid extends StatelessWidget {
  final List<Book> books;
  final LibraryViewMode libraryViewMode;
  final void Function(Book book)? onBookTap;
  final EdgeInsets? padding;
  final ValueChanged<Book>? onRemoveFromShelf;
  final Map<String, AcquisitionJob> acquisitionJobsByBookId;
  final List<AcquisitionJob> placeholderJobs;
  final Set<String> selectedAcquisitionJobIds;
  final ValueChanged<AcquisitionJob>? onAcquisitionTap;
  final ValueChanged<AcquisitionJob>? onAcquisitionSelectionToggle;

  const BookGrid({
    super.key,
    required this.books,
    required this.libraryViewMode,
    this.onBookTap,
    this.padding,
    this.onRemoveFromShelf,
    this.acquisitionJobsByBookId = const {},
    this.placeholderJobs = const [],
    this.selectedAcquisitionJobIds = const {},
    this.onAcquisitionTap,
    this.onAcquisitionSelectionToggle,
  });

  @override
  Widget build(BuildContext context) {
    if (libraryViewMode == LibraryViewMode.list) {
      throw ArgumentError('List mode does not use a grid layout');
    }

    final libraryProvider = context.watch<LibraryProvider>();
    final storageStatusController = context.watch<BookStorageStatusController?>();
    final bookIds = books.map((book) => book.id).toSet();
    final placeholderJobsByBookId = <String, AcquisitionJob>{};

    for (final job in placeholderJobs) {
      final bookId = job.bookId;

      if (bookId != null) {
        placeholderJobsByBookId.putIfAbsent(bookId, () => job);
      }
    }

    final linkedJobsByBookId = <String, AcquisitionJob>{};
    final claimedJobIds = <String>{};

    for (final book in books) {
      final job = acquisitionJobsByBookId[book.id] ?? placeholderJobsByBookId[book.id];

      if (job != null && claimedJobIds.add(job.id)) {
        linkedJobsByBookId[book.id] = job;
      }
    }

    final orphanJobs = <AcquisitionJob>[];
    final seenJobIds = <String>{...claimedJobIds};
    final seenPendingBookIds = <String>{};

    for (final job in placeholderJobs) {
      if (!seenJobIds.add(job.id)) {
        continue;
      }

      final bookId = job.bookId;

      if (bookId != null && (bookIds.contains(bookId) || !seenPendingBookIds.add(bookId))) {
        continue;
      }

      orphanJobs.add(job);
    }

    final hasTransferDetails = linkedJobsByBookId.values
        .followedBy(orphanJobs)
        .any((job) => acquisitionTransferDetails(job) != null);

    return CollectionGrid(
      preferredWidth: libraryProvider.gridDensity.width,
      padding: padding ?? const EdgeInsets.only(left: Spacing.md, right: Spacing.md, bottom: Spacing.md),
      itemCount: books.length + orphanJobs.length,
      hasTransferDetails: hasTransferDetails,
      itemBuilder: (context, index, metrics) {
        if (index >= books.length) {
          final job = orphanJobs[index - books.length];
          final canSelect = job.status != AcquisitionJobStatus.completed;

          return AcquisitionPlaceholderCard(
            compact: metrics.compact,
            transferDetailsLineHeight: metrics.transferDetailsLineHeight,
            job: job,
            onTap: onAcquisitionTap == null ? null : () => onAcquisitionTap!(job),
            isSelectionMode: canSelect && selectedAcquisitionJobIds.isNotEmpty,
            isSelected: selectedAcquisitionJobIds.contains(job.id),
            onSelectToggle: !canSelect || onAcquisitionSelectionToggle == null
                ? null
                : () => onAcquisitionSelectionToggle!(job),
            onEnterSelectionMode: !canSelect || onAcquisitionSelectionToggle == null
                ? null
                : () => onAcquisitionSelectionToggle!(job),
          );
        }

        final book = books[index];
        final job = linkedJobsByBookId[book.id];
        final isFavorite = libraryProvider.isBookFavorite(book.id, book.isFavorite);

        if (job == null) {
          unawaited(storageStatusController?.ensureDeviceStatus(book));
        }

        return BookCard(
          compact: metrics.compact,
          transferDetailsLineHeight: metrics.transferDetailsLineHeight,
          book: book,
          onRemoveFromShelf: onRemoveFromShelf == null ? null : () => onRemoveFromShelf!(book),
          isFavorite: isFavorite,
          onToggleFavorite: job == null ? (current) => toggleBookFavorite(context, book.id, current) : null,
          onTap: switch (job) {
            final job? when onAcquisitionTap != null => () => onAcquisitionTap!(job),
            _? => null,
            null when onBookTap != null => () => onBookTap!(book),
            null => null,
          },
          isSelectionMode: job != null ? selectedAcquisitionJobIds.isNotEmpty : libraryProvider.isSelectionMode,
          isSelected: job != null
              ? selectedAcquisitionJobIds.contains(job.id)
              : libraryProvider.isBookSelected(book.id),
          onSelectToggle: switch (job) {
            final job? when onAcquisitionSelectionToggle != null => () => onAcquisitionSelectionToggle!(job),
            _? => null,
            null => () => libraryProvider.toggleBookSelection(book.id),
          },
          onEnterSelectionMode: switch (job) {
            final job? when onAcquisitionSelectionToggle != null => () => onAcquisitionSelectionToggle!(job),
            _? => null,
            null => () => libraryProvider.enterSelectionMode(book.id),
          },
          acquisitionJob: job,
          accountStatus: job == null ? storageStatusController?.accountStatus(book) : null,
          deviceStatus: job == null ? storageStatusController?.deviceStatus(book) : null,
        );
      },
    );
  }
}
