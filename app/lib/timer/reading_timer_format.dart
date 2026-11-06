String readingTimerClock(Duration duration) {
  final seconds = duration.inSeconds.clamp(0, 99999999);
  final minutes = (seconds ~/ 60 % 60).toString().padLeft(2, '0');
  final remainder = (seconds % 60).toString().padLeft(2, '0');
  return seconds >= 3600 ? '${seconds ~/ 3600}:$minutes:$remainder' : '$minutes:$remainder';
}
