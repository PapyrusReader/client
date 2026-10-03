import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Coordinates mobile sheet expansion with its primary content scroll view.
/// The sheet grows only as far as its content needs, then scrolls normally.
class ExpandableBottomSheet extends StatefulWidget {
  const ExpandableBottomSheet({super.key, required this.builder, this.canClose = true});

  final Widget Function(BuildContext context, ScrollController controller) builder;
  final bool canClose;

  @override
  State<ExpandableBottomSheet> createState() => _ExpandableBottomSheetState();
}

class _ExpandableBottomSheetState extends State<ExpandableBottomSheet> {
  final _contentKey = GlobalKey();
  ScrollController? _scrollController;
  double? _contentHeight;
  bool _measurementScheduled = false;

  void _measureContent() {
    if (_measurementScheduled) return;
    _measurementScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementScheduled = false;
      if (!mounted) return;
      final box = _contentKey.currentContext?.findRenderObject();
      final controller = _scrollController;
      if (box is! RenderBox || !box.hasSize) return;
      final position = controller != null && controller.positions.length == 1 ? controller.position : null;
      if (position != null && !position.hasContentDimensions) return;
      final height = box.size.height + math.max(0, position?.maxScrollExtent ?? 0);
      if (_contentHeight == null || (height - _contentHeight!).abs() > 1) {
        setState(() => _contentHeight = height);
      }
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final availableHeight = constraints.maxHeight;
      final maxSize = ((_contentHeight ?? availableHeight) / availableHeight).clamp(0.01, 1.0);
      // When the keyboard leaves little room, use all of the available height.
      final initialSize = math.min(availableHeight < 400 ? 1.0 : .8, maxSize);
      _measureContent();
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: initialSize,
        minChildSize: availableHeight < 400 ? initialSize : math.min(initialSize, .5),
        maxChildSize: maxSize,
        shouldCloseOnMinExtent: widget.canClose,
        builder: (context, controller) {
          _scrollController = controller;
          return NotificationListener<ScrollMetricsNotification>(
            onNotification: (notification) {
              if (notification.depth == 0) _measureContent();
              return false;
            },
            child: NotificationListener<SizeChangedLayoutNotification>(
              onNotification: (_) {
                _measureContent();
                return false;
              },
              child: PrimaryScrollController(
                controller: controller,
                automaticallyInheritForPlatforms: TargetPlatform.values.toSet(),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  heightFactor: 1,
                  child: SizeChangedLayoutNotifier(
                    child: SizedBox(key: _contentKey, child: widget.builder(context, controller)),
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
