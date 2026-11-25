import 'package:flutter/material.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/themes/design_tokens.dart';

class CollectionGridTitle extends StatefulWidget {
  const CollectionGridTitle({super.key, required this.title, this.style, this.focused = false});

  final String title;
  final TextStyle? style;
  final bool focused;

  @override
  State<CollectionGridTitle> createState() => _CollectionGridTitleState();
}

class _CollectionGridTitleState extends State<CollectionGridTitle> {
  static final _issueSuffix = RegExp(r'\s+(#\d+)\s*$');
  var _tooltipKey = GlobalKey<TooltipState>();
  var _instantTooltipKey = GlobalKey<RawTooltipState>();

  @override
  void didUpdateWidget(covariant CollectionGridTitle oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.focused == widget.focused) {
      return;
    }

    if (!widget.focused) {
      _tooltipKey = GlobalKey<TooltipState>();
      _instantTooltipKey = GlobalKey<RawTooltipState>();
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.focused) {
        _tooltipKey.currentState?.ensureTooltipVisible();
        _instantTooltipKey.currentState?.ensureTooltipVisible();
      }
    });
  }

  String? _shortenIssueTitle(TextPainter painter, TextStyle style, double width, RegExpMatch issue) {
    final suffix = '… ${issue.group(1)}';
    final prefix = widget.title.substring(0, issue.start).characters;
    String labelWithPrefix(int length) => '${prefix.take(length).toString().trimRight()}$suffix';

    bool fits(String label) {
      painter.text = TextSpan(text: label, style: style);
      painter.layout(maxWidth: width);
      return !painter.didExceedMaxLines;
    }

    if (!fits(suffix)) {
      return null;
    }

    var low = 0;
    var high = prefix.length;

    while (low < high) {
      final length = (low + high + 1) ~/ 2;

      if (fits(labelWithPrefix(length))) {
        low = length;
      } else {
        high = length - 1;
      }
    }

    return labelWithPrefix(low);
  }

  @override
  Widget build(BuildContext context) {
    final suffixMatch = _issueSuffix.firstMatch(widget.title);

    return LayoutBuilder(
      builder: (context, constraints) {
        var style = DefaultTextStyle.of(context).style.merge(widget.style);

        if (MediaQuery.boldTextOf(context)) {
          style = style.merge(const TextStyle(fontWeight: FontWeight.bold));
        }

        final painter = TextPainter(
          text: TextSpan(text: widget.title, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: constraints.maxWidth);

        final truncated = painter.didExceedMaxLines;
        final shortened = truncated && suffixMatch != null
            ? _shortenIssueTitle(painter, style, constraints.maxWidth, suffixMatch)
            : null;

        painter.dispose();

        final label = Text(
          shortened ?? widget.title,
          semanticsLabel: shortened == null ? null : widget.title,
          style: widget.style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );

        if (truncated) {
          if (AppMotion.disabled(context) && TooltipVisibility.of(context)) {
            final theme = Theme.of(context);
            final colors = theme.colorScheme;

            return RawTooltip(
              key: _instantTooltipKey,
              semanticsTooltip: null,
              triggerMode: TooltipTriggerMode.manual,
              animationStyle: AnimationStyle.noAnimation,
              dismissDelay: Duration.zero,
              tooltipBuilder: (context, animation) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
                child: Material(
                  color: colors.inverseSurface,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xs),
                    child: Text(
                      widget.title,
                      style: theme.textTheme.bodySmall?.copyWith(color: colors.onInverseSurface),
                    ),
                  ),
                ),
              ),
              child: label,
            );
          }

          return Tooltip(
            key: _tooltipKey,
            message: widget.title,
            triggerMode: TooltipTriggerMode.manual,
            excludeFromSemantics: true,
            child: label,
          );
        }

        return label;
      },
    );
  }
}
