import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Adapts catalog fixtures to the relay protocol; transport contract tests use raw mocks.
class MockRelayClient extends MockClient {
  MockRelayClient(Future<http.Response> Function(http.Request) handler)
    : super((request) async {
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        final upstream = http.Request('GET', Uri.parse(payload['url'] as String));
        final response = await handler(upstream);
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          headers: {...response.headers, 'x-opds-url': upstream.url.toString()},
        );
      });
}
