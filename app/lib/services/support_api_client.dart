import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:papyrus/services/support_attachment.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';

class SupportException implements Exception {
  const SupportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SupportIssue {
  const SupportIssue({required this.number, required this.url});

  final int number;
  final Uri url;
}

class SupportApiClient {
  SupportApiClient({required this.config, http.Client? httpClient}) : _client = httpClient ?? http.Client();

  final PapyrusApiConfig config;
  final http.Client _client;

  Future<SupportIssue> submit({
    required String kind,
    required String title,
    required String description,
    required String appVersion,
    required String platform,
    List<SupportAttachment> attachments = const [],
  }) async {
    try {
      final request = http.MultipartRequest('POST', config.endpoint('/support/issues'));
      request.headers['Accept'] = 'application/json';
      request.fields['payload'] = jsonEncode({
        'kind': kind,
        'title': title.trim(),
        'description': description.trim(),
        'app_version': appVersion,
        'platform': platform,
      });

      for (final attachment in attachments) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'attachments',
            attachment.bytes,
            filename: attachment.name,
            contentType: MediaType.parse(attachment.contentType),
          ),
        );
      }

      final response = await _client.send(request).then(http.Response.fromStream).timeout(const Duration(minutes: 4));

      if (response.statusCode != 201) {
        final message = switch (response.statusCode) {
          429 => 'Too many submissions. Please try again later.',
          503 => 'Support submissions are not configured on this server.',
          404 => 'This server does not support in-app submissions yet.',
          422 => 'Please check your title and description.',
          504 => 'Submission could not be confirmed. Check the repository before submitting again.',
          _ => 'Could not submit your request. Please try again later.',
        };

        throw SupportException(message);
      }

      final result = jsonDecode(response.body) as Map<String, dynamic>;
      final number = result['number'] as int;
      final url = Uri.parse(result['url'] as String);

      final validIssueUrl = RegExp(
        r'^https://github\.com/[A-Za-z0-9-]+/[A-Za-z0-9][A-Za-z0-9_.-]*/issues/[1-9][0-9]*$',
      ).hasMatch(url.toString());

      if (number <= 0 || !validIssueUrl || url.pathSegments.last != number.toString()) {
        throw const FormatException('Invalid issue response');
      }

      return SupportIssue(number: number, url: url);
    } on SupportException {
      rethrow;
    } catch (_) {
      throw const SupportException(
        'Submission could not be confirmed. Check your connection and the repository before submitting again.',
      );
    }
  }

  void close() => _client.close();
}
