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

  test('deleteFlight removes entry and restores totals', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final initialState = container.read(fleetProvider);
    final aircraft = initialState.aircraft.first;
    final battery = initialState.batteries.first;
    final flightDate = DateTime(2026, 5, 27, 16, 45);
    final entry = FlightLogEntry(
      id: 'delete-test-flight',
      aircraftId: aircraft.id,
      date: flightDate,
      location: 'Testplatz',
      durationMinutes: 15,
      batteryPacks: 1,
      batteryId: battery.id,
      batteryLabel: battery.label,
      pilot: 'Test',
      notes: 'Wird wieder geloescht',
    );

    container.read(fleetProvider.notifier).addFlight(entry);
    container.read(fleetProvider.notifier).deleteFlight(entry.id);

    final updatedState = container.read(fleetProvider);
    final restoredAircraft = updatedState.aircraft.firstWhere(
      (item) => item.id == aircraft.id,
    );
    final restoredBattery = updatedState.batteries.firstWhere(
      (item) => item.id == battery.id,
    );

    expect(
        updatedState.flights.any((flight) => flight.id == entry.id), isFalse);
    expect(restoredAircraft.totalFlights, aircraft.totalFlights);
    expect(restoredAircraft.flightHours, closeTo(aircraft.flightHours, 0.0001));
    expect(restoredBattery.cycles, battery.cycles);
  });

  test('battery photo fields survive json round trip', () {
    const photoDataUri = 'data:image/jpeg;base64,akku-foto';
    const thumbnailDataUri = 'data:image/jpeg;base64,akku-vorschau';
    const downloadUrl = 'https://example.com/akku.jpg';
    final battery = BatteryPack(
      id: 'test-akku',
      inventoryNumber: 9,
      label: 'Testakku',
      chemistry: 'LiPo',
      cells: 4,
      capacityMah: 2200,
      chargePercent: 45,
      cycles: 3,
      status: BatteryStatus.storage,
      purchaseDate: DateTime(2026, 5, 25),
      lastUsed: DateTime(2026, 5, 25),
      assignedAircraftId: '',
      notes: 'Test',
      photoDataUri: photoDataUri,
      photoThumbnailDataUri: thumbnailDataUri,
      photoStoragePath: 'users/test/batteries/test-akku/photo/battery.jpg',
      photoDownloadUrl: downloadUrl,
    );

    final restored = BatteryPack.fromJson(battery.toJson());

    expect(restored.photoDataUri, photoDataUri);
    expect(restored.photoThumbnailDataUri, thumbnailDataUri);
    expect(restored.photoStoragePath, battery.photoStoragePath);
    expect(restored.photoDownloadUrl, downloadUrl);
    expect(restored.photoSource, downloadUrl);
    expect(restored.photoPreviewSource, thumbnailDataUri);
  });

  test('previous model flight minutes are stored and counted', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final initialState = container.read(fleetProvider);
    final initialAircraft = initialState.aircraft.first;
    final initialTotalMinutes = initialState.totalMinutes;
    final changedAircraft =
        initialAircraft.copyWith(previousFlightMinutes: 120);

    container.read(fleetProvider.notifier).updateAircraft(changedAircraft);

    final updatedState = container.read(fleetProvider);
    final restoredAircraft = AircraftModel.fromJson(
      changedAircraft.toJson(),
    );

    expect(restoredAircraft.previousFlightMinutes, 120);
    expect(
      restoredAircraft.totalFlightMinutes,
      restoredAircraft.loggedFlightMinutes + 120,
    );
    expect(
      updatedState.totalMinutes,
      initialTotalMinutes - initialAircraft.previousFlightMinutes + 120,
    );
  });

  test('saving aircraft syncs multiple selected batteries', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final initialState = container.read(fleetProvider);
    final selectedBatteries =
        initialState.batteries.where((battery) => battery.cells == 6).toList();
    expect(selectedBatteries.length, greaterThanOrEqualTo(2));

    final aircraft = initialState.aircraft.first.copyWith(
      id: 'test-aircraft',
      name: 'Testmodell',
      batteryCount: 6,
      batteryCellOptions: const [6],
    );

    container.read(fleetProvider.notifier).saveAircraftWithBatteryAssignment(
      aircraft,
      selectedBatteryIds: [
        selectedBatteries[0].id,
        selectedBatteries[1].id,
      ],
    );

    var updatedState = container.read(fleetProvider);
    expect(updatedState.aircraft.any((item) => item.id == aircraft.id), isTrue);
    expect(
      updatedState.batteries
          .where((battery) =>
              battery.id == selectedBatteries[0].id ||
              battery.id == selectedBatteries[1].id)
          .every((battery) => battery.aircraftIds.contains(aircraft.id)),
      isTrue,
    );

    container.read(fleetProvider.notifier).saveAircraftWithBatteryAssignment(
      aircraft,
      selectedBatteryIds: [selectedBatteries[0].id],
    );

    updatedState = container.read(fleetProvider);
    final keptBattery = updatedState.batteries.firstWhere(
      (item) => item.id == selectedBatteries[0].id,
    );
    final uncheckedBattery = updatedState.batteries.firstWhere(
      (item) => item.id == selectedBatteries[1].id,
    );

    expect(keptBattery.aircraftIds, contains(aircraft.id));
    expect(uncheckedBattery.aircraftIds, isNot(contains(aircraft.id)));
    expect(
      updatedState.batteries
          .where((item) => item.cells != 6)
          .any((item) => item.aircraftIds.contains(aircraft.id)),
      isFalse,
    );
  });
}
