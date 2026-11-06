import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:papyrus/themes/design_tokens.dart';

/// Equal-height panels whose contents may use LayoutBuilder or scroll views.
/// Measure real layouts instead of requesting unsupported intrinsic dimensions.
class StatisticsRow extends MultiChildRenderObjectWidget {
  StatisticsRow({super.key, required Widget main, required Widget aside}) : super(children: [main, aside]);

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderStatisticsRow(Directionality.of(context));

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) {
    (renderObject as _RenderStatisticsRow).textDirection = Directionality.of(context);
  }
}

class _StatisticsParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderStatisticsRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _StatisticsParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _StatisticsParentData> {
  _RenderStatisticsRow(this._textDirection);

  TextDirection _textDirection;

  set textDirection(TextDirection value) {
    if (value != _textDirection) {
      _textDirection = value;
      markNeedsLayout();
    }
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _StatisticsParentData) {
      child.parentData = _StatisticsParentData();
    }
  }

  @override
  void performLayout() {
    final main = firstChild!;
    final aside = lastChild!;
    final available = constraints.maxWidth - Spacing.lg;
    final mainWidth = available * 5 / 8;
    final asideWidth = available - mainWidth;
    main.layout(BoxConstraints.tightFor(width: mainWidth), parentUsesSize: true);
    aside.layout(BoxConstraints.tightFor(width: asideWidth), parentUsesSize: true);
    final height = math.max(main.size.height, aside.size.height);
    // A minimum height keeps content changes bubbling up during expansion.
    // Tight height constraints would make each panel a separate layout boundary.
    main.layout(BoxConstraints(minWidth: mainWidth, maxWidth: mainWidth, minHeight: height), parentUsesSize: true);
    aside.layout(BoxConstraints(minWidth: asideWidth, maxWidth: asideWidth, minHeight: height), parentUsesSize: true);
    final mainData = main.parentData! as ContainerBoxParentData<RenderBox>;
    final asideData = aside.parentData! as ContainerBoxParentData<RenderBox>;
    mainData.offset = Offset(_textDirection == TextDirection.ltr ? 0 : asideWidth + Spacing.lg, 0);
    asideData.offset = Offset(_textDirection == TextDirection.ltr ? mainWidth + Spacing.lg : 0, 0);
    size = constraints.constrain(Size(constraints.maxWidth, height));
  }

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
