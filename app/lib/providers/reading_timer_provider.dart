import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/data/repositories/reading_timer_repository.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/services/reading_device_identity.dart';
import 'package:papyrus/timer/reading_timer.dart';

class ReadingTimerProvider extends ChangeNotifier {
  ReadingTimerProvider(this.store, {DateTime Function()? now, bool tick = true}) : _now = now ?? DateTime.now {
    store.addListener(_libraryChanged);
    _libraryChanged();

    if (tick) {
      _clock = Timer.periodic(const Duration(seconds: 1), (_) {
        _libraryChanged();

        final seconds = session?.elapsed(this.now).inSeconds;

        if (seconds != _lastSecond) {
          _lastSecond = seconds;
          notifyListeners();
        }
      });
    }
  }

  final DataStore store;
  final DateTime Function() _now;
  Timer? _clock;
  StreamSubscription<ReadingTimer?>? _subscription;
  ReadingTimerRepository? _repository;
  ReadingTimer? _session;
  int _generation = 0;
  int? _lastSecond;
  bool _disposed = false;
  bool loading = false;
  bool busy = false;
  String? error;

  DateTime get now => _now().toUtc();
  Object? get libraryIdentity => _repository;
  ReadingTimer? get session => _repository?.isCurrent == true ? _session : null;
  bool get available => _repository?.isCurrent == true && !loading;
  Duration get elapsed => session?.elapsed(now) ?? Duration.zero;
  bool get running => session?.isRunning(now) == true;
  bool get goalReached => session?.reachedGoal(now) == true;
  bool get finished => goalReached || session?.phase == ReadingTimerPhase.finished;

  ReadingTimerRepository? _currentRepository() {
    try {
      final repository = store.trackingRepository;

      if (repository is ReadingTimerRepository) {
        final timerRepository = repository as ReadingTimerRepository;
        return timerRepository.isCurrent ? timerRepository : null;
      }

      return null;
    } on StateError {
      return null;
    }
  }

  void _libraryChanged() {
    final repository = _currentRepository();

    if (identical(repository, _repository)) {
      return;
    }

    unawaited(_subscription?.cancel());
    _subscription = null;
    _repository = repository;
    _session = null;
    error = null;
    busy = false;
    loading = repository != null;
    _generation++;

    if (repository != null) {
      final generation = _generation;
      _subscription = repository.watchTimer().listen(
        (value) {
          if (_isCurrent(generation, repository)) {
            _session = value;
            loading = false;
            notifyListeners();
          }
        },
        onError: (Object failure) {
          if (_isCurrent(generation, repository)) {
            loading = false;
            error = 'Your timer could not be loaded. Try again.';
            notifyListeners();
          }
        },
      );
    } else {
      notifyListeners();
    }
  }

  Future<void> reload() async {
    final repository = _repository;
    final generation = _generation;

    if (repository == null) {
      return;
    }

    loading = true;
    error = null;
    notifyListeners();

    try {
      final restored = await repository.loadTimer();

      if (_isCurrent(generation, repository)) {
        _session = restored;
      }
    } catch (_) {
      if (_isCurrent(generation, repository)) {
        error = 'Your timer could not be loaded. Try again.';
      }
    } finally {
      if (_isCurrent(generation, repository)) {
        loading = false;
        notifyListeners();
      }
    }
  }

  bool _isCurrent(int generation, ReadingTimerRepository repository) =>
      !_disposed && generation == _generation && identical(repository, _repository) && repository.isCurrent;

  Future<bool> _change(Future<ReadingTimer?> Function(ReadingTimerRepository repository) action) async {
    final repository = _repository;
    final generation = _generation;

    if (repository == null || !available || busy) {
      return false;
    }

    busy = true;
    error = null;
    notifyListeners();

    try {
      await action(repository);
      final next = await repository.loadTimer();

      if (!_isCurrent(generation, repository)) {
        return false;
      }

      _session = next;
      return true;
    } catch (failure) {
      if (_isCurrent(generation, repository)) {
        error = failure is StateError || failure is ArgumentError
            ? failure.toString().replaceFirst(RegExp(r'^(Bad state|Invalid argument\(s\)):\s*'), '')
            : 'Your session could not be saved. Try again. Your timer is still available.';
      }

      return false;
    } finally {
      if (_isCurrent(generation, repository)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<bool> start(Book book, {int? targetSeconds}) => _change((repository) async {
    if (session != null) {
      throw StateError('Finish or discard the current session before starting another.');
    }

    final timer = ReadingTimer.start(
      book,
      now,
      ReadingDeviceIdentity.current,
      store.getShelfIdsForBook(book.id),
      targetSeconds: targetSeconds,
    );

    await repository.writeTimer(timer);
    return timer;
  });

  Future<bool> pause({bool finish = false}) => _change((repository) async {
    final previous = session!;
    final next = previous.stop(now, finish: finish);
    await repository.writeTimer(next, previous: previous);
    return next;
  });

  Future<bool> resume() => _change((repository) async {
    final previous = session!;
    final stopped = previous.stop(now);
    final next = stopped.resume(now, keepReading: goalReached);
    await repository.writeTimer(next, previous: previous);
    return next;
  });

  Future<bool> save({int? currentPage}) => _change((repository) async {
    await repository.finishTimer(session!, now, currentPage: currentPage);
    return null;
  });

  Future<bool> discard() => _change((repository) async {
    await repository.discardTimer(session!);
    return null;
  });

  /// Replays native actions at their tap times, never at app-resume time.
  /// Command IDs double as versions so a crash between writing and acknowledging
  /// cannot apply the same interval twice. A changed remote version wins.
  Future<bool> applyNotificationActions(Map<String, dynamic> batch) async {
    final current = session;
    final actions = (batch['actions'] as List).map((value) => Map<String, dynamic>.from(value as Map)).toList();
    final appliedIndex = actions.indexWhere((action) => action['id'] == current?.version);

    if (current == null ||
        current.id != batch['sessionId'] ||
        (current.version != batch['version'] && appliedIndex < 0)) {
      return true;
    }

    return _change((repository) async {
      var next = current;

      for (var index = 0; index < actions.length; index++) {
        final action = actions[index];
        final kind = action['kind'] as String;
        final at = DateTime.fromMillisecondsSinceEpoch(action['atMs'] as int, isUtc: true);

        if (index > appliedIndex) {
          final previous = next;

          next = switch (kind) {
            'pause' => next.stop(at),
            'resume' => next.stop(at).resume(at, keepReading: next.reachedGoal(at)),
            'finish' => next.stop(at, finish: true),
            _ => throw ArgumentError('Unknown timer action.'),
          };
          next = ReadingTimer.fromJson({...next.toJson(), 'version': action['id']});
          await repository.writeTimer(next, previous: previous);
        }

        if (kind == 'finish' && index >= appliedIndex) {
          if (next.elapsed(at).inSeconds < 1) {
            await repository.discardTimer(next);
          } else {
            await repository.finishTimer(next, at);
          }

          return null;
        }
      }

      return next;
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _clock?.cancel();
    unawaited(_subscription?.cancel());
    store.removeListener(_libraryChanged);
    super.dispose();
  }
}
