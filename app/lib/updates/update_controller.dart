import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:papyrus/services/app_info.dart';
import 'package:papyrus/updates/update_platform.dart' as platform;
import 'package:papyrus/updates/update_release.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UpdateController extends ChangeNotifier {
  static const checkFailureMessage = 'Could not check for updates. Check your connection and try again.';

  final SharedPreferences preferences;
  final Future<PackageInfo> Function() appInfo;
  final Future<UpdateChannel> Function() channelProvider;
  final Future<int?> Function() playCheck;
  final Future<Map<String, dynamic>> Function() manifest;
  final Future<String> Function(UpdateAsset?, void Function(double?)) installer;
  UpdateChannel? channel;
  UpdateRelease? release;
  bool busy = false;
  bool available = false;
  bool staged = false;
  bool viewingSettings = false;
  double? progress;
  String message = 'Check for a newer version of Papyrus.';
  Timer? _timer;
  bool _disposed = false;

  UpdateController({
    required this.preferences,
    this.appInfo = loadAppInfo,
    this.channelProvider = platform.updateChannel,
    this.playCheck = platform.checkPlayUpdate,
    this.manifest = fetchManifest,
    this.installer = platform.installUpdate,
  });

  bool get automatic => preferences.getBool('updates.automatic') ?? true;
  bool get external => channel == UpdateChannel.apt || channel == UpdateChannel.manual;

  void setViewingSettings(bool value) {
    viewingSettings = value;
    _notify();
  }

  void start() {
    if (kReleaseMode) {
      unawaited(_backgroundCheck());
      _timer = Timer.periodic(const Duration(hours: 1), (_) => unawaited(_backgroundCheck()));
    }
  }

  Future<void> setAutomatic(bool value) async {
    await preferences.setBool('updates.automatic', value);
    _notify();
  }

  Future<void> _backgroundCheck() async {
    final lastCheck = preferences.getInt('updates.lastCheck') ?? 0;

    if (viewingSettings ||
        !automatic ||
        DateTime.now().millisecondsSinceEpoch - lastCheck < const Duration(days: 1).inMilliseconds) {
      return;
    }

    await check();
  }

  Future<void> check() async {
    if (busy || staged || _disposed) {
      return;
    }

    busy = true;
    message = 'Checking for updates…';
    _notify();

    try {
      channel = await channelProvider();
      final info = await appInfo();
      final compiledBuild = const int.fromEnvironment('PAPYRUS_BUILD_NUMBER');
      final currentBuild = kIsWeb && compiledBuild > 0 ? compiledBuild : int.tryParse(info.buildNumber);

      if (currentBuild == null || currentBuild < 1) {
        throw const FormatException('Installed build number is unavailable');
      }

      if (channel == UpdateChannel.play) {
        final build = await playCheck();
        available = build != null && build > currentBuild;
      } else {
        final data = await manifest();
        release = UpdateRelease.fromJson({...data, 'assets': data['assets'] ?? <String, dynamic>{}});
        available = release!.buildNumber > currentBuild;

        if (available && !external && channel != UpdateChannel.web) {
          release!.asset(_assetKey);
        }
      }

      message = available ? 'A newer version of Papyrus is available.' : 'Papyrus is up to date.';
      await preferences.setInt('updates.lastCheck', DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      available = false;
      release = null;
      message = checkFailureMessage;
    } finally {
      busy = false;
      _notify();
    }
  }

  String get _assetKey => switch (channel) {
    UpdateChannel.apk => 'android_apk',
    UpdateChannel.windows => 'installer',
    UpdateChannel.appImage => 'appimage',
    _ => throw StateError('No downloadable package for this channel'),
  };

  Future<void> install() async {
    if (busy || !available || staged || external || _disposed) {
      return;
    }

    busy = true;
    progress = null;
    message = 'Preparing the update…';
    _notify();

    try {
      final asset = channel == UpdateChannel.play || channel == UpdateChannel.web ? null : release!.asset(_assetKey);

      var previousPercent = -1;

      message = await installer(asset, (value) {
        final percent = value == null ? 0 : (value * 100).floor();

        if (percent == previousPercent) {
          return;
        }

        previousPercent = percent;
        progress = value;
        message = value == null ? 'Downloading update…' : 'Downloading update: ${(value * 100).floor()}%';
        _notify();
      });

      staged = channel == UpdateChannel.windows || channel == UpdateChannel.appImage;
    } catch (_) {
      message = 'Could not finish the update. Please try again.';
    } finally {
      busy = false;
      progress = null;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }

  static Future<Map<String, dynamic>> fetchManifest() async {
    final client = http.Client();

    try {
      final uri = platform.updateManifestUri.replace(
        queryParameters: {'check': '${DateTime.now().millisecondsSinceEpoch}'},
      );
      final response = await client.send(http.Request('GET', uri)).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw const FormatException('Update metadata unavailable');
      }

      final bytes = <int>[];

      await for (final chunk in response.stream.timeout(const Duration(seconds: 15))) {
        bytes.addAll(chunk);

        if (bytes.length > 65536) {
          throw const FormatException('Update metadata exceeds limit');
        }
      }

      return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }
}
