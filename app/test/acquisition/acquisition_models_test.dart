import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/acquisition/acquisition_models.dart';

void main() {
  test('recognizes a magnet release returned by an indexer', () {
    final release = TorrentRelease.fromJson({
      'title': 'Example book',
      'download_url': 'magnet:?xt=urn:btih:example',
      'protocol': 'torrent',
      'indexer': 'Prowlarr',
      'seeders': 12,
    });

    expect(release.isMagnet, isTrue);
    expect(release.seeders, 12);
  });

  test('parses torrent-only capabilities', () {
    final capabilities = AcquisitionCapabilities.fromJson({
      'endpoint_kinds': [
        'qbittorrent',
        'transmission',
        'deluge',
        'prowlarr',
        'torznab',
        'readarr',
      ],
      'indexer_kinds': ['prowlarr', 'torznab'],
      'download_client_kinds': ['qbittorrent', 'transmission', 'deluge'],
      'arr_kinds': ['readarr'],
      'arr_commands': {
        'readarr': ['AuthorSearch', 'BookSearch'],
      },
    });

    expect(capabilities.indexerKinds, [
      AcquisitionEndpointKind.prowlarr,
      AcquisitionEndpointKind.torznab,
    ]);
    expect(capabilities.downloadClientKinds, [
      AcquisitionEndpointKind.qbittorrent,
      AcquisitionEndpointKind.transmission,
      AcquisitionEndpointKind.deluge,
    ]);
    expect(capabilities.arrCommands[AcquisitionEndpointKind.readarr], [
      'AuthorSearch',
      'BookSearch',
    ]);
  });
}
