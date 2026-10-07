import 'package:flutter/material.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/shared/app_bottom_sheet.dart';

/// A validated library selection, with title, author and ISBN search.
class SearchableBookField extends FormField<String> {
  SearchableBookField({
    super.key,
    required List<Book> books,
    String? value,
    super.enabled = true,
    required ValueChanged<String> onChanged,
  }) : super(
         initialValue: value,
         validator: (value) => books.any((book) => book.id == value) ? null : 'Choose a book.',
         builder: (field) {
           final selected = books.where((book) => book.id == field.value).firstOrNull;
           return InkWell(
             onTap: !enabled || books.isEmpty
                 ? null
                 : () async {
                     final book = await showModalBottomSheet<Book>(
                       context: field.context,
                       useRootNavigator: true,
                       useSafeArea: true,
                       isScrollControlled: true,
                       constraints: const BoxConstraints(maxWidth: 640),
                       sheetAnimationStyle: AppMotion.animationStyle(field.context),
                       builder: (_) => _BookSearchSheet(books: books, selectedId: field.value),
                     );
                     if (book != null && field.mounted) {
                       field.didChange(book.id);
                       onChanged(book.id);
                     }
                   },
             child: InputDecorator(
               isEmpty: selected == null,
               decoration: InputDecoration(
                 labelText: 'Book',
                 errorText: field.errorText,
                 suffixIcon: const Icon(Icons.search),
               ),
               child: Text(selected?.title ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
             ),
           );
         },
       );
}

class _BookSearchSheet extends StatefulWidget {
  const _BookSearchSheet({required this.books, this.selectedId});
  final List<Book> books;
  final String? selectedId;
  @override
  State<_BookSearchSheet> createState() => _BookSearchSheetState();
}

class _BookSearchSheetState extends State<_BookSearchSheet> {
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
      title: 'Choose a book',
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
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: book.allAuthors.isEmpty
                            ? null
                            : Text(book.allAuthors, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: book.id == widget.selectedId ? const Icon(Icons.check) : null,
                        onTap: () => Navigator.pop(context, book),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
