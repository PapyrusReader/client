import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/media/media_upload_queue.dart';
import 'package:papyrus/powersync/powersync_service.dart';
import 'package:papyrus/powersync/storage_sync_controller.dart';
import 'package:papyrus/powersync/sync_state.dart';
import 'package:papyrus/providers/acquisition_availability_provider.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/providers/preferences_provider.dart';
import 'package:papyrus/providers/sync_settings_provider.dart';
import 'package:papyrus/services/book_import_service_stub.dart'
    if (dart.library.js_interop) 'package:papyrus/services/book_import_service.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/settings/settings_row.dart';
import 'package:papyrus/widgets/settings/settings_section.dart';
import 'package:provider/provider.dart';

/// Storage, synchronization, and acquisition settings section.
///
/// Supports both mobile ListView presentation and desktop card layout.
class StorageSyncSettingsSection extends StatelessWidget {
  final bool isDesktop;

  const StorageSyncSettingsSection({super.key, this.isDesktop = false});

  @override
  Widget build(BuildContext context) {
    if (isDesktop) {
      return _buildDesktopContent(context);
    }
    return _buildMobileSection(context);
  }

  // ============================================================================
  // MOBILE PRESENTATION
  // ============================================================================

  Widget _buildMobileSection(BuildContext context) {
    final controller = _storageSyncController(context);

    if (controller.isGuest) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SettingsSectionHeader(title: 'Storage'),
          const SettingsRow(label: 'Library', value: 'Stored on this device'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xs),
            child: Text(
              'Nothing is sent to Papyrus servers while offline mode is on.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          SettingsRow(
            label: 'Backup',
            value: 'Export or import a backup',
            onTap: () => _showOfflineBackupActions(context),
          ),
          SettingsRow(label: 'Clear local library', onTap: () => _confirmClearLocalLibrary(context)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(title: 'Storage'),
        SettingsRow(
          label: 'Data sync',
          value: controller.dataSyncLabel,
          onTap: () => _showManageSyncServersSheet(context),
        ),
        SettingsRow(label: 'Current status', value: controller.statusLabel),
        SettingsRow(label: 'File storage', value: controller.fileStorageLabel),
        if (controller.hasFailedMediaUploads)
          SettingsRow(
            label: 'Media uploads',
            value: controller.failedMediaUploadLabel,
            onTap: () => _retryFailedMediaUploads(context),
          ),
        SettingsRow(label: 'Manage servers', onTap: () => _showManageSyncServersSheet(context)),
        if (controller.canReconnect) SettingsRow(label: 'Reconnect', onTap: () => _handleReconnectSync(context)),
        if (controller.canClearGuestLibrary)
          SettingsRow(label: 'Clear local library', onTap: () => _confirmClearLocalLibrary(context)),
        if (controller.canClearAuthenticatedCache)
          SettingsRow(label: 'Clear local copy', onTap: () => _confirmClearAuthenticatedCache(context)),
      ],
    );
  }

  // ============================================================================
  // DESKTOP PRESENTATION
  // ============================================================================

  Widget _buildDesktopContent(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final controller = _storageSyncController(context);

    if (controller.isGuest) return _buildOfflineStorageSyncContent(context);

    return Column(
      children: [
        SettingsCard(
          key: const Key('profile-data-sync-card'),
          title: 'Data sync',
          children: [
            _buildInfoRow(context, label: 'Active server', value: controller.dataSyncLabel),
            _buildInfoRow(context, label: 'Status', value: controller.statusLabel),
            _buildInfoRow(context, label: 'File storage', value: controller.fileStorageLabel),
            if (controller.hasFailedMediaUploads)
              _buildInfoRow(context, label: 'Media uploads', value: controller.failedMediaUploadLabel),
            const SizedBox(height: Spacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xs),
              child: Text(
                controller.syncDetail,
                style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              alignment: WrapAlignment.start,
              children: [
                if (controller.canReconnect)
                  OutlinedButton.icon(
                    onPressed: () => _handleReconnectSync(context),
                    icon: const Icon(Icons.sync, size: IconSizes.small),
                    label: const Text('Reconnect'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _showManageSyncServersSheet(context),
                  icon: const Icon(Icons.dns_outlined, size: IconSizes.small),
                  label: const Text('Manage servers'),
                ),
                if (controller.hasFailedMediaUploads)
                  OutlinedButton.icon(
                    onPressed: () => _retryFailedMediaUploads(context),
                    icon: const Icon(Icons.refresh, size: IconSizes.small),
                    label: const Text('Retry uploads'),
                  ),
                if (controller.canClearAuthenticatedCache)
                  OutlinedButton.icon(
                    onPressed: () => _confirmClearAuthenticatedCache(context),
                    icon: const Icon(Icons.cleaning_services_outlined, size: IconSizes.small),
                    label: const Text('Clear local copy'),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        SettingsCard(
          key: const Key('profile-acquisition-card'),
          title: 'Acquisition',
          children: [_buildAcquisitionDescription(context), ..._buildAcquisitionSettings(context)],
        ),
      ],
    );
  }

  Widget _buildOfflineStorageSyncContent(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final mutedStyle = textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

    return SettingsCard(
      title: 'Library storage',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your library is stored on this device.', style: textTheme.bodyLarge),
              const SizedBox(height: Spacing.sm),
              Text(
                'Nothing is sent to Papyrus servers while offline mode is on. Export a backup before changing devices or clearing app data.',
                style: mutedStyle,
              ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.md),
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          children: [
            OutlinedButton.icon(
              onPressed: () => _showBackupUnavailable(context, 'Backup export'),
              icon: const Icon(Icons.file_download_outlined, size: IconSizes.small),
              label: const Text('Export backup'),
            ),
            OutlinedButton.icon(
              onPressed: () => _showBackupUnavailable(context, 'Backup import'),
              icon: const Icon(Icons.file_upload_outlined, size: IconSizes.small),
              label: const Text('Import backup'),
            ),
            OutlinedButton.icon(
              onPressed: () => _confirmClearLocalLibrary(context),
              icon: const Icon(Icons.delete_outline, size: IconSizes.small),
              label: const Text('Clear local library'),
            ),
          ],
        ),
      ],
    );
  }

  // ============================================================================
  // ACQUISITION HELPERS
  // ============================================================================

  static Widget buildMobileAcquisitionSection(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.isOfflineMode) return const SizedBox.shrink();

    return Column(
      key: const Key('profile-acquisition-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(title: 'Acquisition'),
        _buildAcquisitionDescription(context),
        ..._buildAcquisitionSettings(context),
      ],
    );
  }

  static Widget _buildAcquisitionDescription(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xs),
      child: Text(
        'Search external sources and send releases to your connected clients.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }

  static List<Widget> _buildAcquisitionSettings(BuildContext context) {
    final prefs = context.watch<PreferencesProvider>();
    final availability = context.watch<AcquisitionAvailabilityProvider>();
    final acquisitionAvailable = availability.state == AcquisitionAvailabilityState.available;

    return [
      MergeSemantics(
        child: Semantics(
          label: 'Enable acquisition',
          enabled: true,
          toggled: prefs.acquisitionEnabled,
          onTap: () => prefs.acquisitionEnabled = !prefs.acquisitionEnabled,
          child: ExcludeSemantics(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => prefs.acquisitionEnabled = !prefs.acquisitionEnabled,
              child: SettingsToggleRow(
                label: 'Enable acquisition',
                value: prefs.acquisitionEnabled,
                onChanged: (value) => prefs.acquisitionEnabled = value,
              ),
            ),
          ),
        ),
      ),
      SettingsRow(
        label: 'Server support',
        value: _acquisitionAvailabilityLabel(availability.state),
        showChevron: false,
      ),
      if (prefs.acquisitionEnabled && acquisitionAvailable)
        SettingsRow(label: 'Manage integrations', onTap: () => context.push('/acquisition')),
    ];
  }

  static String _acquisitionAvailabilityLabel(AcquisitionAvailabilityState state) {
    return switch (state) {
      AcquisitionAvailabilityState.available => 'Available on this server',
      AcquisitionAvailabilityState.unavailable => 'Unavailable on this server',
      AcquisitionAvailabilityState.unknown || AcquisitionAvailabilityState.loading => 'Checking server support…',
    };
  }

  // ============================================================================
  // STORAGE CONTROLLER & HELPERS
  // ============================================================================

  StorageSyncController _storageSyncController(BuildContext context) {
    return StorageSyncController(
      authProvider: context.watch<AuthProvider>(),
      powerSyncService: context.read<PapyrusPowerSyncService>(),
      syncSettings: context.watch<SyncSettingsProvider>(),
      syncState: context.watch<SyncState>(),
      fileStorageUsedBytes: _fileStorageUsedBytes(context.watch<DataStore>()),
      mediaStorageUsage: context.watch<MediaUploadQueue>().storageUsage,
      failedMediaUploadCount: _failedMediaUploadCount(context.watch<MediaUploadQueue>()),
    );
  }

  int _fileStorageUsedBytes(DataStore dataStore) {
    return dataStore.books.fold<int>(0, (total, book) => total + (book.fileSize ?? 0));
  }

  int _failedMediaUploadCount(MediaUploadQueue queue) {
    return queue.pendingTasks.where((task) => task.status == MediaUploadTaskStatus.failed).length;
  }

  Widget _buildInfoRow(BuildContext context, {required String label, required String value}) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(label, style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: SelectableText(value, style: textTheme.bodyMedium)),
        ],
      ),
    );
  }

  // ============================================================================
  // ACTIONS & DIALOGS
  // ============================================================================

  void _showManageSyncServersSheet(BuildContext context) {
    showModalBottomSheet(
      sheetAnimationStyle: AppMotion.animationStyle(context),
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Consumer<SyncSettingsProvider>(
          builder: (context, settings, _) {
            return ListView(
              shrinkWrap: true,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.md, Spacing.md, Spacing.sm),
                  child: Text('Sync servers', style: Theme.of(context).textTheme.titleMedium),
                ),
                ListTile(
                  leading: Icon(
                    settings.activeServerId == SyncSettingsProvider.officialServerId
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  title: const Text('Official server'),
                  subtitle: const Text('Papyrus-hosted data sync and file storage'),
                  onTap: () {
                    settings.selectServer(SyncSettingsProvider.officialServerId);
                    Navigator.pop(sheetContext);
                  },
                ),
                for (final server in settings.customServers)
                  ListTile(
                    leading: Icon(
                      settings.activeServerId == server.id ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    ),
                    title: Text(server.label),
                    subtitle: Text(server.url),
                    onTap: () {
                      settings.selectServer(server.id);
                      Navigator.pop(sheetContext);
                    },
                    trailing: PopupMenuButton<String>(
                      popUpAnimationStyle: AppMotion.animationStyle(context),
                      onSelected: (value) {
                        if (value == 'edit') {
                          Navigator.pop(sheetContext);
                          unawaited(_showCustomServerDialog(context, server: server));
                        } else if (value == 'remove') {
                          settings.removeCustomServer(server.id);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(value: 'remove', child: Text('Remove')),
                      ],
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('Add custom server'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    unawaited(_showCustomServerDialog(context));
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _showCustomServerDialog(BuildContext context, {CustomSyncServer? server}) async {
    final settings = context.read<SyncSettingsProvider>();
    final urlController = TextEditingController(text: server?.url ?? '');
    final messenger = ScaffoldMessenger.of(context);
    final snackBarAnimationStyle = AppMotion.animationStyle(context);

    try {
      await showDialog<void>(
        animationStyle: AppMotion.animationStyle(context),
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(server == null ? 'Add custom server' : 'Edit custom server'),
          content: TextField(
            controller: urlController,
            decoration: const InputDecoration(labelText: 'Server URL'),
            keyboardType: TextInputType.url,
            autofocus: true,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                try {
                  if (server == null) {
                    await settings.addCustomServer(urlController.text);
                  } else {
                    await settings.updateCustomServer(server.id, urlController.text);
                  }
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                } catch (error) {
                  messenger.showSnackBar(
                    snackBarAnimationStyle: snackBarAnimationStyle,
                    SnackBar(content: Text('Could not save server: $error')),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );
    } finally {
      urlController.dispose();
    }
  }

  Future<void> _handleReconnectSync(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final snackBarAnimationStyle = AppMotion.animationStyle(context);
    try {
      await context.read<PapyrusPowerSyncService>().reconnect();
      messenger.showSnackBar(
        snackBarAnimationStyle: snackBarAnimationStyle,
        const SnackBar(content: Text('Sync reconnect requested.')),
      );
    } catch (error) {
      messenger.showSnackBar(
        snackBarAnimationStyle: snackBarAnimationStyle,
        SnackBar(content: Text('Could not reconnect sync: $error')),
      );
    }
  }

  Future<void> _retryFailedMediaUploads(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final snackBarAnimationStyle = AppMotion.animationStyle(context);
    await context.read<MediaUploadQueue>().retryFailed();
    messenger.showSnackBar(
      snackBarAnimationStyle: snackBarAnimationStyle,
      const SnackBar(content: Text('Media uploads will retry on the next sync.')),
    );
  }

  void _showOfflineBackupActions(BuildContext context) {
    showModalBottomSheet(
      sheetAnimationStyle: AppMotion.animationStyle(context),
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: const Text('Export backup'),
              subtitle: const Text('Save a copy for another device'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showBackupUnavailable(context, 'Backup export');
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_upload_outlined),
              title: const Text('Import backup'),
              subtitle: const Text('Restore from a saved copy'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showBackupUnavailable(context, 'Backup import');
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showBackupUnavailable(BuildContext context, String action) {
    ScaffoldMessenger.of(context).showSnackBar(
      snackBarAnimationStyle: AppMotion.animationStyle(context),
      SnackBar(content: Text('$action is not available yet.')),
    );
  }

  Future<void> _confirmClearLocalLibrary(BuildContext context) async {
    final confirmed = await _confirmStorageAction(
      context,
      title: 'Clear local library',
      message:
          'This deletes the library stored on this device. This cannot be undone unless you have exported a backup.',
      actionLabel: 'Clear library',
    );
    if (!confirmed || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final snackBarAnimationStyle = AppMotion.animationStyle(context);
    try {
      await context.read<PapyrusPowerSyncService>().clearGuestLibrary();
      messenger.showSnackBar(
        snackBarAnimationStyle: snackBarAnimationStyle,
        const SnackBar(content: Text('Local library cleared.')),
      );
    } catch (error) {
      messenger.showSnackBar(
        snackBarAnimationStyle: snackBarAnimationStyle,
        SnackBar(content: Text('Could not clear local library: $error')),
      );
    }
  }

  Future<void> _confirmClearAuthenticatedCache(BuildContext context) async {
    final confirmed = await _confirmStorageAction(
      context,
      title: 'Clear local copy',
      message:
          'This removes synced library data stored on this device. Your library stays on the server and will download again when sync reconnects.',
      actionLabel: 'Clear local copy',
    );
    if (!confirmed || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final snackBarAnimationStyle = AppMotion.animationStyle(context);
    try {
      final scope = context.read<MediaUploadQueue>().activeScope;
      final powerSyncService = context.read<PapyrusPowerSyncService>();
      final importService = context.read<BookImportService>();
      await powerSyncService.clearAuthenticatedCache();
      if (scope != null) {
        await importService.clearCoverFiles(scope);
      }
      messenger.showSnackBar(
        snackBarAnimationStyle: snackBarAnimationStyle,
        const SnackBar(content: Text('Local copy cleared.')),
      );
    } catch (error) {
      messenger.showSnackBar(
        snackBarAnimationStyle: snackBarAnimationStyle,
        SnackBar(content: Text('Could not clear local copy: $error')),
      );
    }
  }

  Future<bool> _confirmStorageAction(
    BuildContext context, {
    required String title,
    required String message,
    required String actionLabel,
  }) async {
    return await showDialog<bool>(
          animationStyle: AppMotion.animationStyle(context),
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(actionLabel)),
            ],
          ),
        ) ??
        false;
  }
}
