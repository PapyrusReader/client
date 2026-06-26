enum LibraryDatabaseMode { guest, authenticated }

class SyncState {
  final bool connected;
  final bool connecting;
  final bool uploading;
  final bool downloading;
  final bool hasPendingWrites;
  final DateTime? lastSyncedAt;
  final Object? uploadError;
  final Object? downloadError;

  const SyncState({
    this.connected = false,
    this.connecting = false,
    this.uploading = false,
    this.downloading = false,
    this.hasPendingWrites = false,
    this.lastSyncedAt,
    this.uploadError,
    this.downloadError,
  });
}
