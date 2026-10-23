import 'dart:async';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';
import 'package:papyrus/pages/support_page.dart';
import 'package:papyrus/services/support_api_client.dart';
import 'package:papyrus/themes/app_theme.dart';

import '../helpers/support_file_picker.dart';

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Papyrus',
      packageName: 'papyrus',
      version: '0.0.4',
      buildNumber: '4',
      buildSignature: '',
    );
  });

  testWidgets('validation, failure recovery, and single successful submission', (tester) async {
    tester.view.physicalSize = const Size(1000, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final completion = Completer<http.Response>();
    var calls = 0;
    final client = SupportApiClient(
      config: PapyrusApiConfig(serverBaseUri: Uri.parse('https://api.example')),
      httpClient: MockClient((request) async {
        calls++;
        expect(request.body, contains('"app_version":"0.0.4 (4)"'));

        if (calls == 1) {
          return http.Response('', 503);
        }

        return completion.future;
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.eink,
        home: SupportPage(client: client),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Submit'));
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a title.'), findsOneWidget);
    expect(calls, 0);
    await tester.enterText(find.byType(TextFormField).at(0), 'Reader issue');
    await tester.enterText(find.byType(TextFormField).at(1), 'The reader shows a blank page.');
    await tester.ensureVisible(find.text('Submit'));
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(find.text('Submission failed.'), findsOneWidget);
    expect(find.text('Check existing issues'), findsNothing);
    expect(find.text('The reader shows a blank page.'), findsOneWidget);
    await tester.ensureVisible(find.text('Submit'));
    await tester.tap(find.text('Submit'));
    await tester.pump();
    expect(find.text('Submitting…'), findsOneWidget);
    await tester.tap(find.text('Submitting…'));
    expect(calls, 2);
    completion.complete(http.Response('{"number":42,"url":"https://github.com/PapyrusReader/client/issues/42"}', 201));
    await tester.pumpAndSettle();
    expect(find.text('Thank you for helping us improve.').hitTestable(), findsOneWidget);
    expect(find.text('View issue'), findsOneWidget);
    expect(find.text('Submit'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('compact form submits a feature request with large text', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? submittedKind;
    final client = SupportApiClient(
      config: PapyrusApiConfig(serverBaseUri: Uri.parse('https://api.example')),
      httpClient: MockClient((request) async {
        submittedKind = request.body.contains('"kind":"feature"') ? 'feature' : 'bug';
        return http.Response('{"number":7,"url":"https://github.com/PapyrusReader/client/issues/7"}', 201);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: SupportPage(client: client),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('GitHub'), findsNothing);
    expect(find.textContaining('repository'), findsNothing);
    expect(find.textContaining('Feedback and attachments are public.'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Feature request').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'More fonts');
    await tester.enterText(find.byType(TextFormField).last, 'Please add more font choices.');
    await tester.ensureVisible(find.text('Submit'));
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(submittedKind, 'feature');
    expect(find.text('Thank you for helping us improve.').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('selected media can be removed and survives failed submission', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final picker = SupportFilePicker();
    FilePicker.platform = picker;
    picker.result = FilePickerResult([
      PlatformFile(name: 'screen.png', size: 3, readStream: Stream.value([1, 2, 3])),
      PlatformFile(name: 'demo.mp4', size: 2, readStream: Stream.value([4, 5])),
    ]);
    final client = SupportApiClient(
      config: PapyrusApiConfig(serverBaseUri: Uri.parse('https://api.example')),
      httpClient: MockClient((request) async {
        expect(request.body, contains('filename="demo.mp4"'));
        expect(request.body, isNot(contains('filename="screen.png"')));
        return http.Response('', 502);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: SupportPage(client: client),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Attach images or videos'));
    await tester.tap(find.text('Attach images or videos'));
    await tester.pumpAndSettle();
    expect(find.text('screen.png'), findsOneWidget);
    expect(find.text('demo.mp4'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Remove screen.png'));
    await tester.tap(find.byTooltip('Remove screen.png'));
    await tester.pumpAndSettle();
    expect(find.text('screen.png'), findsNothing);
    picker.result = null;
    await tester.ensureVisible(find.text('Attach images or videos'));
    await tester.tap(find.text('Attach images or videos'));
    await tester.pumpAndSettle();
    expect(find.text('demo.mp4'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'Reader issue');
    await tester.enterText(find.byType(TextFormField).last, 'The reader shows a blank page.');
    await tester.ensureVisible(find.text('Submit'));
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(find.text('Submission failed.'), findsOneWidget);
    expect(find.text('demo.mp4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
