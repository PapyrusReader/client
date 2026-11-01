import 'package:papyrus/updates/update_release.dart';
import 'package:web/web.dart' as web;

Future<UpdateChannel> updateChannel() async => UpdateChannel.web;
Future<int?> checkPlayUpdate() async => null;
Uri get updateManifestUri => Uri.base.resolve('/release.json');

Future<String> installUpdate(UpdateAsset? asset, void Function(double?) progress) async {
  web.window.location.reload();
  return 'Reloading Papyrus…';
}
