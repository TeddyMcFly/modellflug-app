import 'package:flutter_test/flutter_test.dart';
import 'package:modellflug_app/shared/utils/flight_time_input.dart';

void main() {
  test('parseFlightMinutesInput accepts minute and hour formats', () {
    expect(parseFlightMinutesInput(''), 0);
    expect(parseFlightMinutesInput('120'), 120);
    expect(parseFlightMinutesInput('120 min'), 120);
    expect(parseFlightMinutesInput('120 Minuten'), 120);
    expect(parseFlightMinutesInput('2 h'), 120);
    expect(parseFlightMinutesInput('2 H'), 120);
    expect(parseFlightMinutesInput('1,5 Stunden'), 90);
    expect(parseFlightMinutesInput('1 h 30 min'), 90);
  });

  test('formatFlightMinutesInput appends min for stored values', () {
    expect(formatFlightMinutesInput(0), '');
    expect(formatFlightMinutesInput(120), '120 min');
  });
}
