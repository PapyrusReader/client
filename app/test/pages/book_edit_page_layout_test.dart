import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:papyrus/pages/book_edit_page.dart';
import 'package:papyrus/providers/book_edit_provider.dart';
import 'package:papyrus/providers/preferences_provider.dart';
import 'package:papyrus/widgets/book_details/book_info_grid.dart';
import 'package:provider/provider.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/book_edit/cover_image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_helpers.dart';

void main() {
  group('BookEditPage layout', () {
    Future<void> pumpPage(
      WidgetTester tester, {
      required Size size,
      double? contentWidth,
      PreferencesProvider? preferences,
      ThemeData? theme,
      double textScale = 1,
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);

      final book = buildTestBook(
        id: 'book-1',
        title: 'Frankenstein; or, The Modern Prometheus',
        author: 'Mary Shelley',
      );

      Widget page = MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
        child: Theme(
          data: theme ?? AppTheme.dark,
          child: const BookEditPage(id: 'book-1'),
        ),
      );

      if (contentWidth != null) {
        page = Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: contentWidth, height: size.height, child: page),
        );
      }

      await tester.pumpWidget(
        createTestPage(
          page: Scaffold(body: page),
          dataStore: createTestDataStore(books: [book]),
          screenSize: size,
          additionalProviders: [
            if (preferences != null) ChangeNotifierProvider<PreferencesProvider>.value(value: preferences),
          ],
        ),
      );

      await tester.pumpAndSettle();
    }

    for (final width in [390.0, 1400.0]) {
      testWidgets('genre can be edited and cleared at $width', (tester) async {
        await pumpPage(tester, size: Size(width, 1000));
        final field = find.ancestor(of: find.text('Genre'), matching: find.byType(TextFormField));
        await tester.ensureVisible(field);
        await tester.enterText(field, 'Science fiction');
        final editor = tester.element(field).read<BookEditProvider>();
        expect(editor.editedBook?.genre, 'Science fiction');
        expect(await editor.save(), isTrue);
        final saved = editor.editedBook!;
        await tester.enterText(field, '');
        expect(editor.editedBook?.genre, isNull);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: BookInfoGrid(book: saved)),
          ),
        );
        expect(find.text('Genre'), findsOneWidget);
        expect(find.text('Science fiction'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('desktop uses a left-aligned page header with a persistent Save action', (tester) async {
      await pumpPage(tester, size: const Size(1400, 1000));
      expect(find.text('Edit book'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Back'), findsNothing);
      expect(find.byTooltip('Back to book details'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
      expect(find.byIcon(Icons.save_outlined), findsNothing);
      final header = find.byKey(const Key('book-edit-desktop-header'));
      expect(tester.getSize(header).height, ComponentSizes.appBarHeight);
      expect(find.descendant(of: header, matching: find.text('Frankenstein; or, The Modern Prometheus')), findsNothing);
      expect(find.text('Cover'), findsNothing);
      expect(tester.getTopLeft(find.byType(CoverImagePicker)).dx, Spacing.lg);
      final saveButton = find.widgetWithText(FilledButton, 'Save');
      expect(find.ancestor(of: saveButton, matching: find.byType(SingleChildScrollView)), findsNothing);
    });

    testWidgets('desktop keeps the cover beside metadata and form sections', (tester) async {
      await pumpPage(tester, size: const Size(1400, 1000));
      final cover = tester.getTopLeft(find.byType(CoverImagePicker));
      final metadataHeading = tester.getTopLeft(find.text('Fetch metadata'));
      final formHeading = tester.getTopLeft(find.text('Basic information'));
      expect(metadataHeading.dx, greaterThan(cover.dx));

      expect(metadataHeading.dy, cover.dy);

      expect(formHeading.dx, closeTo(metadataHeading.dx, 1));
      expect(formHeading.dy, greaterThan(metadataHeading.dy));
    });

    testWidgets('intermediate desktop keeps panes side by side while paired fields stack', (tester) async {
      await pumpPage(tester, size: const Size(1000, 1200), contentWidth: 800);
      final cover = tester.getTopLeft(find.byType(CoverImagePicker));
      final metadataHeading = tester.getTopLeft(find.text('Fetch metadata'));
      final publisher = tester.getTopLeft(find.text('Publisher'));
      final language = tester.getTopLeft(find.text('Language'));
      expect(metadataHeading.dx, greaterThan(cover.dx));

      expect(metadataHeading.dy, cover.dy);

      expect(language.dy, greaterThan(publisher.dy));
      expect(tester.takeException(), isNull);
    });

    testWidgets('medium desktop aligns the cover with the page gutter above full-width form sections', (tester) async {
      await pumpPage(tester, size: const Size(1000, 1200), contentWidth: 640);
      final cover = tester.getTopLeft(find.byType(CoverImagePicker));
      final metadataHeading = tester.getTopLeft(find.text('Fetch metadata'));
      final formHeading = tester.getTopLeft(find.text('Basic information'));
      final coverPreview = find.descendant(of: find.byType(CoverImagePicker), matching: find.byType(AspectRatio));
      expect(metadataHeading.dy, greaterThan(cover.dy));
      expect(formHeading.dy, greaterThan(metadataHeading.dy));
      expect(tester.getTopLeft(coverPreview).dx, Spacing.lg);
      expect(metadataHeading.dx, formHeading.dx);
      expect(tester.getSize(find.byType(AspectRatio).first).width, 240);
      expect(tester.takeException(), isNull);
    });

    testWidgets('metadata search leaves source configuration in Settings', (tester) async {
      await pumpPage(tester, size: const Size(1000, 1200), contentWidth: 640);
      final searchField = find.ancestor(of: find.text('Search'), matching: find.byType(TextFormField)).first;
      expect(searchField, findsOneWidget);
      expect(find.text('Source'), findsNothing);
      expect(find.text('Open Library'), findsNothing);
      expect(find.text('Google Books'), findsNothing);
    });

    testWidgets('metadata searches use the current saved source and results remain applicable', (tester) async {
      SharedPreferences.setMockInitialValues({'metadata_source': 'Google Books'});
      final preferences = PreferencesProvider(await SharedPreferences.getInstance());
      addTearDown(preferences.dispose);
      final requests = <Uri>[];

      final client = MockClient((request) async {
        requests.add(request.url);

        if (request.url.host == 'localhost') {
          return http.Response(
            '{"results":[{"title":"Google result","authors":["Author"],"cover_url":"https://books.google.com/cover.jpg"}]}',
            200,
          );
        }

        return http.Response('{"docs":[{"title":"Open Library result","author_name":["Author"]}]}', 200);
      });

      addTearDown(client.close);

      await http.runWithClient(
        () => pumpPage(tester, size: const Size(1400, 1200), preferences: preferences),
        () => client,
      );

      final search = find.widgetWithText(TextFormField, 'Search');

      for (final (source, query, host, result) in [
        ('Google Books', 'Alice', 'localhost', 'Google result'),
        ('Open Library', '9780141439518', 'openlibrary.org', 'Open Library result'),
        ('Open Library', 'Alice', 'openlibrary.org', 'Open Library result'),
        ('Google Books', '9780141439518', 'localhost', 'Google result'),
      ]) {
        preferences.metadataSource = source;
        await tester.enterText(search, query);
        await tester.tap(find.byTooltip('Search book metadata'));
        await tester.pumpAndSettle();
        expect(requests.last.host, host);

        final parameter = host == 'openlibrary.org' && query == '9780141439518' ? 'isbn' : 'q';
        final expectedQuery = query;
        expect(requests.last.queryParameters[parameter], expectedQuery);
        expect(find.text(result), findsOneWidget);
        expect(find.text('Tap to apply'), findsNothing);
      }

      await tester.tap(find.text('Google result'));
      await tester.pumpAndSettle();
      final provider = tester.element(find.byType(Form)).read<BookEditProvider>();
      expect(provider.editedBook!.title, 'Google result');
      expect(provider.editedBook!.coverUrl, 'https://books.google.com/cover.jpg');
      expect(provider.fetchedResults, isEmpty);
      expect(tester.takeException(), isNull);
    });

    for (final width in [320.0, 400.0, 1400.0]) {
      testWidgets('metadata pagination keeps results on failure and navigates at $width', (tester) async {
        SharedPreferences.setMockInitialValues({});
        final preferences = PreferencesProvider(await SharedPreferences.getInstance());
        addTearDown(preferences.dispose);
        final requests = <Uri>[];
        final delayedPage = Completer<http.Response>();
        var failNextPage = true;

        final client = MockClient((request) async {
          requests.add(request.url);
          final offset = int.parse(request.url.queryParameters['offset']!);

          if (offset == 10 && failNextPage) {
            failNextPage = false;
            return delayedPage.future;
          }

          return http.Response(
            jsonEncode({
              'numFound': 12,
              'docs': List.generate(offset == 0 ? 10 : 2, (index) => {'title': 'Result ${offset + index + 1}'}),
            }),
            200,
          );
        });

        addTearDown(client.close);

        await http.runWithClient(
          () => pumpPage(
            tester,
            size: Size(width, 1200),
            preferences: preferences,
            theme: width == 320 ? AppTheme.eink : AppTheme.dark,
            textScale: width == 320 ? 2 : 1,
          ),
          () => client,
        );

        final search = find.widgetWithText(TextFormField, 'Search');

        if (width < 840) {
          await tester.scrollUntilVisible(search, 500, scrollable: find.byType(Scrollable).first);
        }

        await tester.ensureVisible(search);
        await tester.pumpAndSettle();
        await tester.enterText(search, 'Alice');
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Search book metadata'));
        await tester.pumpAndSettle();
        expect(find.text('Results 1–10 of 12'), findsOneWidget);
        final next = find.widgetWithText(TextButton, 'Next');
        final previous = find.widgetWithText(TextButton, 'Previous');
        expect(tester.widget<TextButton>(previous).onPressed, isNull);

        // Unsubmitted edits must not change the query used by pagination.
        await tester.enterText(search, 'Dune');
        await tester.pumpAndSettle();
        await tester.ensureVisible(next);
        await tester.pumpAndSettle();
        await tester.tap(next);
        await tester.pump();
        expect(find.text('Loading…'), findsOneWidget);
        expect(tester.widget<TextButton>(next).onPressed, isNull);
        delayedPage.complete(http.Response('Unavailable', 503));
        await tester.pumpAndSettle();
        expect(find.text('Result 1'), findsOneWidget);
        expect(find.textContaining('Could not load this page'), findsOneWidget);
        expect(find.text('Page 1'), findsOneWidget);
        await tester.ensureVisible(next);
        await tester.pumpAndSettle();
        await tester.tap(next);
        await tester.pumpAndSettle();
        expect(find.text('Results 11–12 of 12'), findsOneWidget);
        expect(find.text('Result 11'), findsOneWidget);
        expect(find.text('Result 1'), findsNothing);
        expect(find.text('Page 2'), findsOneWidget);
        expect(tester.widget<TextButton>(next).onPressed, isNull);
        expect(requests.last.queryParameters['q'], 'Alice');
        await tester.ensureVisible(previous);
        await tester.pumpAndSettle();
        await tester.tap(previous);
        await tester.pumpAndSettle();
        expect(find.text('Results 1–10 of 12'), findsOneWidget);
        expect(requests.last.queryParameters['offset'], '0');
        await tester.ensureVisible(search);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Search book metadata'));
        await tester.pumpAndSettle();
        expect(requests.last.queryParameters['q'], 'Dune');
        expect(requests.last.queryParameters['offset'], '0');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('narrow layouts stack the cover above the form without overflow', (tester) async {
      await pumpPage(tester, size: const Size(600, 1600));
      expect(find.text('Edit book'), findsOneWidget);
      expect(find.byType(CoverImagePicker), findsOneWidget);

      expect(
        tester.getTopLeft(find.byType(CoverImagePicker)).dy,
        lessThan(tester.getTopLeft(find.text('Basic information')).dy),
      );

      expect(tester.takeException(), isNull);
    });
  });
}
