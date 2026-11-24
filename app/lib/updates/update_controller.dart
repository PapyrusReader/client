import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:papyrus/services/app_info.dart';
import 'package:papyrus/updates/update_platform.dart' as platform;
import 'package:papyrus/updates/update_release.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum UpdateStatus {
  unchecked,
  checking,
  upToDate,
  available,
  installing,
  staged,
  handedOff,
  checkFailed,
  installFailed,
}

class UpdateController extends ChangeNotifier with WidgetsBindingObserver {
  static const checkFailureMessage = 'Could not check for updates. Try again.';

  final SharedPreferences preferences;
  final Future<PackageInfo> Function() appInfo;
  final Future<UpdateChannel> Function() channelProvider;
  final Future<int?> Function() playCheck;
  final Future<Map<String, dynamic>> Function() manifest;
  final Future<String> Function(UpdateAsset?, void Function(double?)) installer;
  UpdateChannel? channel;
  UpdateRelease? release;
  UpdateStatus status = UpdateStatus.unchecked;
  bool busy = false;
  bool checking = false;
  bool available = false;
  bool staged = false;
  bool viewingSettings = false;
  double? progress;
  String message = 'Check for a newer version of Papyrus.';
  Timer? _timer;
  bool _disposed = false;
  bool _started = false;
  bool _noticeVisible = false;
  int _noticeRevision = 0;
  int? _currentBuild;
  int? _offeredBuild;
  int? _dismissedBuild;
  Future<void>? _initialization;
  final bool backgroundEnabled;

  UpdateController({
    required this.preferences,
    this.appInfo = loadAppInfo,
    this.channelProvider = platform.updateChannel,
    this.playCheck = platform.checkPlayUpdate,
    this.manifest = fetchManifest,
    this.installer = platform.installUpdate,
    this.backgroundEnabled = kReleaseMode,
  });

  DateTime? get lastChecked {
    final timestamp = preferences.getInt('updates.lastCheck');
    return timestamp == null ? null : DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  bool get supported => channel != UpdateChannel.web && (channel != null || !kIsWeb);
  bool get automatic => preferences.getBool('updates.automatic') ?? true;
  bool get external => channel == UpdateChannel.apt || channel == UpdateChannel.manual;
  bool get skipped => _offeredBuild != null && preferences.getInt('updates.skippedBuild') == _offeredBuild;
  bool get showNotice => supported && available && _noticeVisible;

  void dismissNotice() {
    _noticeVisible = false;
    _noticeRevision++;
    _dismissedBuild = _offeredBuild;
    _notify();
  }

  Future<void> setSkipVersion(bool value) async {
    final build = _offeredBuild;

    if (!available || build == null || busy || staged) {
      return;
    }

    if (value) {
      await preferences.setInt('updates.skippedBuild', build);
    } else {
      await preferences.remove('updates.skippedBuild');
    }

    _notify();
  }

  void setViewingSettings(bool value) {
    if (value && !viewingSettings) {
      _noticeRevision++;
    }

    viewingSettings = value;
    _notify();
  }

  void start() {
    if (_started || _disposed || !supported) {
      return;
    }

    _started = true;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_start());
  }

  Future<void> _start() async {
    final noticeRevision = _noticeRevision;
    await initialize();

    if (_disposed || !supported) {
      return;
    }

    _offerNotice(noticeRevision);
    _notify();

    if (!backgroundEnabled) {
      return;
    }

    await _backgroundCheck(startup: true);

    if (!_disposed) {
      _timer = Timer.periodic(const Duration(hours: 1), (_) => unawaited(_backgroundCheck()));
    }
  }

  Future<void> initialize() => _initialization ??= _restore();

  Future<void> _restore() async {
    try {
      channel = await channelProvider();

      if (!supported) {
        return;
      }

      final info = await appInfo();
      final currentBuild = int.parse(info.buildNumber);
      _currentBuild = currentBuild;
      final cached = preferences.getString('updates.known');

      if (cached == null) {
        return;
      }

      final data = jsonDecode(cached) as Map<String, dynamic>;
      if (currentBuild < 1 || data['channel'] != channel!.name || (data['build'] as int) <= currentBuild) {
        await preferences.remove('updates.known');
        return;
      }

      if (channel != UpdateChannel.play) {
        release = UpdateRelease.fromJson(data['release'] as Map<String, dynamic>);

        if (release!.buildNumber != data['build']) {
          throw const FormatException('Invalid cached update');
        }

        if (!external) {
          release!.asset(_assetKey);
        }
      }

      _offeredBuild = data['build'] as int;
      available = true;
      status = UpdateStatus.available;
      message = 'A newer version of Papyrus is available.';
    } catch (_) {
      release = null;
      await preferences.remove('updates.known');
    } finally {
      _notify();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && backgroundEnabled && supported) {
      // Returning from an installer or permission screen must refresh eligibility.
      if (status == UpdateStatus.handedOff) {
        unawaited(check());
      } else {
        unawaited(_backgroundCheck());
      }
    }
  }

  Future<void> setAutomatic(bool value) async {
    await preferences.setBool('updates.automatic', value);
    _notify();
  }

  Future<void> _backgroundCheck({bool startup = false}) async {
    final lastCheck = preferences.getInt('updates.lastCheck') ?? 0;
    final checkedBuild = preferences.getInt('updates.checkedBuild');
    final elapsed = DateTime.now().millisecondsSinceEpoch - lastCheck;
    final recentlyChecked =
        checkedBuild != null &&
        checkedBuild == _currentBuild &&
        elapsed >= 0 &&
        elapsed < const Duration(days: 1).inMilliseconds;

    if (!supported || viewingSettings || !automatic || (!startup && recentlyChecked)) {
      return;
    }

    await check(notifyUser: true);
  }

  void _offerNotice(int revision) {
    if (revision == _noticeRevision && !viewingSettings && available && !skipped && _offeredBuild != _dismissedBuild) {
      _noticeVisible = true;
    }
  }

  Future<void> check({bool notifyUser = false}) async {
    final noticeRevision = _noticeRevision;
    await initialize();

    if (!supported || busy || staged || _disposed) {
      return;
    }

    busy = true;
    checking = true;
    status = UpdateStatus.checking;
    _notify();

    try {
      channel = await channelProvider();
      final info = await appInfo();
      final currentBuild = int.tryParse(info.buildNumber);
      int? offeredBuild;
      Map<String, dynamic>? offeredRelease;

      if (currentBuild == null || currentBuild < 1) {
        throw const FormatException('Installed build number is unavailable');
      }

      if (channel == UpdateChannel.play) {
        final build = await playCheck();
        available = build != null && build > currentBuild;
        offeredBuild = build;
      } else {
        final data = await manifest();
        offeredRelease = {...data, 'assets': data['assets'] ?? <String, dynamic>{}};
        final candidate = UpdateRelease.fromJson(offeredRelease);

        if (candidate.buildNumber > currentBuild && !external) {
          candidate.asset(_assetKey);
        }

        release = candidate;
        offeredBuild = candidate.buildNumber;
        available = release!.buildNumber > currentBuild;
      }

      _offeredBuild = available ? offeredBuild : null;

      if (available) {
        await preferences.setString(
          'updates.known',
          jsonEncode({
            'channel': channel!.name,
            'build': offeredBuild,
            'release': ?offeredRelease,
          }),
        );
      } else {
        _noticeVisible = false;
        await preferences.remove('updates.known');
      }

      if (notifyUser) {
        _offerNotice(noticeRevision);
      }

      status = available ? UpdateStatus.available : UpdateStatus.upToDate;
      message = available ? 'A newer version of Papyrus is available.' : 'Papyrus is up to date.';
      await preferences.setInt('updates.checkedBuild', currentBuild);
      await preferences.setInt('updates.lastCheck', DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      message = checkFailureMessage;
      status = UpdateStatus.checkFailed;
    } finally {
      checking = false;
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
    if (!supported || busy || !available || staged || external || _disposed) {
      return;
    }

    busy = true;
    progress = null;
    status = UpdateStatus.installing;
    message = 'Preparing the update…';
    _notify();

    try {
      final asset = channel == UpdateChannel.play ? null : release!.asset(_assetKey);

      var previousPercent = -1;

      message = await installer(asset, (value) {
        final percent = value == null ? 0 : (value * 100).floor();

        if (percent == previousPercent) {
          return;
        }

        previousPercent = percent;
        progress = value;

        if (value == 1 && channel == UpdateChannel.windows) {
          message = 'Installing…';
        } else {
          message = value == null ? 'Downloading update…' : 'Downloading update: ${(value * 100).floor()}%';
        }

        _notify();
      });

      staged = channel == UpdateChannel.windows || channel == UpdateChannel.appImage;
      status = staged ? UpdateStatus.staged : UpdateStatus.handedOff;
    } on UpdateInstallException catch (error) {
      message = error.message;
      status = UpdateStatus.installFailed;
    } catch (_) {
      message = 'Could not finish the update. Please try again.';
      status = UpdateStatus.installFailed;
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

    if (_started) {
      WidgetsBinding.instance.removeObserver(this);
    }

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
