import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/aircraft_model.dart';

final fleetProvider =
    StateNotifierProvider<FleetNotifier, FleetState>((ref) => FleetNotifier());

class FleetState {
  final List<AircraftModel> aircraft;
  final List<FlightLogEntry> flights;
  final List<BatteryPack> batteries;
  final PilotProfile pilotProfile;
  final AppSettings appSettings;

  const FleetState({
    required this.aircraft,
    required this.flights,
    required this.batteries,
    required this.pilotProfile,
    required this.appSettings,
  });

  int get readyCount =>
      aircraft.where((item) => item.status == AircraftStatus.ready).length;

  int get serviceDueCount => aircraft
      .where((item) => item.nextService.isBefore(DateTime.now()))
      .length;

  int get chargedBatteryCount =>
      batteries.where((item) => item.status == BatteryStatus.charged).length;

  int get totalFlights =>
      aircraft.fold(0, (sum, item) => sum + item.totalFlights);

  double get totalHours =>
      aircraft.fold(0, (sum, item) => sum + item.flightHours);

  FleetState copyWith({
    List<AircraftModel>? aircraft,
    List<FlightLogEntry>? flights,
    List<BatteryPack>? batteries,
    PilotProfile? pilotProfile,
    AppSettings? appSettings,
  }) {
    return FleetState(
      aircraft: aircraft ?? this.aircraft,
      flights: flights ?? this.flights,
      batteries: batteries ?? this.batteries,
      pilotProfile: pilotProfile ?? this.pilotProfile,
      appSettings: appSettings ?? this.appSettings,
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
      batteries: [
        for (final item in json['batteries'] as List<dynamic>? ?? [])
          BatteryPack.fromJson(item as Map<String, dynamic>),
      ],
      pilotProfile: PilotProfile.fromJson(
        json['pilotProfile'] as Map<String, dynamic>? ?? const {},
      ),
      appSettings: AppSettings.fromJson(
        json['appSettings'] as Map<String, dynamic>? ?? const {},
      ),
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

class FleetNotifier extends StateNotifier<FleetState> {
  FleetNotifier() : super(_initialState) {
    _load();
  }

  static const _storageKey = 'modellflug_fleet_state';

  void addAircraft(AircraftModel aircraft) {
    state = state.copyWith(aircraft: [aircraft, ...state.aircraft]);
    _save();
  }

  void updateAircraft(AircraftModel aircraft) {
    state = state.copyWith(
      aircraft: [
        for (final item in state.aircraft)
          if (item.id == aircraft.id) aircraft else item,
      ],
    );
    _save();
  }

  void deleteAircraft(String id) {
    state = state.copyWith(
      aircraft: [
        for (final item in state.aircraft)
          if (item.id != id) item,
      ],
      flights: [
        for (final item in state.flights)
          if (item.aircraftId != id) item,
      ],
      batteries: [
        for (final item in state.batteries)
          if (item.assignedAircraftId == id)
            item.copyWith(assignedAircraftId: '')
          else
            item,
      ],
    );
    _save();
  }

  void updateStatus(String id, AircraftStatus status) {
    state = state.copyWith(
      aircraft: [
        for (final item in state.aircraft)
          if (item.id == id) item.copyWith(status: status) else item,
      ],
    );
    _save();
  }

  void addBattery(BatteryPack battery) {
    state = state.copyWith(batteries: [battery, ...state.batteries]);
    _save();
  }

  void updateBatteryStatus(String id, BatteryStatus status) {
    state = state.copyWith(
      batteries: [
        for (final item in state.batteries)
          if (item.id == id) item.copyWith(status: status) else item,
      ],
    );
    _save();
  }

  void updatePilotProfile(PilotProfile profile) {
    state = state.copyWith(pilotProfile: profile);
    _save();
  }

  void updateLocationSharing(bool enabled) {
    state = state.copyWith(
      appSettings: state.appSettings.copyWith(
        shareLocationWithFriends: enabled,
        presenceStatus: enabled
            ? _determinePresenceStatus(state.flights)
            : LocationPresenceStatus.offline,
      ),
    );
    _save();
  }

  void updateChatReachability(bool enabled) {
    state = state.copyWith(
      appSettings: state.appSettings.copyWith(reachableByChat: enabled),
    );
    _save();
  }

  void addFlight(FlightLogEntry entry) {
    final updatedAircraft = [
      for (final item in state.aircraft)
        if (item.id == entry.aircraftId)
          item.copyWith(
            totalFlights: item.totalFlights + 1,
            flightHours: item.flightHours + entry.durationMinutes / 60,
          )
        else
          item,
    ];

    state = state.copyWith(
      aircraft: updatedAircraft,
      flights: [entry, ...state.flights],
    );
    _save();
  }

  void updateFlight(FlightLogEntry entry) {
    final previous = state.flights.cast<FlightLogEntry?>().firstWhere(
          (item) => item?.id == entry.id,
          orElse: () => null,
        );

    var updatedAircraft = state.aircraft;
    if (previous != null) {
      updatedAircraft = [
        for (final item in state.aircraft)
          if (item.id == previous.aircraftId)
            item.copyWith(
              totalFlights: item.totalFlights - 1,
              flightHours: item.flightHours - previous.durationMinutes / 60,
            )
          else
            item,
      ];
      updatedAircraft = [
        for (final item in updatedAircraft)
          if (item.id == entry.aircraftId)
            item.copyWith(
              totalFlights: item.totalFlights + 1,
              flightHours: item.flightHours + entry.durationMinutes / 60,
            )
          else
            item,
      ];
    }

    state = state.copyWith(
      aircraft: updatedAircraft,
      flights: [
        for (final item in state.flights)
          if (item.id == entry.id) entry else item,
      ],
    );
    _save();
  }

  Future<void> _load() async {
    final preferences = await SharedPreferences.getInstance();
    final rawState = preferences.getString(_storageKey);
    if (rawState == null) {
      return;
    }

    try {
      final decoded = jsonDecode(rawState) as Map<String, dynamic>;
      state = FleetState.fromJson(decoded);
      final missingDemoFlights = [
        for (final flight in _initialState.flights)
          if (!state.flights.any((item) => item.id == flight.id)) flight,
      ];
      if (missingDemoFlights.isNotEmpty) {
        state =
            state.copyWith(flights: [...missingDemoFlights, ...state.flights]);
        _save();
      }
    } on FormatException {
      await preferences.remove(_storageKey);
    } on TypeError {
      await preferences.remove(_storageKey);
    }
  }

  Future<void> _save() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, jsonEncode(state.toJson()));
  }
}

LocationPresenceStatus _determinePresenceStatus(List<FlightLogEntry> flights) {
  if (flights.isEmpty) {
    return LocationPresenceStatus.atField;
  }

  final now = DateTime.now();
  final latestFlight = [...flights]..sort((a, b) => b.date.compareTo(a.date));
  final latest = latestFlight.first;
  final flightEnd = latest.date.add(Duration(minutes: latest.durationMinutes));

  if (now.isAfter(latest.date) && now.isBefore(flightEnd)) {
    return LocationPresenceStatus.flying;
  }

  return LocationPresenceStatus.atField;
}

final _initialState = FleetState(
  appSettings: const AppSettings(
    shareLocationWithFriends: false,
    reachableByChat: true,
    presenceStatus: LocationPresenceStatus.offline,
  ),
  pilotProfile: const PilotProfile(
    name: 'Teddy',
    homeAirfield: 'MFC Suedhang',
    club: 'MFC Adler',
    licenseNumber: '',
    phone: '',
    email: '',
    notes: 'Modellpilot mit Fokus auf Segler, Drohnen und Kunstflug.',
  ),
  aircraft: [
    AircraftModel(
      id: 'asw28',
      name: 'ASW 28',
      type: 'Segler',
      manufacturer: 'Schleicher',
      registration: 'D-1872',
      wingspanMeters: 3.2,
      lengthMeters: 1.42,
      weightKg: 4.8,
      receiver: 'Jeti REX 10',
      propeller: 'Klapp 13x8',
      purchaseDate: DateTime(2024, 3, 12),
      drive: 'Elektrosegler, 6S',
      batteryCount: 2,
      totalFlights: 42,
      flightHours: 18.6,
      status: AircraftStatus.ready,
      lastService: DateTime(2026, 4, 26),
      nextService: DateTime(2026, 6, 10),
      notes: 'Thermikmodell mit Vario, neue Servos im rechten Fluegel.',
    ),
    AircraftModel(
      id: 'extra300',
      name: 'Extra 300',
      type: 'Kunstflug',
      manufacturer: 'Extreme Flight',
      registration: 'D-ACRO',
      wingspanMeters: 1.8,
      lengthMeters: 1.72,
      weightKg: 3.1,
      receiver: 'Spektrum AR8020T',
      propeller: '16x8',
      purchaseDate: DateTime(2025, 7, 4),
      drive: 'Brushless 6S',
      batteryCount: 5,
      totalFlights: 29,
      flightHours: 9.4,
      status: AircraftStatus.ready,
      lastService: DateTime(2026, 5, 5),
      nextService: DateTime(2026, 5, 30),
      notes: 'Schwerpunkt bei 102 mm, Propeller 16x8 pruefen.',
    ),
    AircraftModel(
      id: 'quadx4',
      name: 'Quad X4',
      type: 'Multicopter',
      manufacturer: 'Eigenbau',
      registration: 'FPV-04',
      wingspanMeters: 0.52,
      lengthMeters: 0.52,
      weightKg: 1.2,
      receiver: 'ELRS 2.4 GHz',
      propeller: '5.1x4.3',
      purchaseDate: DateTime(2025, 9, 18),
      drive: '4x Brushless',
      batteryCount: 8,
      totalFlights: 67,
      flightHours: 12.7,
      status: AircraftStatus.maintenance,
      lastService: DateTime(2026, 3, 18),
      nextService: DateTime(2026, 5, 12),
      notes: 'Vibrationen an Motor 3, Lager tauschen.',
    ),
  ],
  batteries: [
    BatteryPack(
      id: 'akku-6s-5000-a',
      label: '6S 5000 A',
      chemistry: 'LiPo',
      cells: 6,
      capacityMah: 5000,
      chargePercent: 100,
      cycles: 34,
      status: BatteryStatus.charged,
      lastUsed: DateTime(2026, 5, 14),
      assignedAircraftId: 'extra300',
      notes: 'Innenwiderstand stabil, fuer Kunstflug freigegeben.',
    ),
    BatteryPack(
      id: 'akku-6s-5000-b',
      label: '6S 5000 B',
      chemistry: 'LiPo',
      cells: 6,
      capacityMah: 5000,
      chargePercent: 62,
      cycles: 35,
      status: BatteryStatus.storage,
      lastUsed: DateTime(2026, 5, 12),
      assignedAircraftId: 'extra300',
      notes: 'Lagerspannung erreicht.',
    ),
    BatteryPack(
      id: 'akku-4s-2200-q1',
      label: '4S 2200 Q1',
      chemistry: 'LiPo',
      cells: 4,
      capacityMah: 2200,
      chargePercent: 78,
      cycles: 88,
      status: BatteryStatus.service,
      lastUsed: DateTime(2026, 5, 9),
      assignedAircraftId: 'quadx4',
      notes: 'Zelle 3 beobachten, Spannungsabfall unter Last.',
    ),
    BatteryPack(
      id: 'akku-2s-rx-asw',
      label: '2S RX ASW',
      chemistry: 'LiIon',
      cells: 2,
      capacityMah: 3000,
      chargePercent: 100,
      cycles: 21,
      status: BatteryStatus.charged,
      lastUsed: DateTime(2026, 5, 15),
      assignedAircraftId: 'asw28',
      notes: 'Empfaengerakku fuer lange Thermikfluege.',
    ),
  ],
  flights: [
    FlightLogEntry(
      id: 'f1',
      aircraftId: 'asw28',
      date: DateTime(2026, 5, 15, 17, 20),
      location: 'MFC Suedhang',
      durationMinutes: 38,
      batteryPacks: 1,
      pilot: 'Teddy',
      notes: 'Ruhige Thermik, Landung auf Bahn 2.',
    ),
    FlightLogEntry(
      id: 'f2',
      aircraftId: 'extra300',
      date: DateTime(2026, 5, 14, 19, 5),
      location: 'Modellflugplatz Nord',
      durationMinutes: 11,
      batteryPacks: 2,
      pilot: 'Teddy',
      notes: 'Messerflug getrimmt, Akku 2 leicht warm.',
    ),
    FlightLogEntry(
      id: 'f3',
      aircraftId: 'asw28',
      date: DateTime(2026, 5, 12, 16, 10),
      location: 'MFC Suedhang',
      durationMinutes: 44,
      batteryPacks: 1,
      pilot: 'Teddy',
      notes: 'Starker Querwind, keine Auffaelligkeiten.',
    ),
    FlightLogEntry(
      id: 'f4',
      aircraftId: 'extra300',
      date: DateTime(2026, 5, 11, 18, 35),
      location: 'LMFC Lohburg',
      durationMinutes: 14,
      batteryPacks: 2,
      pilot: 'Teddy',
      notes: 'Saubere Rollenfolge, Schwerpunkt passt.',
    ),
    FlightLogEntry(
      id: 'f5',
      aircraftId: 'asw28',
      date: DateTime(2026, 5, 10, 15, 45),
      location: 'LMFC Lohburg',
      durationMinutes: 29,
      batteryPacks: 1,
      pilot: 'Teddy',
      notes: 'Thermik am Waldrand, Motorlauf kurz gehalten.',
    ),
    FlightLogEntry(
      id: 'f6',
      aircraftId: 'quadx4',
      date: DateTime(2026, 5, 9, 17, 5),
      location: 'Modellflugplatz Nord',
      durationMinutes: 9,
      batteryPacks: 1,
      pilot: 'Teddy',
      notes: 'Langsamer Ueberflug, Seitenruder pruefen.',
    ),
    FlightLogEntry(
      id: 'f7',
      aircraftId: 'asw28',
      date: DateTime(2026, 5, 8, 14, 20),
      location: 'Hangkante West',
      durationMinutes: 52,
      batteryPacks: 1,
      pilot: 'Teddy',
      notes: 'Langer Gleitflug, Sicht sehr gut.',
    ),
    FlightLogEntry(
      id: 'f8',
      aircraftId: 'extra300',
      date: DateTime(2026, 5, 7, 19, 10),
      location: 'LMFC Lohburg',
      durationMinutes: 12,
      batteryPacks: 2,
      pilot: 'Teddy',
      notes: 'Looping und Turn sauber, Motorlauf unauffaellig.',
    ),
    FlightLogEntry(
      id: 'f9',
      aircraftId: 'asw28',
      date: DateTime(2026, 5, 6, 16, 55),
      location: 'MFC Suedhang',
      durationMinutes: 24,
      batteryPacks: 1,
      pilot: 'Teddy',
      notes: 'Landeeinteilung geuebt, leichter Seitenwind.',
    ),
    FlightLogEntry(
      id: 'f10',
      aircraftId: 'extra300',
      date: DateTime(2026, 5, 5, 18, 15),
      location: 'LMFC Lohburg',
      durationMinutes: 13,
      batteryPacks: 2,
      pilot: 'Teddy',
      notes: 'Snap-Rolls reduziert, Akku 1 bevorzugen.',
    ),
    FlightLogEntry(
      id: 'f11',
      aircraftId: 'asw28',
      date: DateTime(2026, 5, 4, 13, 30),
      location: 'MFC Suedhang',
      durationMinutes: 41,
      batteryPacks: 1,
      pilot: 'Teddy',
      notes: 'Thermik schwach, sauberer Endanflug.',
    ),
    FlightLogEntry(
      id: 'f12',
      aircraftId: 'quadx4',
      date: DateTime(2026, 5, 3, 11, 50),
      location: 'LMFC Lohburg',
      durationMinutes: 8,
      batteryPacks: 1,
      pilot: 'Teddy',
      notes: 'Kurzer Checkflug vor Wartung.',
    ),
    FlightLogEntry(
      id: 'f13',
      aircraftId: 'extra300',
      date: DateTime(2026, 5, 2, 18, 40),
      location: 'Modellflugplatz Nord',
      durationMinutes: 10,
      batteryPacks: 2,
      pilot: 'Teddy',
      notes: 'Kunstflugprogramm einmal komplett geflogen.',
    ),
    FlightLogEntry(
      id: 'f14',
      aircraftId: 'asw28',
      date: DateTime(2026, 4, 30, 16, 25),
      location: 'LMFC Lohburg',
      durationMinutes: 31,
      batteryPacks: 1,
      pilot: 'Teddy',
      notes: 'Akku nach 31 Minuten noch Reserve.',
    ),
    FlightLogEntry(
      id: 'f15',
      aircraftId: 'asw28',
      date: DateTime(2026, 4, 28, 15, 10),
      location: 'Hangkante West',
      durationMinutes: 47,
      batteryPacks: 1,
      pilot: 'Teddy',
      notes: 'Mehrere Kreise in ruhiger Abendthermik.',
    ),
    FlightLogEntry(
      id: 'f16',
      aircraftId: 'extra300',
      date: DateTime(2026, 4, 27, 18, 5),
      location: 'LMFC Lohburg',
      durationMinutes: 15,
      batteryPacks: 2,
      pilot: 'Teddy',
      notes: 'Gasannahme gut, Fahrwerk kontrollieren.',
    ),
    FlightLogEntry(
      id: 'f17',
      aircraftId: 'extra300',
      date: DateTime(2026, 4, 25, 17, 45),
      location: 'MFC Suedhang',
      durationMinutes: 12,
      batteryPacks: 2,
      pilot: 'Teddy',
      notes: 'Rauchattrappe nicht montiert, Flug stabil.',
    ),
    FlightLogEntry(
      id: 'f18',
      aircraftId: 'asw28',
      date: DateTime(2026, 4, 23, 12, 30),
      location: 'LMFC Lohburg',
      durationMinutes: 26,
      batteryPacks: 1,
      pilot: 'Teddy',
      notes: 'Schulung mit ruhigen Platzrunden.',
    ),
    FlightLogEntry(
      id: 'f19',
      aircraftId: 'asw28',
      date: DateTime(2026, 4, 21, 14, 0),
      location: 'Modellflugplatz Nord',
      durationMinutes: 36,
      batteryPacks: 1,
      pilot: 'Teddy',
      notes: 'Schlepphoehe simuliert, Spoiler geprueft.',
    ),
    FlightLogEntry(
      id: 'f20',
      aircraftId: 'quadx4',
      date: DateTime(2026, 4, 20, 10, 40),
      location: 'LMFC Lohburg',
      durationMinutes: 7,
      batteryPacks: 1,
      pilot: 'Teddy',
      notes: 'Sehr kurzer Flug, Motorhaube sitzt locker.',
    ),
    FlightLogEntry(
      id: 'f21',
      aircraftId: 'extra300',
      date: DateTime(2026, 4, 18, 18, 55),
      location: 'MFC Suedhang',
      durationMinutes: 16,
      batteryPacks: 2,
      pilot: 'Teddy',
      notes: 'Figurenfolge mit geringer Hoehe beendet.',
    ),
    FlightLogEntry(
      id: 'f22',
      aircraftId: 'asw28',
      date: DateTime(2026, 4, 16, 15, 20),
      location: 'LMFC Lohburg',
      durationMinutes: 28,
      batteryPacks: 1,
      pilot: 'Teddy',
      notes: 'Guter Test fuer Tabellenansicht im Flugbuch.',
    ),
    FlightLogEntry(
      id: 'f23',
      aircraftId: 'asw28',
      date: DateTime(2026, 4, 14, 13, 15),
      location: 'Hangkante West',
      durationMinutes: 49,
      batteryPacks: 1,
      pilot: 'Teddy',
      notes: 'Letzter Flug der Serie, ruhige Landung.',
    ),
  ],
);
