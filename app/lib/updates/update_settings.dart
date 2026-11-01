import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/services/about_links.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/updates/update_controller.dart';
import 'package:papyrus/updates/update_release.dart';
import 'package:papyrus/widgets/settings/settings_row.dart';

Future<void> showUpdateSettings(BuildContext context, UpdateController controller) async {
  if (controller.viewingSettings) {
    return;
  }

  controller.setViewingSettings(true);

  try {
    await showDialog<void>(
      context: context,
      animationStyle: AppMotion.animationStyle(context),
      builder: (context) => ListenableBuilder(
        listenable: controller,
        builder: (context, child) => AlertDialog(
          title: const Text('App updates'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(controller.message),
                  const SizedBox(height: Spacing.md),
                  SettingsToggleRow(
                    label: 'Check automatically',
                    value: controller.automatic,
                    onChanged: controller.setAutomatic,
                  ),
                  if (controller.channel == UpdateChannel.apt) ...[
                    const SizedBox(height: Spacing.md),
                    const Text(
                      'Install updates through your system’s software updater. Enable the Papyrus repository once to receive future releases.',
                    ),
                    TextButton(
                      onPressed: () => AboutLinks.open(
                        context,
                        Uri.https('github.com', '/PapyrusReader/client/blob/master/docs/INSTALL.md'),
                      ),
                      child: const Text('Repository setup'),
                    ),
                  ],
                  if (controller.channel == UpdateChannel.manual) ...[
                    const SizedBox(height: Spacing.md),
                    const Text(
                      'This portable or development build uses manual installation. Install a supported package to receive integrated updates.',
                    ),
                    TextButton(
                      onPressed: () => AboutLinks.open(context, AboutLinks.releases),
                      child: const Text('Downloads'),
                    ),
                  ],
                  if (controller.available && !controller.external && !controller.staged) ...[
                    const SizedBox(height: Spacing.md),
                    Text(switch (controller.channel) {
                      UpdateChannel.windows => 'The update will install after you close Papyrus normally.',
                      UpdateChannel.appImage => 'The update takes effect when you close and reopen Papyrus.',
                      UpdateChannel.web => 'Reload when you have finished reading to use the latest version.',
                      _ => 'Your device will guide you through installation.',
                    }),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
            TextButton(
              onPressed: controller.busy || controller.staged ? null : controller.check,
              child: const Text('Check now'),
            ),
            if (controller.available && !controller.external && !controller.staged)
              FilledButton(
                onPressed: controller.busy ? null : controller.install,
                child: Text(controller.channel == UpdateChannel.web ? 'Reload' : 'Update'),
              ),
          ],
        ),
      ),
    );
  } finally {
    controller.setViewingSettings(false);
  }
}

class UpdateNotice extends StatefulWidget {
  final UpdateController controller;
  final GoRouter router;
  final Widget child;

  const UpdateNotice({super.key, required this.controller, required this.router, required this.child});

  @override
  State<UpdateNotice> createState() => _UpdateNoticeState();
}

class _UpdateNoticeState extends State<UpdateNotice> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.controller, widget.router.routeInformationProvider]),
      builder: (context, child) {
        final reading = widget.router.routeInformationProvider.value.uri.path.contains('/read/');
        final visible =
            widget.controller.available &&
            !widget.controller.staged &&
            !widget.controller.viewingSettings &&
            !_dismissed &&
            !reading;

        return Column(
          children: [
            if (visible)
              SafeArea(
                bottom: false,
                child: MaterialBanner(
                  content: const Text('A Papyrus update is available.'),
                  actions: [
                    TextButton(onPressed: () => setState(() => _dismissed = true), child: const Text('Later')),
                    TextButton(
                      onPressed: () => showUpdateSettings(
                        widget.router.routerDelegate.navigatorKey.currentContext!,
                        widget.controller,
                      ),
                      child: const Text('View update'),
                    ),
                  ],
                ),
              ),
            Expanded(child: widget.child),
          ],
        );
      },
    );
  }
}
