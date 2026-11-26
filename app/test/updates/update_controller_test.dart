import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

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
        return 'Restart Papyrus to finish updating.';
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

  test('failed checks remain retryable', () async {
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

  test('last successful check survives failure and does not claim freshness after restart', () async {
    var fails = false;
    final updates = controller(
      manifest: () async {
        if (fails) {
          throw StateError('Offline');
        }

        return metadata(build: 6);
      },
    );

    expect(updates.status, UpdateStatus.unchecked);
    expect(updates.lastChecked, isNull);
    await updates.check();
    expect(updates.status, UpdateStatus.upToDate);
    final checked = updates.lastChecked;
    expect(checked, isNotNull);
    fails = true;
    await updates.check();
    expect(updates.status, UpdateStatus.checkFailed);
    expect(updates.lastChecked, checked);
    final restarted = controller();
    expect(restarted.lastChecked, checked);
    expect(restarted.status, UpdateStatus.unchecked);
  });

  test('startup restores the notice before a fresh check and retains it offline', () async {
    await controller().check();
    var requests = 0;
    final response = Completer<Map<String, dynamic>>();
    final restarted = UpdateController(
      preferences: preferences,
      appInfo: () async => info,
      channelProvider: () async => UpdateChannel.windows,
      backgroundEnabled: true,
      manifest: () {
        requests++;
        return response.future;
      },
    );

    addTearDown(restarted.dispose);
    restarted.start();
    restarted.start();
    await Future<void>.delayed(Duration.zero);
    expect(restarted.showNotice, isTrue);
    expect(requests, 1);
    response.completeError(StateError('Offline'));
    await Future<void>.delayed(Duration.zero);
    expect(restarted.status, UpdateStatus.checkFailed);
    expect(restarted.showNotice, isTrue);
    await restarted.setAutomatic(false);
    expect(restarted.showNotice, isTrue);
  });

  test('startup checks despite a recent check; resume within the session is throttled', () async {
    await preferences.setInt('updates.lastCheck', DateTime.now().millisecondsSinceEpoch);
    await preferences.setInt('updates.checkedBuild', 6);
    var requests = 0;
    final restarted = UpdateController(
      preferences: preferences,
      appInfo: () async => info,
      channelProvider: () async => UpdateChannel.windows,
      backgroundEnabled: true,
      manifest: () async {
        requests++;
        return metadata();
      },
    );

    addTearDown(restarted.dispose);
    restarted.start();
    await Future<void>.delayed(Duration.zero);
    expect(requests, 1);
    expect(restarted.showNotice, isTrue);
    restarted.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(requests, 1);
  });

  test('a withdrawn update clears availability and the persisted notice', () async {
    var build = 7;
    final updates = controller(manifest: () async => metadata(build: build));
    await updates.check();
    expect(updates.available, isTrue);
    build = 6;
    await updates.check();
    expect(updates.available, isFalse);
    expect(preferences.getString('updates.known'), isNull);
  });

  test('dismissal lasts for the session, including refresh, but not a new launch', () async {
    final updates = controller();
    await updates.check(notifyUser: true);
    expect(updates.showNotice, isTrue);
    updates.dismissNotice();
    expect(updates.available, isTrue);
    expect(updates.showNotice, isFalse);
    await updates.check(notifyUser: true);
    expect(updates.showNotice, isFalse);
    final restarted = controller();
    restarted.start();
    await Future<void>.delayed(Duration.zero);
    expect(restarted.showNotice, isTrue);
  });

  for (final channel in [UpdateChannel.windows, UpdateChannel.play]) {
    test('skip changes future notices but not the current $channel banner', () async {
      var offeredBuild = 7;
      final updates = controller(
        channel: channel,
        manifest: () async => metadata(build: offeredBuild),
        play: () async => offeredBuild,
      );

      await updates.check(notifyUser: true);
      await updates.setSkipVersion(true);
      expect(updates.showNotice, isTrue);
      await updates.setSkipVersion(false);
      expect(updates.showNotice, isTrue);
      await updates.setSkipVersion(true);
      updates.dismissNotice();
      expect(updates.showNotice, isFalse);
      final restarted = controller(channel: channel);
      restarted.start();
      await Future<void>.delayed(Duration.zero);
      expect(restarted.available, isTrue);
      expect(restarted.skipped, isTrue);
      expect(restarted.showNotice, isFalse);
      restarted.setViewingSettings(true);
      await restarted.setSkipVersion(false);
      expect(restarted.showNotice, isFalse);
      await restarted.setSkipVersion(true);
      offeredBuild = 8;
      await updates.check(notifyUser: true);
      expect(updates.skipped, isFalse);
      expect(updates.showNotice, isTrue);
      expect(updates.available, isTrue);
    });
  }

  test('manual discovery is cached without raising a banner until the next launch', () async {
    final updates = controller();
    await updates.check();
    expect(updates.available, isTrue);
    expect(updates.showNotice, isFalse);
    final restarted = controller();
    restarted.start();
    await Future<void>.delayed(Duration.zero);
    expect(restarted.showNotice, isTrue);
  });

  for (final closeDialog in [false, true]) {
    test('automatic result does not raise a banner after opening settings; closed=$closeDialog', () async {
      final response = Completer<Map<String, dynamic>>();
      final updates = controller(manifest: () => response.future);
      final check = updates.check(notifyUser: true);
      await Future<void>.delayed(Duration.zero);
      updates.setViewingSettings(true);

      if (closeDialog) {
        updates.dismissNotice();
        updates.setViewingSettings(false);
      }

      response.complete(metadata());
      await check;
      expect(updates.available, isTrue);
      expect(updates.showNotice, isFalse);
    });
  }

  test('startup respects disabled automatic checks', () async {
    await preferences.setBool('updates.automatic', false);
    var requests = 0;
    final updates = UpdateController(
      preferences: preferences,
      appInfo: () async => info,
      channelProvider: () async => UpdateChannel.windows,
      backgroundEnabled: true,
      manifest: () async {
        requests++;
        return metadata();
      },
    );

    addTearDown(updates.dispose);
    updates.start();
    await Future<void>.delayed(Duration.zero);
    expect(requests, 0);
    expect(updates.showNotice, isFalse);
  });

  test('installed update and changed distribution clear cached availability', () async {
    await controller().check();
    final saved = preferences.getString('updates.known')!;

    for (final (build, channel) in [('7', UpdateChannel.windows), ('6', UpdateChannel.apk)]) {
      await preferences.setString('updates.known', saved);
      final restarted = UpdateController(
        preferences: preferences,
        appInfo: () async =>
            PackageInfo(appName: 'Papyrus', packageName: 'papyrus', version: '0.2.0', buildNumber: build),
        channelProvider: () async => channel,
      );

      addTearDown(restarted.dispose);
      await restarted.initialize();
      expect(restarted.available, isFalse);
      expect(preferences.getString('updates.known'), isNull);
    }
  });

  test('corrupt cached metadata is ignored and can be checked again', () async {
    await preferences.setString(
      'updates.known',
      jsonEncode({
        'channel': 'windows',
        'build': 7,
        'release': metadata(build: 8),
      }),
    );
    final updates = controller();
    await updates.initialize();
    expect(updates.available, isFalse);
    expect(preferences.getString('updates.known'), isNull);
    await updates.check();
    expect(updates.available, isTrue);
  });

  test('web restores the release notice and reloads without a native asset', () async {
    final updates = controller(
      channel: UpdateChannel.web,
      manifest: () async => metadata()..remove('assets'),
    );

    await updates.check(notifyUser: true);
    expect(updates.showNotice, isTrue);
    var reloads = 0;
    final restarted = controller(
      channel: UpdateChannel.web,
      installer: (asset, _) async {
        expect(asset, isNull);
        reloads++;
        return 'Reloading Papyrus…';
      },
    );

    restarted.start();
    await Future<void>.delayed(Duration.zero);
    expect(restarted.showNotice, isTrue);
    expect(reloads, 0);
    await restarted.install();
    expect(reloads, 1);
    expect(restarted.status, UpdateStatus.handedOff);
  });

  for (final (channel, key, suffix) in [
    (UpdateChannel.apk, 'android_apk', 'android-universal.apk'),
    (UpdateChannel.appImage, 'appimage', 'linux-x64.AppImage'),
  ]) {
    test('$channel downloads only its own verified package', () async {
      final data = metadata();
      (data['assets'] as Map)[key] = {'name': 'papyrus-v0.2.0+7-$suffix', 'sha256': 'b' * 64};
      final updates = controller(
        channel: channel,
        manifest: () async => data,
        installer: (asset, _) async {
          expect(asset!.name, endsWith(suffix));
          expect(asset.sha256, 'b' * 64);
          return 'Ready';
        },
      );

      await updates.check();
      await updates.install();
      expect(updates.status, channel == UpdateChannel.appImage ? UpdateStatus.staged : UpdateStatus.handedOff);
    });
  }

  test('manual packages never run an installer', () async {
    final updates = controller(
      channel: UpdateChannel.manual,
      installer: (_, _) async => throw StateError('Must not install'),
    );
    await updates.check();
    await updates.install();
    expect(updates.status, UpdateStatus.available);
    expect(updates.external, isTrue);
  });

  test('Windows is not ready while Setup runs; cancellation stays retryable', () async {
    final setup = Completer<String>();
    var attempts = 0;
    final updates = controller(
      installer: (_, progress) {
        progress(1);
        return attempts++ == 0 ? setup.future : Future.value('Restart Papyrus to finish updating.');
      },
    );
    await updates.check();
    final installation = updates.install();
    expect(updates.status, UpdateStatus.installing);
    expect(updates.staged, isFalse);
    expect(updates.message, 'Installing…');
    setup.completeError(const UpdateInstallException('Windows Setup was cancelled.'));
    await installation;
    expect(updates.status, UpdateStatus.installFailed);
    expect(updates.available, isTrue);
    expect(updates.staged, isFalse);
    expect(updates.message, 'Windows Setup was cancelled.');
    expect(updates.busy, isFalse);
    await updates.install();
    expect(attempts, 2);
    expect(updates.status, UpdateStatus.staged);
  });

  test('returning from Android installer rechecks eligibility despite daily throttle', () async {
    var eligible = true;
    final updates = UpdateController(
      preferences: preferences,
      appInfo: () async => info,
      channelProvider: () async => UpdateChannel.play,
      playCheck: () async => eligible ? 7 : null,
      installer: (_, _) async => 'Follow Play',
      backgroundEnabled: true,
    );

    addTearDown(updates.dispose);
    await updates.check();
    await updates.install();
    eligible = false;
    updates.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(updates.available, isFalse);
    expect(updates.status, UpdateStatus.upToDate);
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
