import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/reader/reader_book_adapter.dart';
import 'package:provider/provider.dart';

Future<void> openSavedReadingLocation(
  BuildContext context, {
  required String bookId,
  Map<String, Object?>? anchor,
  int? pageNumber,
}) async {
  final book = context.read<DataStore>().getBook(bookId);

  if (book == null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('This book is no longer in your library.')));
    return;
  }

  if (book.isPhysical) {
    await context.pushNamed('BOOK_DETAILS', pathParameters: {'bookId': bookId});
    return;
  }

  final String location;

  try {
    location = jsonEncode(ReaderBookAdapter.savedLocator(book, anchor: anchor, pageNumber: pageNumber).toJson());
  } on FormatException {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This item does not have a valid reading location.')),
    );
    return;
  }

  await context.pushNamed(
    'BOOK_READER',
    pathParameters: {'bookId': bookId},
    queryParameters: {'location': location},
  );
}
