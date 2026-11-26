import 'dart:async';

import 'package:flutter/material.dart';
import 'package:papyrus/services/about_links.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/updates/update_controller.dart';
import 'package:papyrus/updates/update_release.dart';
import 'package:papyrus/widgets/shared/app_motion_control.dart';
import 'package:papyrus/widgets/shared/app_progress_indicator.dart';

class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, required this.controller});

  final UpdateController controller;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

typedef _UpdatePresentation = ({
  String title,
  String? detail,
  String action,
  DateTime? lastChecked,
  bool externalLink,
});

class _UpdateDialogState extends State<UpdateDialog> {
  static const _feedbackDelay = Duration(milliseconds: 300);
  static const _checkFailedTitle = 'Couldn’t check for updates';

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
    final compact = MediaQuery.sizeOf(context).width < Breakpoints.tablet;

    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.all(Spacing.lg),
      contentPadding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, Spacing.sm),
      titlePadding: compact ? const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.sm, 0) : null,
      title: compact
          ? Row(
              children: [
                const Expanded(child: Text('App updates')),
                CloseButton(key: const ValueKey('close-update-dialog')),
              ],
            )
          : const Text('App updates'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(_presentation.title, style: theme.textTheme.titleMedium),
            ),
            if (lastChecked != null && !controller.available) ...[
              const SizedBox(height: Spacing.sm),
              Text(_lastCheckedLabel(context, lastChecked), style: theme.textTheme.bodySmall),
            ],
            if (_presentation.detail case final String detail) ...[
              const SizedBox(height: Spacing.sm),
              Text(detail, style: theme.textTheme.bodyMedium),
            ],
            if (!controller.available || controller.busy)
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
            if (controller.available && !controller.staged && !controller.busy)
              Theme(
                data: theme.copyWith(
                  splashFactory: NoSplash.splashFactory,
                  highlightColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                ),
                child: AppMotionControl(
                  value: controller.skipped,
                  builder: (focusNode) => MergeSemantics(
                    child: ListTile(
                      key: const ValueKey('skip-update-version'),
                      focusNode: focusNode,
                      contentPadding: EdgeInsets.zero,
                      visualDensity: const VisualDensity(vertical: -2),
                      minTileHeight: 40,
                      minLeadingWidth: Checkbox.width,
                      horizontalTitleGap: Spacing.sm,
                      leading: ExcludeFocus(
                        child: SizedBox(
                          width: Checkbox.width,
                          child: Checkbox(
                            value: controller.skipped,
                            onChanged: (value) => controller.setSkipVersion(value!),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
                          ),
                        ),
                      ),
                      title: const Text('Skip this version'),
                      onTap: () => controller.setSkipVersion(!controller.skipped),
                    ),
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
          ],
        ),
      ),
      actions: [
        if (!compact) TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Dismiss')),
        if (!controller.staged)
          FilledButton(
            key: const ValueKey('check-updates'),
            onPressed: controller.busy ? null : () => _performAction(context, controller),
            child: Text(controller.checking && _showCheckFeedback ? 'Checking…' : _presentation.action),
          ),
      ],
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
    UpdateStatus.handedOff when controller.channel == UpdateChannel.web => 'Reloading Papyrus',
    UpdateStatus.handedOff => 'Continue on your device',
    UpdateStatus.checkFailed => _checkFailedTitle,
    UpdateStatus.installFailed => 'Couldn’t finish the update',
  };

  String? _statusDetail(UpdateController controller) {
    if (controller.status == UpdateStatus.handedOff && controller.channel == UpdateChannel.web) {
      return null;
    }

    if (controller.status == UpdateStatus.installFailed) {
      return controller.message;
    }

    if (controller.status == UpdateStatus.checkFailed) {
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

    return controller.channel == UpdateChannel.apt ? 'Update Papyrus using your package manager.' : null;
  }

  String _actionLabel(UpdateController controller) {
    if (controller.checking) return 'Checking…';
    if (controller.busy) return 'Updating…';
    if (controller.status == UpdateStatus.checkFailed || controller.status == UpdateStatus.installFailed) {
      return 'Retry';
    }

    if (controller.available) {
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
    if (controller.status == UpdateStatus.checkFailed || !controller.available) {
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
