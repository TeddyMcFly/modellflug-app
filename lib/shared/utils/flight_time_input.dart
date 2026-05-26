int parseFlightMinutesInput(String value) {
  var normalized = value.trim().toLowerCase();
  if (normalized.isEmpty) {
    return 0;
  }
  normalized = normalized
      .replaceAll(',', '.')
      .replaceAll('stunden', 'h')
      .replaceAll('stunde', 'h')
      .replaceAll('minuten', 'min')
      .replaceAll('minute', 'min');

  final plainNumber = double.tryParse(normalized);
  if (plainNumber != null) {
    if (plainNumber < 0) {
      throw const FormatException('negative flight time');
    }
    return plainNumber.round();
  }

  var totalMinutes = 0.0;
  var foundUnit = false;
  final hourMatches =
      RegExp(r'([0-9]+(?:\.[0-9]+)?)\s*h').allMatches(normalized);
  for (final match in hourMatches) {
    final hours = double.tryParse(match.group(1)!);
    if (hours != null) {
      totalMinutes += hours * 60;
      foundUnit = true;
    }
  }

  final minuteMatches =
      RegExp(r'([0-9]+(?:\.[0-9]+)?)\s*min').allMatches(normalized);
  for (final match in minuteMatches) {
    final minutes = double.tryParse(match.group(1)!);
    if (minutes != null) {
      totalMinutes += minutes;
      foundUnit = true;
    }
  }

  if (!foundUnit || totalMinutes < 0) {
    throw const FormatException('invalid flight time');
  }

  return totalMinutes.round();
}

String formatFlightMinutesInput(int minutes) {
  return minutes <= 0 ? '' : '$minutes min';
}
