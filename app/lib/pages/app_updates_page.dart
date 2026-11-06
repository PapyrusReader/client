import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:papyrus/services/about_links.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/updates/update_controller.dart';
import 'package:papyrus/updates/update_release.dart';
import 'package:papyrus/widgets/settings/settings_row.dart';
import 'package:papyrus/widgets/library/library_page_header.dart';
import 'package:papyrus/widgets/shared/app_page_bar.dart';
import 'package:papyrus/widgets/shared/app_progress_indicator.dart';

class AppUpdatesPage extends StatefulWidget {
  const AppUpdatesPage({super.key, required this.controller});

  final UpdateController controller;

  @override
  State<AppUpdatesPage> createState() => _AppUpdatesPageState();
}

typedef _UpdatePresentation = ({
  String title,
  String? detail,
  String action,
  DateTime? lastChecked,
  bool externalLink,
});

class _AppUpdatesPageState extends State<AppUpdatesPage> {
  static const _feedbackDelay = Duration(milliseconds: 300);
  static const _checkFailedTitle = 'Couldn’t check for updates';

  late final Future<PackageInfo> _installedVersion = widget.controller.appInfo();
  late _UpdatePresentation _presentation;
  Timer? _feedbackTimer;
  bool _showCheckFeedback = false;

  @override
  void initState() {
    super.initState();
    _presentation = _currentPresentation();
    widget.controller.addListener(_handleUpdate);

    if (widget.controller.checking) {
      _scheduleFeedback();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleUpdate);
    _feedbackTimer?.cancel();
    super.dispose();
  }

  void _scheduleFeedback() {
    _feedbackTimer ??= Timer(_feedbackDelay, () {
      if (mounted && widget.controller.checking) {
        setState(() => _showCheckFeedback = true);
      }
    });
  }

  void _handleUpdate() {
    // Keep the previous result's geometry until a new check result arrives.
    if (widget.controller.checking) {
      _scheduleFeedback();
    } else {
      _feedbackTimer?.cancel();
      _feedbackTimer = null;
      _showCheckFeedback = false;
      _presentation = _currentPresentation();
    }

    setState(() {});
  }

  _UpdatePresentation _currentPresentation() {
    final controller = widget.controller;

    return (
      title: _statusTitle(controller),
      detail: _statusDetail(controller),
      action: _actionLabel(controller),
      lastChecked: controller.lastChecked,
      externalLink: controller.external && !controller.available && !controller.busy,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = widget.controller;
    final lastChecked = _presentation.lastChecked;
    final compact = MediaQuery.sizeOf(context).width < Breakpoints.desktopSmall;

    final content = SingleChildScrollView(
      padding: EdgeInsets.all(compact ? Spacing.md : Spacing.lg),
      child: Align(
        alignment: AlignmentDirectional.topStart,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: compact ? 600 : 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Installed version', style: theme.textTheme.bodyMedium),
              const SizedBox(height: Spacing.xs),
              FutureBuilder<PackageInfo>(
                future: _installedVersion,
                builder: (context, snapshot) => Text(
                  switch (snapshot) {
                    AsyncSnapshot(data: final PackageInfo info) => AboutLinks.versionLabel(info),
                    AsyncSnapshot(hasError: true) => 'Unavailable',
                    _ => 'Loading…',
                  },
                  style: theme.textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: Spacing.md),
              Semantics(
                liveRegion: true,
                // Reserve wrapped error text so a failed check never moves the action.
                child: IndexedStack(
                  index: 0,
                  alignment: AlignmentDirectional.topStart,
                  children: [
                    Text(_presentation.title, style: theme.textTheme.titleLarge),
                    Text(_checkFailedTitle, style: theme.textTheme.titleLarge),
                  ],
                ),
              ),
              if (lastChecked != null) ...[
                const SizedBox(height: Spacing.sm),
                Text(
                  _lastCheckedLabel(context, lastChecked),
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
              if (_presentation.detail case final String detail) ...[
                const SizedBox(height: Spacing.sm),
                Text(detail, style: theme.textTheme.bodyMedium),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
                child: SizedBox(
                  height: Spacing.xs,
                  child: controller.busy && (!controller.checking || _showCheckFeedback)
                      ? AppLinearProgressIndicator(
                          value: controller.progress,
                          semanticsLabel: controller.checking ? 'Checking for updates' : 'Update progress',
                        )
                      : null,
                ),
              ),
              if (!controller.staged)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton(
                    key: const ValueKey('check-updates'),
                    onPressed: controller.busy ? null : () => _performAction(context, controller),
                    style: controller.checking
                        ? FilledButton.styleFrom(
                            disabledBackgroundColor: theme.colorScheme.primary,
                            disabledForegroundColor: theme.colorScheme.onPrimary,
                          )
                        : null,
                    child: IndexedStack(
                      index: controller.checking && _showCheckFeedback ? 1 : 0,
                      alignment: Alignment.center,
                      children: [Text(_presentation.action), const Text('Checking…')],
                    ),
                  ),
                ),
              if (_presentation.externalLink)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: () => _openExternalUpdate(context, controller),
                    child: Text(controller.channel == UpdateChannel.apt ? 'Repository setup' : 'Downloads'),
                  ),
                ),
              const SizedBox(height: Spacing.xl),
              const Divider(height: 1),
              const SizedBox(height: Spacing.md),
              SettingsToggleRow(
                label: 'Check automatically',
                value: controller.automatic,
                onChanged: controller.setAutomatic,
                padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
              ),
              Text(
                'Check for new versions in the background.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );

    return Scaffold(
      appBar: compact
          ? AppPageBar(context: context, title: const Text('App updates'), leading: const BackButton())
          : null,
      body: SafeArea(
        child: compact
            ? content
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const LibraryPageHeader(title: 'App updates', leading: BackButton()),
                  Expanded(child: content),
                ],
              ),
      ),
    );
  }

  String _lastCheckedLabel(BuildContext context, DateTime checked) {
    final local = checked.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final date = localizations.formatMediumDate(local);
    final time = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(local),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

    return 'Last checked $date at $time';
  }

  String _statusTitle(UpdateController controller) => switch (controller.status) {
    UpdateStatus.unchecked => controller.lastChecked == null ? 'Not checked yet' : 'Ready to check for updates',
    UpdateStatus.checking => 'Checking for updates…',
    UpdateStatus.upToDate => 'You’re up to date',
    UpdateStatus.available =>
      controller.release == null
          ? 'Update available'
          : 'Version ${controller.release!.version} (${controller.release!.buildNumber}) is available',
    UpdateStatus.installing => 'Updating Papyrus',
    UpdateStatus.staged => 'Ready to finish updating',
    UpdateStatus.handedOff => 'Update started',
    UpdateStatus.checkFailed => _checkFailedTitle,
    UpdateStatus.installFailed => 'Couldn’t finish the update',
  };

  String? _statusDetail(UpdateController controller) {
    if (controller.status == UpdateStatus.checkFailed || controller.status == UpdateStatus.installFailed) {
      return null;
    }

    if (controller.status == UpdateStatus.installing ||
        controller.status == UpdateStatus.staged ||
        controller.status == UpdateStatus.handedOff) {
      return controller.message;
    }

    if (controller.checking || (!controller.available && !controller.external)) {
      return null;
    }

    return switch (controller.channel) {
      UpdateChannel.apt =>
        'Install updates through your system’s software updater. Set up the Papyrus repository if needed.',
      UpdateChannel.manual => 'Install updates by downloading the latest Papyrus package.',
      UpdateChannel.windows => 'The update will install after you close Papyrus normally.',
      UpdateChannel.appImage => 'The update takes effect when you close and reopen Papyrus.',
      UpdateChannel.web => 'Reload when you have finished reading to use the latest version.',
      _ => 'Your device will guide you through installation.',
    };
  }

  String _actionLabel(UpdateController controller) {
    if (controller.checking) return 'Checking…';
    if (controller.busy) return 'Updating…';
    if (controller.status == UpdateStatus.checkFailed || controller.status == UpdateStatus.installFailed) {
      return 'Retry';
    }

    if (controller.available && controller.status != UpdateStatus.handedOff) {
      return switch (controller.channel) {
        UpdateChannel.web => 'Reload',
        UpdateChannel.apt => 'Repository setup',
        UpdateChannel.manual => 'Downloads',
        _ => 'Update',
      };
    }

    return 'Check for updates';
  }

  void _performAction(BuildContext context, UpdateController controller) {
    if (!controller.available || controller.status == UpdateStatus.handedOff) {
      controller.check();
      return;
    }

    switch (controller.channel) {
      case UpdateChannel.apt:
      case UpdateChannel.manual:
        _openExternalUpdate(context, controller);
      default:
        controller.install();
    }
  }

  void _openExternalUpdate(BuildContext context, UpdateController controller) {
    final uri = controller.channel == UpdateChannel.apt
        ? Uri.https('github.com', '/PapyrusReader/client/blob/master/docs/INSTALL.md')
        : AboutLinks.releases;

    AboutLinks.open(context, uri);
  }
}
