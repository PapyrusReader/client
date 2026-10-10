import 'package:flutter/material.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/shared/app_bottom_sheet.dart';

/// A searchable library selection that retains unavailable books when editing.
class SearchableBooksField extends FormField<List<String>> {
  SearchableBooksField({
    super.key,
    required List<Book> books,
    required List<String> value,
    super.enabled = true,
    required ValueChanged<List<String>> onChanged,
  }) : super(
         initialValue: value,
         validator: (value) => value == null || value.isEmpty ? 'Choose at least one book.' : null,
         builder: (field) {
           final selected = field.value ?? const <String>[];

           return Column(
             crossAxisAlignment: CrossAxisAlignment.start,
             children: [
               OutlinedButton.icon(
                 icon: const Icon(Icons.search),
                 label: Text(selected.isEmpty ? 'Choose books' : 'Change books (${selected.length})'),
                 onPressed: !enabled || books.isEmpty
                     ? null
                     : () async {
                         final result = await showModalBottomSheet<List<String>>(
                           context: field.context,
                           useRootNavigator: true,
                           useSafeArea: true,
                           isScrollControlled: true,
                           constraints: const BoxConstraints(maxWidth: 640),
                           sheetAnimationStyle: AppMotion.animationStyle(field.context),
                           builder: (_) => _BooksSearchSheet(books: books, selected: selected),
                         );

                         if (result != null && field.mounted) {
                           field.didChange(result);
                           onChanged(result);
                         }
                       },
               ),
               if (selected.isNotEmpty) ...[
                 const SizedBox(height: Spacing.sm),
                 Wrap(
                   spacing: Spacing.sm,
                   runSpacing: Spacing.sm,
                   children: [
                     for (final id in selected)
                       Chip(
                         label: ConstrainedBox(
                           constraints: const BoxConstraints(maxWidth: 220),
                           child: Text(
                             books.where((book) => book.id == id).firstOrNull?.title ?? 'Removed book',
                             maxLines: 1,
                             overflow: TextOverflow.ellipsis,
                           ),
                         ),
                         onDeleted: !enabled
                             ? null
                             : () {
                                 final result = selected.where((value) => value != id).toList();
                                 field.didChange(result);
                                 onChanged(result);
                               },
                       ),
                   ],
                 ),
               ],
               if (books.isEmpty || field.hasError)
                 Padding(
                   padding: const EdgeInsets.only(top: Spacing.sm),
                   child: Text(
                     field.errorText ?? 'Your library has no books to select.',
                     style: TextStyle(color: Theme.of(field.context).colorScheme.error),
                   ),
                 ),
             ],
           );
         },
       );
}

class _BooksSearchSheet extends StatefulWidget {
  const _BooksSearchSheet({required this.books, required this.selected});
  final List<Book> books;
  final List<String> selected;

  @override
  State<_BooksSearchSheet> createState() => _BooksSearchSheetState();
}

class _BooksSearchSheetState extends State<_BooksSearchSheet> {
  late final Set<String> _selected = widget.selected.toSet();
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();

    final books = widget.books
        .where(
          (book) =>
              '${book.title} ${book.allAuthors} ${book.isbn ?? ''} ${book.isbn13 ?? ''}'.toLowerCase().contains(query),
        )
        .toList();

    return AppBottomSheet(
      title: 'Choose books',
      onClose: () => Navigator.pop(context),
      expandBody: true,
      scrollable: false,
      expandOnScroll: false,
      body: Column(
        children: [
          TextField(
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Search books', prefixIcon: Icon(Icons.search)),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: Spacing.md),
          Expanded(
            child: books.isEmpty
                ? const Align(alignment: Alignment.topCenter, child: Text('No books found'))
                : ListView.builder(
                    itemCount: books.length,
                    itemBuilder: (context, index) {
                      final book = books[index];

                      return CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _selected.contains(book.id),
                        title: Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: book.allAuthors.isEmpty
                            ? null
                            : Text(book.allAuthors, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onChanged: (value) => setState(() {
                          if (value == true) {
                            _selected.add(book.id);
                          } else {
                            _selected.remove(book.id);
                          }
                        }),
                      );
                    },
                  ),
          ),
        ],
      ),
      footer: BottomSheetFormActions(
        onCancel: () => Navigator.pop(context),
        onSave: _selected.isEmpty ? null : () => Navigator.pop(context, _selected.toList()..sort()),
        saveLabel: 'Select (${_selected.length})',
      ),
    );
  }
}
