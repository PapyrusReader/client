import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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
  static const _dismissDistance = 48.0;
  static const _dismissVelocity = 700.0;

  final _contentKey = GlobalKey();
  final _sheetController = DraggableScrollableController();
  ScrollController? _scrollController;
  AnimationController? _routeController;
  double? _contentHeight;
  double _minSize = 0;
  double _maxSize = 1;
  double _dragStartSize = 0;
  double _dragDistance = 0;
  bool _draggingFromHeader = false;
  bool _measurementScheduled = false;

  @override
  void dispose() {
    _sheetController.dispose();
    super.dispose();
  }

  void _resizeFromHeader(double size) {
    if (!_sheetController.isAttached) {
      return;
    }

    _sheetController.jumpTo(size.clamp(_minSize, _maxSize));
  }

  void _startHeaderDrag(AnimationController? routeController) {
    if (!_sheetController.isAttached || routeController?.status == AnimationStatus.reverse) {
      return;
    }

    _draggingFromHeader = true;
    _dragStartSize = _sheetController.size;
    _dragDistance = 0;
    _routeController = routeController;
    _routeController?.stop();
    _resizeFromHeader(_dragStartSize);
  }

  void _updateHeaderDrag(DragUpdateDetails details) {
    if (!_sheetController.isAttached || !_draggingFromHeader) {
      return;
    }

    var delta = details.primaryDelta ?? 0;
    _dragDistance += delta;
    final routeController = _routeController;
    final height = _sheetController.sizeToPixels(_sheetController.size);

    if (routeController != null && routeController.value < 1) {
      final previousValue = routeController.value;
      routeController.value -= delta / height;
      delta += (routeController.value - previousValue) * height;
    }

    final size = _sheetController.size;
    _resizeFromHeader(_sheetController.size - _sheetController.pixelsToSize(delta));
    final consumed = _sheetController.sizeToPixels(size - _sheetController.size);

    if (routeController != null && delta > consumed) {
      routeController.value -= (delta - consumed) / height;
    }
  }

  void _endHeaderDrag(DragEndDetails details, VoidCallback? onDismiss) {
    if (!_sheetController.isAttached || !_draggingFromHeader) {
      _restoreRoute();
      return;
    }

    final atMinimum = _sheetController.size <= _minSize + precisionErrorTolerance;
    final pulledDown = _dragDistance > 0 && (_dragStartSize > _minSize || _dragDistance >= _dismissDistance);

    if (widget.canClose &&
        onDismiss != null &&
        ((atMinimum && pulledDown) || (details.primaryVelocity ?? 0) > _dismissVelocity)) {
      onDismiss();
    }

    _restoreRoute();
  }

  void _restoreRoute() {
    final controller = _routeController;
    _draggingFromHeader = false;
    _routeController = null;

    if (mounted && controller != null && controller.status != AnimationStatus.reverse) {
      controller.forward();
    }
  }

  void _measureContent() {
    if (_measurementScheduled) {
      return;
    }

    _measurementScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementScheduled = false;

      if (!mounted) {
        return;
      }

      final box = _contentKey.currentContext?.findRenderObject();
      final controller = _scrollController;

      if (box is! RenderBox || !box.hasSize) {
        return;
      }

      final position = controller != null && controller.positions.length == 1 ? controller.position : null;

      if (position != null && !position.hasContentDimensions) {
        return;
      }

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
      _minSize = availableHeight < 400 ? initialSize : math.min(initialSize, .5);
      _maxSize = maxSize;
      _measureContent();

      return DraggableScrollableSheet(
        controller: _sheetController,
        expand: false,
        initialChildSize: initialSize,
        minChildSize: _minSize,
        maxChildSize: maxSize,
        // Content flings can reach the minimum too. Dismiss through the
        // header's deliberate drag gesture instead of scroll momentum.
        shouldCloseOnMinExtent: false,
        builder: (context, controller) {
          _scrollController = controller;

          return NotificationListener<ScrollMetricsNotification>(
            onNotification: (notification) {
              if (notification.depth == 0) {
                _measureContent();
              }

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
                    child: _SheetDragScope(
                      state: this,
                      child: SizedBox(key: _contentKey, child: widget.builder(context, controller)),
                    ),
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

/// Resizes from the header without consuming or resetting the body's scroll offset.
class BottomSheetDragRegion extends StatelessWidget {
  const BottomSheetDragRegion({super.key, required this.child, this.onDismiss});

  final Widget child;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final state = context.dependOnInheritedWidgetOfExactType<_SheetDragScope>()?.state;

    if (state == null) {
      return child;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      excludeFromSemantics: true,
      onVerticalDragStart: (_) => state._startHeaderDrag(
        onDismiss == null ? null : context.findAncestorWidgetOfExactType<BottomSheet>()?.animationController,
      ),
      onVerticalDragUpdate: state._updateHeaderDrag,
      onVerticalDragEnd: (details) => state._endHeaderDrag(details, onDismiss),
      onVerticalDragCancel: state._restoreRoute,
      child: child,
    );
  }
}

class _SheetDragScope extends InheritedWidget {
  const _SheetDragScope({required this.state, required super.child});

  final _ExpandableBottomSheetState state;

  @override
  bool updateShouldNotify(_SheetDragScope oldWidget) => state != oldWidget.state;
}
