import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:papyrus/providers/reading_timer_provider.dart';

/// Bridges native controls to the existing, profile-scoped timer repository.
/// Native actions are durably journaled before acknowledgement, including while
/// iOS suspends Dart. Their original timestamps are used when replaying them.
class ReadingTimerNotifications with WidgetsBindingObserver {
  ReadingTimerNotifications(this.timer, {required this.onOpen, MethodChannel? channel, bool? supported})
    : _channel = channel ?? const MethodChannel('papyrus/reading_timer'),
      _supported =
          supported ?? (!kIsWeb && [TargetPlatform.android, TargetPlatform.iOS].contains(defaultTargetPlatform)) {
    if (!_supported) {
      return;
    }

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'open') {
        onOpen();
      } else if (call.method == 'changed') {
        _lastPublished = null;
        _schedule();
      }
    });
    timer.addListener(_schedule);
    WidgetsBinding.instance.addObserver(this);
    _schedule();
  }

  final ReadingTimerProvider timer;
  final VoidCallback onOpen;
  final MethodChannel _channel;
  final bool _supported;
  bool _disposed = false;
  bool _syncing = false;
  bool _queued = false;
  String? _lastPublished;
  Object? _library;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _lastPublished = null;
      _schedule();
    }
  }

  void _schedule() {
    if (_disposed) {
      return;
    }

    _queued = true;

    if (!_syncing) {
      unawaited(_sync());
    }
  }

  Future<void> _sync() async {
    _syncing = true;

    try {
      while (_queued && !_disposed) {
        _queued = false;

        if (_library != null && !identical(_library, timer.libraryIdentity)) {
          await _channel.invokeMethod<void>('clear');
          _lastPublished = null;
        }

        _library = timer.libraryIdentity;

        if (!timer.available || timer.busy) {
          continue;
        }

        final pending = await _channel.invokeMapMethod<String, dynamic>('pending');

        if (_disposed || !timer.available || timer.busy) {
          continue;
        }

        if (pending != null) {
          final applied = await timer.applyNotificationActions(pending);

          if (!applied) {
            // Retain the journal for a later retry if storage is unavailable.
            break;
          }

          await _channel.invokeMethod<void>('acknowledge', {
            'through': pending['through'],
            'snapshot': snapshot(timer),
          });
          _lastPublished = null;
          _queued = true;
          continue;
        }

        final value = snapshot(timer);
        final encoded = jsonEncode(value);

        if (encoded != _lastPublished) {
          await _channel.invokeMethod<void>('publish', {
            'snapshot': value,
            'foreground': WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
          });
          _lastPublished = encoded;
        }
      }
    } on MissingPluginException {
      // Unsupported runtimes and older local builds keep the in-app timer.
    } on PlatformException catch (error) {
      debugPrint('Timer notification unavailable: ${error.code}');
    } finally {
      _syncing = false;
    }
  }

  static Map<String, dynamic>? snapshot(ReadingTimerProvider timer) {
    final session = timer.session;

    if (session == null) {
      return null;
    }

    final view = timer.goalReached ? session.stop(timer.now, finish: true) : session;

    return {
      'id': session.id,
      'version': session.version,
      'title': String.fromCharCodes(session.bookTitle.runes.take(200)),
      'phase': view.phase.name,
      'recordedMs': view.recorded.inMilliseconds,
      'runningSinceMs': view.runningSince?.millisecondsSinceEpoch,
      'targetMs': view.targetSeconds == null ? null : view.targetSeconds! * 1000,
    };
  }

  void dispose() {
    _disposed = true;

    if (_supported) {
      timer.removeListener(_schedule);
      WidgetsBinding.instance.removeObserver(this);
      _channel.setMethodCallHandler(null);
    }
  }
}
