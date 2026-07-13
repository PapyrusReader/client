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
}
