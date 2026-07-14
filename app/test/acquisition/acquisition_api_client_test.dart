import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:papyrus/acquisition/acquisition_api_client.dart';
import 'package:papyrus/acquisition/acquisition_models.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';

void main() {
  test('uses acquisition capabilities endpoint with bearer auth', () async {
    final seenPaths = <String>[];
    final client = AcquisitionApiClient(
      config: PapyrusApiConfig(serverBaseUri: Uri.parse('https://api.test')),
      httpClient: MockClient((request) async {
        seenPaths.add(request.url.path);
        expect(request.headers['authorization'], 'Bearer access-token');
        return http.Response(
          jsonEncode({
            'endpoint_kinds': ['qbittorrent', 'prowlarr', 'readarr'],
            'indexer_kinds': ['prowlarr'],
            'download_client_kinds': ['qbittorrent'],
            'arr_kinds': ['readarr'],
            'arr_commands': {
              'readarr': ['BookSearch'],
            },
          }),
          200,
        );
      }),
    );

    final capabilities = await client.capabilities('access-token');

    expect(seenPaths, ['/v1/acquisition/capabilities']);
    expect(capabilities.downloadClientKinds, [
      AcquisitionEndpointKind.qbittorrent,
    ]);
    expect(capabilities.arrCommands[AcquisitionEndpointKind.readarr], [
      'BookSearch',
    ]);
  });

  test('submits a selected release to a torrent client', () async {
    late Map<String, dynamic> requestBody;
    final client = AcquisitionApiClient(
      config: PapyrusApiConfig(serverBaseUri: Uri.parse('https://api.test')),
      httpClient: MockClient((request) async {
        expect(request.url.path, '/v1/acquisition/submissions');
        requestBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'job_id': 'job-1'}), 201);
      }),
    );

    await client.submitRelease(
      accessToken: 'access-token',
      endpointId: 'client-1',
      release: const TorrentRelease(
        title: 'Example',
        downloadUrl: 'magnet:?xt=urn:btih:example',
        protocol: 'torrent',
        indexer: 'Prowlarr',
      ),
    );

    expect(requestBody['endpoint_id'], 'client-1');
    expect(requestBody['download_url'], 'magnet:?xt=urn:btih:example');
  });
}
