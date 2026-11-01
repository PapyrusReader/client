import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:papyrus/updates/update_controller.dart';
import 'package:papyrus/updates/update_release.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> metadata({int build = 7}) => {
  'tag': 'v0.2.0+$build',
  'version': '0.2.0',
  'build_number': build,
  'assets': {
    'installer': {'name': 'papyrus-v0.2.0+$build-windows-x64-setup.exe', 'sha256': 'a' * 64},
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences preferences;
  final info = PackageInfo(appName: 'Papyrus', packageName: 'papyrus', version: '0.2.0', buildNumber: '6');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });

  UpdateController controller({
    UpdateChannel channel = UpdateChannel.windows,
    Future<Map<String, dynamic>> Function()? manifest,
    Future<int?> Function()? play,
    Future<String> Function(UpdateAsset?, void Function(double?))? installer,
  }) {
    final controller = UpdateController(
      preferences: preferences,
      appInfo: () async => info,
      channelProvider: () async => channel,
      manifest: manifest ?? () async => metadata(),
      playCheck: play ?? () async => null,
      installer: installer ?? (_, _) async => 'Installed',
    );

    addTearDown(controller.dispose);
    return controller;
  }

  test('downloads the exact newer platform asset and prevents duplicate installs', () async {
    var installs = 0;
    final updates = controller(
      installer: (asset, progress) async {
        installs++;
        expect(
          asset!.uri.toString(),
          'https://github.com/PapyrusReader/client/releases/download/v0.2.0+7/papyrus-v0.2.0+7-windows-x64-setup.exe',
        );
        progress(0.5);
        return 'Close Papyrus to update';
      },
    );

    await updates.check();
    expect(updates.available, isTrue);
    await updates.install();
    await updates.install();
    expect(installs, 1);
    expect(updates.staged, isTrue);
  });

  test('same and older builds are never offered', () async {
    for (final build in [5, 6]) {
      final updates = controller(manifest: () async => metadata(build: build));
      await updates.check();
      expect(updates.available, isFalse);
    }
  });

  test('Play eligibility is authoritative and never falls back to APK feed', () async {
    final updates = controller(
      channel: UpdateChannel.play,
      manifest: () async => throw StateError('GitHub must not be queried'),
      play: () async => 7,
      installer: (asset, _) async {
        expect(asset, isNull);
        return 'Play started';
      },
    );

    await updates.check();
    expect(updates.available, isTrue);
    await updates.install();
    expect(updates.message, 'Play started');
    expect(updates.staged, isFalse);
  });

  test('offline and invalid metadata remain retryable', () async {
    var attempts = 0;
    final updates = controller(
      manifest: () async {
        if (attempts++ == 0) throw StateError('offline');
        return metadata();
      },
    );

    await updates.check();
    expect(updates.available, isFalse);
    expect(updates.busy, isFalse);
    expect(preferences.getInt('updates.lastCheck'), isNull);
    await updates.check();
    expect(updates.available, isTrue);
  });

  test('malicious asset names and checksums are rejected', () async {
    for (final badAsset in [
      {'name': '../installer.exe', 'sha256': 'a' * 64},
      {'name': 'papyrus-v0.2.0+7-windows-x64-setup.exe', 'sha256': 'not a hash'},
    ]) {
      final data = metadata();
      (data['assets'] as Map)['installer'] = badAsset;
      final updates = controller(manifest: () async => data);
      await updates.check();
      expect(updates.available, isFalse);
    }
  });

  test('APT never runs a downloaded installer', () async {
    var installed = false;
    final updates = controller(
      channel: UpdateChannel.apt,
      installer: (_, _) async {
        installed = true;
        return '';
      },
    );

    await updates.check();
    await updates.install();
    expect(updates.available, isTrue);
    expect(updates.external, isTrue);
    expect(installed, isFalse);
  });

  test('failed installation can retry without clearing update', () async {
    final updates = controller(installer: (_, _) async => throw StateError('disk full'));
    await updates.check();
    await updates.install();
    expect(updates.busy, isFalse);
    expect(updates.available, isTrue);
    expect(updates.staged, isFalse);
  });

  test('automatic preference persists and a check in flight cannot duplicate', () async {
    final response = Completer<Map<String, dynamic>>();
    var checks = 0;
    final updates = controller(
      manifest: () {
        checks++;
        return response.future;
      },
    );

    await updates.setAutomatic(false);
    expect(preferences.getBool('updates.automatic'), isFalse);
    final first = updates.check();
    await Future<void>.delayed(Duration.zero);
    await updates.check();
    response.complete(metadata());
    await first;
    expect(checks, 1);
  });

  test('changing automatic checks persists without starting a check or changing status', () async {
    var checks = 0;
    final updates = controller(
      manifest: () async {
        checks++;
        throw StateError('offline');
      },
    );

    await updates.check();
    final message = updates.message;
    await updates.setAutomatic(false);
    await updates.setAutomatic(true);
    expect(preferences.getBool('updates.automatic'), isTrue);
    expect(checks, 1);
    expect(updates.message, message);
    expect(updates.busy, isFalse);
  });

  test('invalid release identity fails closed', () {
    for (final data in [
      {...metadata(), 'tag': 'v0.2.0+8'},
      {...metadata(), 'version': '../0.2.0'},
      {...metadata(), 'build_number': '7'},
      {...metadata(), 'build_number': 0},
    ]) {
      expect(() => UpdateRelease.fromJson(data), throwsFormatException);
    }
  });
}
