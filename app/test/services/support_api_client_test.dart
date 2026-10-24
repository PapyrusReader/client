import 'dart:convert';
import 'dart:typed_data';

import 'package:papyrus/services/support_attachment.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';
import 'package:papyrus/services/support_api_client.dart';

void main() {
  test('submission uses configured server and no account credentials', () async {
    final client = SupportApiClient(
      config: PapyrusApiConfig(serverBaseUri: Uri.parse('https://custom.example'), apiPrefix: '/api'),
      httpClient: MockClient((request) async {
        expect(request.url.toString(), 'https://custom.example/api/support/issues');
        expect(request.headers.containsKey('authorization'), isFalse);
        expect(request.headers['content-type'], startsWith('multipart/form-data; boundary='));
        expect(
          request.body,
          contains(
            jsonEncode({
              'kind': 'feature',
              'title': 'More fonts',
              'description': 'Please add more font choices.',
              'app_version': '0.0.4 (4)',
              'platform': 'android',
            }),
          ),
        );
        expect(request.body, contains('filename="screen.png"'));
        expect(request.body, contains('content-type: image/png'));
        expect(request.body, contains('image bytes'));
        expect(request.body, contains('filename="demo.mp4"'));
        expect(request.body, contains('content-type: video/mp4'));
        expect(request.body, contains('video bytes'));
        return http.Response('{"number":42,"url":"https://github.com/PapyrusReader/client/issues/42"}', 201);
      }),
    );
    addTearDown(client.close);
    final issue = await client.submit(
      kind: 'feature',
      title: ' More fonts ',
      description: 'Please add more font choices.',
      appVersion: '0.0.4 (4)',
      platform: 'android',
      attachments: [
        SupportAttachment(
          name: 'screen.png',
          bytes: Uint8List.fromList(utf8.encode('image bytes')),
          contentType: 'image/png',
        ),
        SupportAttachment(
          name: 'demo.mp4',
          bytes: Uint8List.fromList(utf8.encode('video bytes')),
          contentType: 'video/mp4',
        ),
      ],
    );
    expect(issue.number, 42);
  });

  for (final status in [404, 422, 429, 502, 503, 504]) {
    test('status $status is a failure with no automatic retry', () async {
      var calls = 0;
      final client = SupportApiClient(
        config: PapyrusApiConfig(serverBaseUri: Uri.parse('https://api.example')),
        httpClient: MockClient((request) async {
          calls++;
          return http.Response('private upstream details', status);
        }),
      );
      addTearDown(client.close);
      await expectLater(
        client.submit(kind: 'bug', title: 'Title', description: 'Description', appVersion: '1', platform: 'web'),
        throwsA(isA<SupportException>()),
      );
      expect(calls, 1);
    });
  }

  test('accepts the configured server repository issue link', () async {
    final client = SupportApiClient(
      config: PapyrusApiConfig(serverBaseUri: Uri.parse('https://api.example')),
      httpClient: MockClient((request) async {
        return http.Response('{"number":42,"url":"https://github.com/ExampleOrg/reader-support/issues/42"}', 201);
      }),
    );
    addTearDown(client.close);
    final issue = await client.submit(
      kind: 'bug',
      title: 'Title',
      description: 'Description',
      appVersion: '1',
      platform: 'web',
    );
    expect(issue.url.toString(), 'https://github.com/ExampleOrg/reader-support/issues/42');
  });

  for (final url in [
    'https://evil.example/Org/repo/issues/42',
    'http://github.com/Org/repo/issues/42',
    'https://github.com@evil.example/Org/repo/issues/42',
    'https://github.com/Org/repo/issues/43',
    'https://github.com/Org/repo/pull/42',
    'https://github.com/Org/repo/issues/42?redirect=evil',
    'https://github.com/Org/repo/issues/42#fragment',
  ]) {
    test('rejects unrelated or malformed support link: $url', () async {
      final client = SupportApiClient(
        config: PapyrusApiConfig(serverBaseUri: Uri.parse('https://api.example')),
        httpClient: MockClient((request) async => http.Response(jsonEncode({'number': 42, 'url': url}), 201)),
      );
      addTearDown(client.close);
      await expectLater(
        client.submit(kind: 'bug', title: 'Title', description: 'Description', appVersion: '1', platform: 'web'),
        throwsA(isA<SupportException>()),
      );
    });
  }
}
