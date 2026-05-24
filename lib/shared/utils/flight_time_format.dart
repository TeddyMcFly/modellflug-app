String formatFlightHours(double hours) {
  return formatFlightMinutes((hours * 60).round());
}

String formatFlightMinutes(int totalMinutes) {
  final safeMinutes = totalMinutes < 0 ? 0 : totalMinutes;
  final hours = safeMinutes ~/ 60;
  final minutes = safeMinutes.remainder(60);
  return '$hours h $minutes min';
}
