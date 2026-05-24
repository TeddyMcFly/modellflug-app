import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modellflug_app/shared/models/aircraft_model.dart';
import 'package:modellflug_app/shared/providers/fleet_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('addFlight increments selected battery cycles', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final initialBattery = container
        .read(fleetProvider)
        .batteries
        .firstWhere((battery) => battery.id == 'akku-6s-5000-a');
    final flightDate = DateTime(2026, 5, 24, 12, 30);

    container.read(fleetProvider.notifier).addFlight(
          FlightLogEntry(
            id: 'test-flight',
            aircraftId: 'extra300',
            date: flightDate,
            location: 'Testplatz',
            durationMinutes: 8,
            batteryPacks: 1,
            pilot: 'Test',
            notes: 'Testflug',
          ),
          usedBatteryId: initialBattery.id,
        );

    final updatedBattery = container
        .read(fleetProvider)
        .batteries
        .firstWhere((battery) => battery.id == initialBattery.id);

    expect(updatedBattery.cycles, initialBattery.cycles + 1);
    expect(updatedBattery.lastUsed, flightDate);
  });
}
