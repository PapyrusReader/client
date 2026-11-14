@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:papyrus/widgets/book/private_book_cover.dart';
import 'package:papyrus/widgets/book_edit/cover_image_picker.dart';

void main() {
  const url = String.fromEnvironment('COVER_TEST_URL');

  for (final preview in [false, true]) {
    testWidgets(
      'public cover renders without CORS headers, edit preview: $preview',
      (tester) async {
        await tester.runAsync(() => expectLater(http.get(Uri.parse(url)), throwsA(isA<http.ClientException>())));

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: preview ? 200 : 40,
                  height: preview ? 600 : 60,
                  child: preview
                      ? CoverImagePicker(initialUrl: url, coverWidth: 200, onUrlChanged: (_) {}, onFileChanged: (_) {})
                      : const CoverImage(imageUrl: url, placeholder: Text('Missing cover')),
                ),
              ),
            ),
          ),
        );

        for (var attempt = 0; attempt < 100 && find.byType(HtmlElementView).evaluate().isEmpty; attempt++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pump();
        }

        expect(find.byType(HtmlElementView), findsOneWidget);
        expect(find.text('Missing cover'), findsNothing);
        expect(find.text('No cover image'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      },
      skip: url.isEmpty,
    );
  }
}
