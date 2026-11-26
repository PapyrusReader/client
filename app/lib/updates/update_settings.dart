import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/updates/update_dialog.dart';
import 'package:papyrus/updates/update_controller.dart';

Future<void> showUpdateSettings(BuildContext context, UpdateController controller) async {
  if (!controller.supported || controller.viewingSettings) {
    return;
  }

  controller.setViewingSettings(true);

  try {
    await controller.initialize();

    if (!context.mounted || !controller.supported) {
      return;
    }

    await showDialog<void>(
      context: context,
      animationStyle: AppMotion.animationStyle(context),
      builder: (_) => UpdateDialog(controller: controller),
    );
    controller.dismissNotice();
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
  Future<void> _viewUpdate() async {
    final context = widget.router.routerDelegate.navigatorKey.currentContext;

    if (context != null) {
      await showUpdateSettings(context, widget.controller);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.controller, widget.router.routeInformationProvider]),
      builder: (context, child) {
        final reading = widget.router.routeInformationProvider.value.uri.path.contains('/read/');
        final visible = widget.controller.showNotice && !reading;

        return Column(
          children: [
            if (visible)
              SafeArea(
                bottom: false,
                child: LayoutBuilder(
                  builder: (context, constraints) => MaterialBanner(
                    content: Text(
                      widget.controller.staged ? 'Restart to finish updating' : 'Update available',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    actions: [
                      // Keep one action group so MaterialBanner uses its single-row layout.
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.65),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: TextButton(
                                onPressed: _viewUpdate,
                                child: const Text('View update', maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                            ),
                            if (constraints.maxWidth < Breakpoints.tablet)
                              IconButton(
                                key: const ValueKey('dismiss-update-notice'),
                                onPressed: widget.controller.dismissNotice,
                                icon: const Icon(Icons.close, semanticLabel: 'Dismiss update notification'),
                              )
                            else
                              TextButton(
                                key: const ValueKey('dismiss-update-notice'),
                                onPressed: widget.controller.dismissNotice,
                                child: const Text('Dismiss'),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: visible,
                child: widget.child,
              ),
            ),
          ],
        );
      },
    );
  }
}
