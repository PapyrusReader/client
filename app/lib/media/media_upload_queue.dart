import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/media/media_models.dart';
import 'package:papyrus/media/media_storage_scope.dart';
import 'package:papyrus/models/book.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef BookFileReader = Future<Uint8List?> Function(String bookId);
typedef MediaUploader = Future<MediaAsset> Function(MediaUploadPayload payload);

enum MediaUploadTaskStatus { pending, failed }

class MediaUploadTask {
  const MediaUploadTask({
    required this.id,
    required this.bookId,
    required this.kind,
    required this.filename,
    required this.contentType,
    required this.status,
    this.coverBase64,
    this.errorMessage,
  });

  final String id;
  final String bookId;
  final MediaKind kind;
  final String filename;
  final String contentType;
  final MediaUploadTaskStatus status;
  final String? coverBase64;
  final String? errorMessage;

  MediaUploadTask copyWith({MediaUploadTaskStatus? status, String? errorMessage}) {
    return MediaUploadTask(
      id: id,
      bookId: bookId,
      kind: kind,
      filename: filename,
      contentType: contentType,
      status: status ?? this.status,
      coverBase64: coverBase64,
      errorMessage: errorMessage,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'book_id': bookId,
      'kind': kind.apiValue,
      'filename': filename,
      'content_type': contentType,
      'status': status.name,
      'cover_base64': coverBase64,
      'error_message': errorMessage,
    };
  }

  factory MediaUploadTask.fromJson(Map<String, dynamic> json) {
    return MediaUploadTask(
      id: json['id'] as String,
      bookId: json['book_id'] as String,
      kind: MediaKind.fromApiValue(json['kind'] as String),
      filename: json['filename'] as String,
      contentType: json['content_type'] as String,
      status: MediaUploadTaskStatus.values.byName(json['status'] as String? ?? MediaUploadTaskStatus.pending.name),
      coverBase64: json['cover_base64'] as String?,
      errorMessage: json['error_message'] as String?,
    );
  }
}

class MediaUploadQueue extends ChangeNotifier {
  MediaUploadQueue(this._prefs);

  static const _storageKeyPrefix = 'media_upload_queue:';

  final SharedPreferences _prefs;
  List<MediaUploadTask> _tasks = [];
  MediaStorageScope? _activeScope;
  MediaStorageUsage? _storageUsage;
  Future<void>? _processing;

  List<MediaUploadTask> get pendingTasks => List.unmodifiable(_tasks);
  MediaStorageScope? get activeScope => _activeScope;
  MediaStorageUsage? get storageUsage => _storageUsage;

  Future<void> activateScope(MediaStorageScope? scope) async {
    if (_activeScope == scope) return;
    await waitUntilIdle();
    _activeScope = scope;
    _tasks = scope == null ? [] : _loadTasks(scope);
    _storageUsage = null;
    notifyListeners();
  }

  Future<void> waitUntilIdle() => _processing ?? Future<void>.value();

  Future<void> refreshUsage(Future<MediaStorageUsage> Function() fetchUsage) async {
    _storageUsage = await fetchUsage();
    notifyListeners();
  }

  Future<void> enqueueBookFile({required Book book, required String filename, required String contentType}) {
    return _enqueue(
      MediaUploadTask(
        id: '${book.id}:book_file',
        bookId: book.id,
        kind: MediaKind.bookFile,
        filename: filename,
        contentType: contentType,
        status: MediaUploadTaskStatus.pending,
      ),
    );
  }

  Future<void> enqueueCover({
    required Book book,
    required String filename,
    required String contentType,
    required Uint8List bytes,
  }) {
    return _enqueue(
      MediaUploadTask(
        id: '${book.id}:cover_image',
        bookId: book.id,
        kind: MediaKind.coverImage,
        filename: filename,
        contentType: contentType,
        status: MediaUploadTaskStatus.pending,
        coverBase64: base64Encode(bytes),
      ),
    );
  }

  Future<void> retryFailed({String? bookId}) async {
    final scope = _requireActiveScope();
    _tasks = _tasks
        .map((task) {
          final matchesBook = bookId == null || task.bookId == bookId;
          if (!matchesBook || task.status != MediaUploadTaskStatus.failed) {
            return task;
          }
          return task.copyWith(status: MediaUploadTaskStatus.pending);
        })
        .toList(growable: false);
    await _save(scope);
    notifyListeners();
  }

  Future<void> removeTasksForBook(String bookId) async {
    final scope = _activeScope;
    if (scope == null) return;
    _tasks = _tasks.where((task) => task.bookId != bookId).toList(growable: false);
    await _save(scope);
    notifyListeners();
  }

  Future<void> processPending({
    required DataStore dataStore,
    required BookFileReader readBookFile,
    required MediaUploader uploadMedia,
  }) {
    final inFlight = _processing;
    if (inFlight != null) return inFlight;
    final scope = _activeScope;
    if (scope == null) return Future<void>.value();

    final operation = _processPending(
      scope: scope,
      dataStore: dataStore,
      readBookFile: readBookFile,
      uploadMedia: uploadMedia,
    );
    _processing = operation;
    operation.then(
      (_) => _clearProcessing(operation),
      onError: (Object error, StackTrace stackTrace) => _clearProcessing(operation),
    );
    return operation;
  }

  Future<void> _processPending({
    required MediaStorageScope scope,
    required DataStore dataStore,
    required BookFileReader readBookFile,
    required MediaUploader uploadMedia,
  }) async {
    final nextTasks = <MediaUploadTask>[];
    for (final task in _tasks) {
      if (task.status == MediaUploadTaskStatus.failed) {
        nextTasks.add(task);
        continue;
      }

      final bytes = await _bytesForTask(task, readBookFile);
      if (bytes == null) {
        nextTasks.add(task.copyWith(status: MediaUploadTaskStatus.pending, errorMessage: 'Local file not found'));
        continue;
      }

      try {
        final asset = await uploadMedia(
          MediaUploadPayload(
            bookId: task.bookId,
            kind: task.kind,
            filename: task.filename,
            contentType: task.contentType,
            bytes: bytes,
          ),
        );
        _applyUploadedAsset(dataStore, asset);
      } on MediaUploadException catch (error) {
        nextTasks.add(
          task.copyWith(
            status: error.storageFull ? MediaUploadTaskStatus.failed : MediaUploadTaskStatus.pending,
            errorMessage: error.message,
          ),
        );
      } catch (error) {
        nextTasks.add(task.copyWith(status: MediaUploadTaskStatus.pending, errorMessage: error.toString()));
      }
    }
    _tasks = nextTasks;
    await _save(scope);
    notifyListeners();
  }

  Future<void> _enqueue(MediaUploadTask task) async {
    final scope = _requireActiveScope();
    _tasks = [..._tasks.where((existing) => existing.id != task.id), task];
    await _save(scope);
    notifyListeners();
  }

  Future<Uint8List?> _bytesForTask(MediaUploadTask task, BookFileReader readBookFile) async {
    if (task.kind == MediaKind.coverImage) {
      final coverBase64 = task.coverBase64;
      return coverBase64 == null ? null : base64Decode(coverBase64);
    }
    return readBookFile(task.bookId);
  }

  void _applyUploadedAsset(DataStore dataStore, MediaAsset asset) {
    final book = dataStore.getBook(asset.bookId);
    if (book == null) return;

    if (asset.kind == MediaKind.bookFile) {
      dataStore.updateBook(book.copyWith(fileMediaId: asset.assetId));
      return;
    }
    dataStore.updateBook(book.copyWith(coverMediaId: asset.assetId, clearCoverUrl: true));
  }

  List<MediaUploadTask> _loadTasks(MediaStorageScope scope) {
    final raw = _prefs.getString(_storageKey(scope));
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((item) => MediaUploadTask.fromJson(item as Map<String, dynamic>)).toList(growable: false);
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'papyrus media upload queue',
          context: ErrorDescription('while loading persisted media uploads'),
        ),
      );
      return [];
    }
  }

  Future<void> _save(MediaStorageScope scope) {
    return _prefs.setString(_storageKey(scope), jsonEncode(_tasks.map((task) => task.toJson()).toList()));
  }

  String _storageKey(MediaStorageScope scope) => '$_storageKeyPrefix${scope.persistenceKey}';

  MediaStorageScope _requireActiveScope() {
    final scope = _activeScope;
    if (scope == null) {
      throw StateError('Authenticated media upload scope is not active');
    }
    return scope;
  }

  void _clearProcessing(Future<void> operation) {
    if (identical(_processing, operation)) {
      _processing = null;
    }
  }
}
