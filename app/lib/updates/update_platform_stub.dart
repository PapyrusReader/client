import 'package:papyrus/updates/update_release.dart';

Future<UpdateChannel> updateChannel() async => UpdateChannel.manual;
Future<int?> checkPlayUpdate() async => null;
Future<String> installUpdate(UpdateAsset? asset, void Function(double?) progress) async =>
    'Install the latest release from the Papyrus downloads page.';
Uri get updateManifestUri =>
    Uri.https('github.com', '/PapyrusReader/client/releases/latest/download/release-manifest.json');
