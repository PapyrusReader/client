import 'package:flutter/material.dart';
import 'package:papyrus/models/annotation.dart';
import 'package:papyrus/models/bookmark.dart';
import 'package:papyrus/models/note.dart';
import 'package:papyrus/reader/reader_book_adapter.dart';
import 'package:papyrus/reader/reader_library.dart';
import 'package:papyrus/reader/reader_bookmark_button.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus_reader/papyrus_reader.dart';

class ReaderLibraryPanel extends StatelessWidget {
  const ReaderLibraryPanel({super.key, required this.library, required this.panel});

  final ReaderLibrary library;
  final ReaderPanelContext panel;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 4,
    animationDuration: AppMotion.duration(context, kTabScrollDuration),
    child: ListenableBuilder(
      listenable: library.store,
      builder: (context, _) {
        if (!library.isCurrent) {
          return const Center(child: Text('Your library changed. Reopen this book from the library.'));
        }

        final bookmarks = library.store.getBookmarksForBook(library.bookId)
          ..sort((left, right) => left.position.compareTo(right.position));
        final annotations = library.store.getAnnotationsForBook(library.bookId)
          ..sort((left, right) => (left.location.percentage ?? 0).compareTo(right.location.percentage ?? 0));
        final notes = library.store.getNotesForBook(library.bookId)
          ..sort((left, right) => right.createdAt.compareTo(left.createdAt));

        return Column(
          children: [
            if (panel.showHeader) panel.buildHeader!(context, 'Contents'),
            const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: 'Chapters'),
                Tab(text: 'Bookmarks'),
                Tab(text: 'Annotations'),
                Tab(text: 'Notes'),
              ],
            ),
            Expanded(
              child: TabBarView(
                physics: AppMotion.disabled(context) ? const NeverScrollableScrollPhysics() : null,
                children: [
                  panel.buildContents!(context),
                  _list(
                    context,
                    items: bookmarks,
                    empty: 'Save a bookmark to return to this place later.',
                    action: ReaderBookmarkButton(
                      library: library,
                      snapshot: panel.snapshot,
                      isBusy: panel.isBusy,
                      floating: true,
                    ),
                  ),
                  _list(context, items: annotations, empty: 'Select text in the book and choose Annotate.'),
                  _list(
                    context,
                    items: notes,
                    empty: 'Keep your thoughts about this book here.',
                    action: FloatingActionButton(
                      heroTag: null,
                      tooltip: 'Add note',
                      onPressed: panel.isBusy ? null : () => library.addNote(context),
                      child: const Icon(Icons.note_add_outlined),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _list(BuildContext context, {required List<Object> items, required String empty, Widget? action}) => Stack(
    fit: StackFit.expand,
    children: [
      if (items.isEmpty)
        Center(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Text(empty, textAlign: TextAlign.center),
          ),
        )
      else
        ListView.separated(
          padding: EdgeInsets.only(
            top: Spacing.sm,
            bottom: action == null ? Spacing.sm : Spacing.md + Spacing.fabClearance,
          ),
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) => _entry(context, items[index]),
        ),

      if (action != null)
        PositionedDirectional(
          end: Spacing.md,
          bottom: Spacing.md,
          child: SafeArea(top: false, left: false, right: false, child: action),
        ),
    ],
  );

  Widget _entry(BuildContext context, Object item) {
    final (title, subtitle, icon, color, anchor) = switch (item) {
      Bookmark() => (
        item.note ?? item.chapterTitle ?? 'Bookmark',
        item.displayLocation,
        Icons.bookmark,
        item.color,
        _savedAnchor(item.readerLocator, item.pageNumber),
      ),
      Annotation() => (
        item.selectedText,
        [item.location.displayLocation, if (item.hasNote) item.note!].join('\n'),
        Icons.format_quote,
        item.color.accentColor,
        _savedAnchor(item.location.readerLocator, item.location.pageNumber),
      ),
      Note() => (
        item.title,
        item.preview,
        Icons.notes,
        Theme.of(context).colorScheme.primary,
        null,
      ),
      _ => throw ArgumentError.value(item),
    };

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, maxLines: 3, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 3, overflow: TextOverflow.ellipsis),
      onTap: () => _view(context, item, title, anchor),
      trailing: PopupMenuButton<String>(
        tooltip: 'Item actions',
        onSelected: (action) {
          if (action == 'delete') {
            _delete(context, item);
          } else {
            _edit(context, item);
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('Edit')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }

  Map<String, Object?>? _savedAnchor(Map<String, Object?>? anchor, int? pageNumber) {
    if (anchor != null) {
      return anchor;
    }

    final book = library.store.getBook(library.bookId);

    if (book == null) {
      return null;
    }

    try {
      return ReaderBookAdapter.savedLocator(book, pageNumber: pageNumber).toJson();
    } on FormatException {
      return null;
    }
  }

  void _goTo(BuildContext context, Map<String, Object?> anchor) {
    if (!library.isCurrent || panel.isBusy) {
      return;
    }

    try {
      panel.navigate?.call(ReaderLocator.fromJson(anchor));
    } on FormatException {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('This saved location could not be opened.')));
    }
  }

  Future<void> _view(BuildContext context, Object item, String title, Map<String, Object?>? anchor) async {
    if (item is Bookmark && anchor != null) {
      _goTo(context, anchor);
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(switch (item) {
          Note() => item.title,
          Bookmark() => 'Bookmark',
          _ => 'Annotation',
        }),
        scrollable: true,
        content: SelectableText(switch (item) {
          Note() => item.content,
          Annotation() => [item.selectedText, if (item.hasNote) item.note!].join('\n\n'),
          _ => title,
        }),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
          if (anchor != null)
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _goTo(context, anchor);
              },
              child: const Text('Go to passage'),
            ),
        ],
      ),
    );
  }

  void _edit(BuildContext context, Object item) {
    switch (item) {
      case Bookmark():
        library.editBookmark(context, item);
      case Annotation():
        library.editAnnotation(context, item);
      case Note():
        library.editNote(context, item);
    }
  }

  Future<void> _delete(BuildContext context, Object item) => library.confirmDelete(context, item);
}
