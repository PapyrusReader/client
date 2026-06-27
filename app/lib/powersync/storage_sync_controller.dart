import 'package:papyrus/powersync/powersync_service.dart';
import 'package:papyrus/powersync/sync_state.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/providers/sync_settings_provider.dart';

class StorageSyncController {
  StorageSyncController({
    required this.authProvider,
    required this.powerSyncService,
    required this.syncSettings,
    required this.syncState,
  });

  final AuthProvider authProvider;
  final PapyrusPowerSyncService powerSyncService;
  final SyncSettingsProvider syncSettings;
  final SyncState syncState;

  LibraryDatabaseMode? get databaseMode => powerSyncService.mode;

  bool get isGuest => authProvider.isOfflineMode || databaseMode == LibraryDatabaseMode.guest;
  bool get isAuthenticated => authProvider.isSignedIn && databaseMode == LibraryDatabaseMode.authenticated;
  bool get isSignedOut => !authProvider.isSignedIn && !authProvider.isOfflineMode;

  String get modeLabel {
    if (isGuest) return 'Guest local';
    if (isAuthenticated) return 'Account synced';
    return 'Signed out';
  }

  String get databaseLabel {
    switch (databaseMode) {
      case LibraryDatabaseMode.guest:
        return 'papyrus-guest.db';
      case LibraryDatabaseMode.authenticated:
        return 'Server-scoped account cache';
      case null:
        return 'No active library database';
    }
  }

  String get backendLabel {
    if (isAuthenticated) return syncSettings.activeServerLabel;
    if (isGuest) return 'Local only';
    return 'Not connected';
  }

  String get metadataSyncLabel {
    if (isGuest) return 'Metadata sync off';
    return syncSettings.activeServerLabel;
  }

  bool get shouldShowServerSettings => !isGuest;

  bool get shouldShowCustomServerUrls {
    return shouldShowServerSettings && syncSettings.serverType == SyncServerType.custom;
  }

  String get mediaStorageLabel => syncSettings.mediaStorageLabel;

  String? get mediaStorageRestrictionMessage => syncSettings.mediaStorageRestrictionMessage;

  String get statusLabel {
    if (isGuest) return 'Guest local';
    if (isSignedOut) return 'Signed out';
    if (syncState.uploadError != null || syncState.downloadError != null) return 'Error';
    if (syncState.connecting) return 'Connecting';
    if (syncState.uploading || syncState.downloading) return 'Syncing';
    if (syncState.connected) {
      return syncState.hasPendingWrites ? 'Pending upload' : 'Connected';
    }
    return 'Offline';
  }

  String get syncDetail {
    final error = syncState.uploadError ?? syncState.downloadError;
    if (error != null) return 'Sync error: $error';
    if (syncState.hasPendingWrites) return 'Local changes are waiting to upload';
    final lastSyncedAt = syncState.lastSyncedAt;
    if (lastSyncedAt == null) return 'No completed sync yet';
    return 'Last sync: ${lastSyncedAt.toLocal()}';
  }

  String get pendingWritesLabel =>
      syncState.hasPendingWrites ? 'Local changes pending upload' : 'No pending local writes';

  bool get canReconnect => isAuthenticated;
  bool get canClearGuestLibrary => databaseMode == LibraryDatabaseMode.guest;
  bool get canClearAuthenticatedCache => databaseMode == LibraryDatabaseMode.authenticated;

  Future<void> reconnect() => powerSyncService.reconnect();
  Future<void> clearGuestLibrary() => powerSyncService.clearGuestLibrary();
  Future<void> clearAuthenticatedCache() => powerSyncService.clearAuthenticatedCache();
}
