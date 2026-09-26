/// Preferred cover width, in logical pixels. The grid adapts to available space.
abstract final class BookGridSize {
  static const double minimum = 120;
  static const double maximum = 320;
  static const double step = 20;
  static const double defaultWidth = 160;

  static double normalize(double width) {
    if (!width.isFinite) return defaultWidth;
    return (minimum + ((width - minimum) / step).round() * step).clamp(minimum, maximum);
  }
}
