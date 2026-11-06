import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/pages/app_updates_page.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/updates/update_controller.dart';
import 'package:papyrus/updates/update_release.dart';

Future<void> showUpdateSettings(BuildContext context, UpdateController controller) async {
  if (controller.viewingSettings) {
    return;
  }

  controller.setViewingSettings(true);

  try {
    final page = AppUpdatesPage(controller: controller);

    await Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => page,
      ),
    );
  } finally {
    controller.setViewingSettings(false);
  }
}

Future<bool> showUpdatePrompt(BuildContext context, UpdateController controller) async {
  if (controller.viewingSettings) {
    return false;
  }

  controller.setViewingSettings(true);

  try {
    return await showDialog<bool>(
          context: context,
          animationStyle: AppMotion.animationStyle(context),
          builder: (context) => ListenableBuilder(
            listenable: controller,
            builder: (context, child) => AlertDialog(
              title: const Text('App update'),
              content: Text(controller.message),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Later')),
                FilledButton(
                  onPressed: controller.busy || controller.staged ? null : controller.install,
                  child: Text(controller.channel == UpdateChannel.web ? 'Reload' : 'Update'),
                ),
              ],
            ),
          ),
        ) ??
        false;
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

  Future<void> _viewUpdate() async {
    final context = widget.router.routerDelegate.navigatorKey.currentContext!;

    if (widget.controller.external) {
      await showUpdateSettings(context, widget.controller);

      if (mounted) {
        setState(() => _dismissed = true);
      }

      return;
    }

    final dismissed = await showUpdatePrompt(context, widget.controller);

    if (mounted && dismissed) {
      setState(() => _dismissed = true);
    }
  }

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
                  content: const Text('Update available'),
                  actions: [
                    TextButton(
                      onPressed: _viewUpdate,
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
