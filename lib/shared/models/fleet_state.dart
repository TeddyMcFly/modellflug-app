import 'aircraft_model.dart';

enum FleetSyncStatus {
  localOnly,
  syncing,
  cloudActive,
  cloudPaused,
}

class FleetState {
  final List<AircraftModel> aircraft;
  final List<FlightLogEntry> flights;
  final List<BatteryPack> batteries;
  final PilotProfile pilotProfile;
  final AppSettings appSettings;
  final bool isLoaded;
  final FleetSyncStatus syncStatus;

  const FleetState({
    required this.aircraft,
    required this.flights,
    required this.batteries,
    required this.pilotProfile,
    required this.appSettings,
    this.isLoaded = false,
    this.syncStatus = FleetSyncStatus.localOnly,
  });

  int get readyCount =>
      aircraft.where((item) => item.status == AircraftStatus.ready).length;

  int get serviceDueCount => aircraft
      .where((item) => item.nextService.isBefore(DateTime.now()))
      .length;

  int get chargedBatteryCount =>
      batteries.where((item) => item.status == BatteryStatus.charged).length;

  int get totalFlights => flights.length;

  int get totalMinutes =>
      flights.fold(0, (sum, item) => sum + item.durationMinutes) +
      aircraft.fold(
        0,
        (sum, item) =>
            sum +
            (item.previousFlightMinutes < 0 ? 0 : item.previousFlightMinutes),
      );

  double get totalHours => totalMinutes / 60;

  int get nextBatteryInventoryNumber {
    if (batteries.isEmpty) {
      return 1;
    }
    return batteries
            .map((item) => item.inventoryNumber)
            .where((number) => number > 0)
            .fold<int>(0, (max, number) => number > max ? number : max) +
        1;
  }

  FleetState copyWith({
    List<AircraftModel>? aircraft,
    List<FlightLogEntry>? flights,
    List<BatteryPack>? batteries,
    PilotProfile? pilotProfile,
    AppSettings? appSettings,
    bool? isLoaded,
    FleetSyncStatus? syncStatus,
  }) {
    return FleetState(
      aircraft: aircraft ?? this.aircraft,
      flights: flights ?? this.flights,
      batteries: batteries ?? this.batteries,
      pilotProfile: pilotProfile ?? this.pilotProfile,
      appSettings: appSettings ?? this.appSettings,
      isLoaded: isLoaded ?? this.isLoaded,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  factory FleetState.fromJson(Map<String, dynamic> json) {
    return FleetState(
      aircraft: [
        for (final item in json['aircraft'] as List<dynamic>)
          AircraftModel.fromJson(item as Map<String, dynamic>),
      ],
      flights: [
        for (final item in json['flights'] as List<dynamic>)
          FlightLogEntry.fromJson(item as Map<String, dynamic>),
      ],
      batteries: _normalizeBatteryInventoryNumbers([
        for (final item in json['batteries'] as List<dynamic>? ?? [])
          BatteryPack.fromJson(item as Map<String, dynamic>),
      ]),
      pilotProfile: PilotProfile.fromJson(
        json['pilotProfile'] as Map<String, dynamic>? ?? const {},
      ),
      appSettings: AppSettings.fromJson(
        json['appSettings'] as Map<String, dynamic>? ?? const {},
      ),
      isLoaded: true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'aircraft': [for (final item in aircraft) item.toJson()],
      'flights': [for (final item in flights) item.toJson()],
      'batteries': [for (final item in batteries) item.toJson()],
      'pilotProfile': pilotProfile.toJson(),
      'appSettings': appSettings.toJson(),
    };
  }
}

List<BatteryPack> _normalizeBatteryInventoryNumbers(
  List<BatteryPack> batteries,
) {
  final usedNumbers = {
    for (final battery in batteries)
      if (battery.inventoryNumber > 0) battery.inventoryNumber,
  };
  var nextNumber = 1;

  return [
    for (final battery in batteries)
      if (battery.inventoryNumber > 0)
        battery
      else
        battery.copyWith(
          inventoryNumber: () {
            while (usedNumbers.contains(nextNumber)) {
              nextNumber++;
            }
            usedNumbers.add(nextNumber);
            return nextNumber++;
          }(),
        ),
  ];
}
