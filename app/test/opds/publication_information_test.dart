import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/opds/opds_models.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/opds/opds_publication_information.dart';

void main() {
  final catalog = OpdsCatalog(id: 'g', name: 'Gutenberg', uri: Uri.parse('https://www.gutenberg.org/ebooks.opds'));
  final publication = OpdsPublication(
    id: 'book',
    title: 'Book',
    language: 'en',
    publisher: 'A publisher with a very long name',
    description:
        'Title: Book\n\nSummary: First paragraph.\n\nSecond paragraph.\n\nLanguage: English\n\nCredits: A helpful person.',
    subjects: ['An unusually long subject heading that should wrap safely on small screens without clipping'],
  );

  for (final theme in [AppTheme.light, AppTheme.dark, AppTheme.eink]) {
    for (final (width, scale) in [(360.0, 1.0), (840.0, 1.0), (1280.0, 1.0), (360.0, 2.0)]) {
      testWidgets('publication sections ${theme.brightness} ${theme.colorScheme.primary} width $width text $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(size: Size(width, 1000), textScaler: TextScaler.linear(scale)),
                child: SingleChildScrollView(
                  child: OpdsPublicationInformation(catalog: catalog, publication: publication),
                ),
              ),
            ),
          ),
        );
        expect(find.text('Description'), findsOneWidget);
        expect(find.text('Information'), findsOneWidget);
        expect(find.text('Subjects'), findsOneWidget);
        expect(find.text('Language'), findsOneWidget);
        expect(find.text('English (en)'), findsOneWidget);
        expect(find.textContaining('Credits: A helpful person.'), findsOneWidget);
        expect(find.text('More details'), findsNothing);
        expect(find.byType(ExpansionTile), findsNothing);
        final description = tester.getTopLeft(find.text('Description'));
        final information = tester.getTopLeft(find.text('Information'));
        if (width >= 840 && scale == 1) {
          expect(information.dy, description.dy);
          expect(information.dx, greaterThan(description.dx));
        } else {
          expect(information.dy, greaterThan(description.dy));
          expect(information.dx, description.dx);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('missing metadata hides optional sections and preserves description fallback', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OpdsPublicationInformation(
            catalog: catalog,
            publication: OpdsPublication(id: 'empty', title: 'Book'),
          ),
        ),
      ),
    );
    expect(find.text('No description available.'), findsOneWidget);
    expect(find.text('Information'), findsNothing);
    expect(find.text('Subjects'), findsNothing);
    expect(find.text('More details'), findsNothing);
  });
}
