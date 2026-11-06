import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/timer/reading_timer_format.dart';

/// A determinate reading clock: remaining fraction, or seconds within a minute.
class ReadingTimerClock extends StatelessWidget {
  const ReadingTimerClock({
    super.key,
    required this.time,
    required this.progress,
    required this.countdown,
    required this.status,
    this.digitSize = 64,
  });

  final Duration time;
  final double progress;
  final bool countdown;
  final String status;
  final double digitSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clock = readingTimerClock(time);

    final largeText = MediaQuery.textScalerOf(context).scale(16) > 22;
    final label = Text(
      countdown ? 'Time remaining' : 'Time elapsed',
      textAlign: TextAlign.center,
      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
    );

    final digitStyle = theme.textTheme.displayLarge?.copyWith(
      fontSize: digitSize,
      fontWeight: FontWeight.w300,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final digits = SizedBox(
      width: double.infinity,
      height: MediaQuery.textScalerOf(context).scale(digitSize) * (digitStyle?.height ?? 1),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(clock, style: digitStyle),
      ),
    );

    final state = Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xs),
      decoration: ShapeDecoration(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Text(status, textAlign: TextAlign.center, style: theme.textTheme.labelLarge),
    );

    final ring = AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: _ClockRing(
          progress: progress,
          color: theme.colorScheme.primary,
          track: Color.alphaBlend(theme.colorScheme.onSurface.withValues(alpha: 0.18), theme.colorScheme.surface),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: largeText
              ? Center(child: digits)
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    label,
                    const SizedBox(height: Spacing.sm),
                    Flexible(child: digits),
                    const SizedBox(height: Spacing.sm),
                    state,
                  ],
                ),
        ),
      ),
    );

    return Semantics(
      label: '${countdown ? 'Time remaining' : 'Time elapsed'}: $clock. $status',
      child: ExcludeSemantics(
        child: largeText
            ? Column(
                children: [
                  label,
                  const SizedBox(height: Spacing.sm),
                  ring,
                  const SizedBox(height: Spacing.sm),
                  state,
                ],
              )
            : ring,
      ),
    );
  }
}

class _ClockRing extends CustomPainter {
  const _ClockRing({required this.progress, required this.color, required this.track});

  final double progress;
  final Color color;
  final Color track;
  static const double _strokeWidth = 28;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - _strokeWidth / 2 - 2;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = track;

    canvas.drawCircle(center, radius, paint);

    if (progress > 0) {
      paint.color = color;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        paint,
      );
    } else {
      canvas.drawCircle(Offset(center.dx, center.dy - radius), _strokeWidth / 2, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_ClockRing oldDelegate) =>
      progress != oldDelegate.progress || color != oldDelegate.color || track != oldDelegate.track;
}
