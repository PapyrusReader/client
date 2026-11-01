import 'dart:js_interop';

import 'package:papyrus/updates/update_release.dart';
import 'package:web/web.dart' as web;

@JS('papyrusApplyUpdate')
external JSPromise<JSString> _applyUpdate();

Future<UpdateChannel> updateChannel() async => UpdateChannel.web;
Future<int?> checkPlayUpdate() async => null;
Uri get updateManifestUri => Uri.parse(web.document.baseURI).resolve('release.json');

Future<String> installUpdate(UpdateAsset? asset, void Function(double?) progress) async {
  return (await _applyUpdate().toDart).toDart;
}
