import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/aircraft_model.dart';
import '../models/fleet_state.dart';
import '../services/fleet_cloud_repository.dart';
import '../services/fleet_storage_service.dart';

export '../models/fleet_state.dart';

final fleetProvider = StateNotifierProvider<FleetNotifier, FleetState>((ref) {
  return FleetNotifier(ref);
});

typedef _CloudWrite = Future<void> Function(
  FleetCloudRepository repository,
  User user,
  FleetState state,
);

enum CloudSyncResult {
  synced,
  cloudUnavailable,
  wifiRequired,
}

class FleetNotifier extends StateNotifier<FleetState> {
  final Ref _ref;
  late final Future<void> _bootstrapFuture;
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _cloudSubscription;
  Future<void> _saveQueue = Future.value();
  String? _activeUid;
  int _pendingCloudWrites = 0;
  int _localRevision = 0;
  DateTime? _ignoreCloudRefreshUntil;
  bool _hasUnsyncedLocalChanges = false;
  bool _disposed = false;

  FleetNotifier(this._ref) : super(_initialState) {
    _bootstrapFuture = _loadBootstrapState();
    if (Firebase.apps.isNotEmpty) {
      _authSubscription =
          FirebaseAuth.instance.authStateChanges().listen(_handleAuthState);
    }
  }

  static const _legacyStorageKey = 'modellflug_fleet_state';

  void addAircraft(AircraftModel aircraft) {
    state = state.copyWith(aircraft: [aircraft, ...state.aircraft]);
    _persistLater(
      (repository, user, snapshot) => repository.saveAircraft(
        user: user,
        state: snapshot,
        aircraft: aircraft,
      ),
    );
  }

  void updateAircraft(AircraftModel aircraft) {
    state = state.copyWith(
      aircraft: [
        for (final item in state.aircraft)
          if (item.id == aircraft.id) aircraft else item,
      ],
    );
    _persistLater(
      (repository, user, snapshot) => repository.saveAircraft(
        user: user,
        state: snapshot,
        aircraft: aircraft,
      ),
    );
  }

  void deleteAircraft(String id) {
    final deletedFlightIds = [
      for (final item in state.flights)
        if (item.aircraftId == id) item.id,
    ];
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
          if (item.aircraftIds.contains(id))
            item.copyWith(
              assignedAircraftId: '',
              assignedAircraftIds: [
                for (final aircraftId in item.aircraftIds)
                  if (aircraftId != id) aircraftId,
              ],
            )
          else
            item,
      ],
    );
    _persistLater(
      (repository, user, snapshot) => repository.deleteAircraft(
        user: user,
        state: snapshot,
        aircraftId: id,
        deletedFlightIds: deletedFlightIds,
      ),
    );
  }

  void updateStatus(String id, AircraftStatus status) {
    AircraftModel? changedAircraft;
    state = state.copyWith(
      aircraft: [
        for (final item in state.aircraft)
          if (item.id == id)
            changedAircraft = item.copyWith(status: status)
          else
            item,
      ],
    );
    if (changedAircraft == null) {
      _persistLater();
    } else {
      _persistLater(
        (repository, user, snapshot) => repository.saveAircraft(
          user: user,
          state: snapshot,
          aircraft: changedAircraft!,
        ),
      );
    }
  }

  void addBattery(BatteryPack battery) {
    final numberAlreadyExists = state.batteries
        .any((item) => item.inventoryNumber == battery.inventoryNumber);
    final numberedBattery = battery.inventoryNumber > 0 && !numberAlreadyExists
        ? battery
        : battery.copyWith(
            inventoryNumber: state.nextBatteryInventoryNumber,
          );
    state = state.copyWith(batteries: [numberedBattery, ...state.batteries]);
    _persistLater(
      (repository, user, snapshot) => repository.saveBattery(
        user: user,
        state: snapshot,
        battery: numberedBattery,
      ),
    );
  }

  void updateBattery(BatteryPack battery) {
    state = state.copyWith(
      batteries: [
        for (final item in state.batteries)
          if (item.id == battery.id) battery else item,
      ],
    );
    _persistLater(
      (repository, user, snapshot) => repository.saveBattery(
        user: user,
        state: snapshot,
        battery: battery,
      ),
    );
  }

  void updateBatteryStatus(String id, BatteryStatus status) {
    BatteryPack? changedBattery;
    state = state.copyWith(
      batteries: [
        for (final item in state.batteries)
          if (item.id == id)
            changedBattery = item.copyWith(status: status)
          else
            item,
      ],
    );
    if (changedBattery == null) {
      _persistLater();
    } else {
      _persistLater(
        (repository, user, snapshot) => repository.saveBattery(
          user: user,
          state: snapshot,
          battery: changedBattery!,
        ),
      );
    }
  }

  void deleteBattery(String id) {
    state = state.copyWith(
      batteries: [
        for (final item in state.batteries)
          if (item.id != id) item,
      ],
    );
    _persistLater(
      (repository, user, snapshot) => repository.deleteBattery(
        user: user,
        state: snapshot,
        batteryId: id,
      ),
    );
  }

  void updatePilotProfile(PilotProfile profile) {
    state = state.copyWith(pilotProfile: profile);
    _persistLater(
      (repository, user, snapshot) => repository.savePilotProfile(
        user: user,
        state: snapshot,
      ),
    );
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
    _persistAppSettingsLater();
  }

  void updateChatReachability(bool enabled) {
    state = state.copyWith(
      appSettings: state.appSettings.copyWith(reachableByChat: enabled),
    );
    _persistAppSettingsLater();
  }

  void updateAppSettings(AppSettings settings) {
    state = state.copyWith(appSettings: settings);
    _persistAppSettingsLater();
  }

  Future<CloudSyncResult> syncNow() async {
    await _bootstrapFuture;

    final user =
        Firebase.apps.isNotEmpty ? FirebaseAuth.instance.currentUser : null;
    final repository = _ref.read(fleetCloudRepositoryProvider);
    if (_activeUid == null ||
        user == null ||
        user.uid != _activeUid ||
        repository == null) {
      state = state.copyWith(syncStatus: FleetSyncStatus.localOnly);
      await _saveLocalState(state);
      return CloudSyncResult.cloudUnavailable;
    }

    if (!await _canUseCloudSyncNetwork(state)) {
      state = state.copyWith(syncStatus: FleetSyncStatus.cloudPaused);
      await _saveLocalState(state);
      return CloudSyncResult.wifiRequired;
    }

    state = state.copyWith(syncStatus: FleetSyncStatus.syncing);
    final synced = await _saveCloudState(state, null);
    return synced && state.syncStatus == FleetSyncStatus.cloudActive
        ? CloudSyncResult.synced
        : CloudSyncResult.cloudUnavailable;
  }

  String exportJson() {
    return const JsonEncoder.withIndent('  ').convert(state.toJson());
  }

  Future<void> importJson(String rawJson) async {
    final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
    state = FleetState.fromJson(decoded);
    await _persist(
      (repository, user, snapshot) => repository.saveState(
        user: user,
        state: snapshot,
        replaceCollections: true,
      ),
    );
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
    final changedAircraft = [
      for (final aircraft in updatedAircraft)
        if (aircraft.id == entry.aircraftId) aircraft,
    ];
    _persistLater(
      (repository, user, snapshot) => repository.saveFlight(
        user: user,
        state: snapshot,
        flight: entry,
        changedAircraft: changedAircraft,
      ),
    );
  }

  void updateFlight(FlightLogEntry entry) {
    final previous = state.flights.cast<FlightLogEntry?>().firstWhere(
          (item) => item?.id == entry.id,
          orElse: () => null,
        );

    var updatedAircraft = state.aircraft;
    final changedAircraftIds = <String>{};
    if (previous != null) {
      changedAircraftIds.add(previous.aircraftId);
      changedAircraftIds.add(entry.aircraftId);
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
    final changedAircraft = [
      for (final aircraft in updatedAircraft)
        if (changedAircraftIds.contains(aircraft.id)) aircraft,
    ];
    _persistLater(
      (repository, user, snapshot) => repository.saveFlight(
        user: user,
        state: snapshot,
        flight: entry,
        changedAircraft: changedAircraft,
      ),
    );
  }

  void _persistAppSettingsLater() {
    _persistLater(
      (repository, user, snapshot) => repository.saveAppSettings(
        user: user,
        state: snapshot,
      ),
    );
  }

  Future<void> _loadBootstrapState() async {
    final loadedState = await _readLocalState(_legacyStorageKey);
    if (_disposed) {
      return;
    }
    state = loadedState ?? state.copyWith(isLoaded: true);
  }

  Future<void> _handleAuthState(User? user) async {
    await _bootstrapFuture;
    if (_disposed) {
      return;
    }

    if (user == null) {
      _activeUid = null;
      _hasUnsyncedLocalChanges = false;
      await _cloudSubscription?.cancel();
      _cloudSubscription = null;
      state = _initialState.copyWith(
        isLoaded: true,
        syncStatus: FleetSyncStatus.localOnly,
      );
      return;
    }

    if (_activeUid == user.uid) {
      return;
    }

    await _connectAccount(user);
  }

  Future<void> _connectAccount(User user) async {
    _activeUid = user.uid;
    await _cloudSubscription?.cancel();
    _cloudSubscription = null;

    final accountLocalState =
        await _readLocalState(_storageKeyForUid(user.uid));
    final legacyLocalState = await _readLocalState(_legacyStorageKey);
    final localState = accountLocalState ??
        legacyLocalState ??
        _initialState.copyWith(isLoaded: true);
    if (!_disposed && _activeUid == user.uid) {
      state = localState.copyWith(
        isLoaded: true,
        syncStatus: FleetSyncStatus.syncing,
      );
    }

    final repository = _ref.read(fleetCloudRepositoryProvider);
    if (repository == null) {
      state = state.copyWith(syncStatus: FleetSyncStatus.localOnly);
      return;
    }

    try {
      final cloudState = await repository.loadState(user.uid);
      if (_disposed || _activeUid != user.uid) {
        return;
      }

      if (cloudState == null) {
        await _saveCloudState(state, null);
        await _saveLocalState(state);
      } else {
        _hasUnsyncedLocalChanges = false;
        state = cloudState.copyWith(
          isLoaded: true,
          syncStatus: FleetSyncStatus.cloudActive,
        );
        await _saveLocalState(state);
      }

      _cloudSubscription = repository.watchFleetMeta(user.uid).listen(
        (snapshot) {
          if (snapshot.metadata.hasPendingWrites) {
            return;
          }
          unawaited(_refreshFromCloud(user.uid));
        },
      );
    } catch (_) {
      state = state.copyWith(syncStatus: FleetSyncStatus.cloudPaused);
      await _saveLocalState(state);
    }
  }

  Future<void> _refreshFromCloud(String uid) async {
    final repository = _ref.read(fleetCloudRepositoryProvider);
    if (repository == null || _activeUid != uid) {
      return;
    }
    if (_shouldIgnoreCloudRefresh) {
      return;
    }

    try {
      final cloudState = await repository.loadState(uid);
      if (cloudState == null ||
          _disposed ||
          _activeUid != uid ||
          _shouldIgnoreCloudRefresh) {
        return;
      }
      state = cloudState.copyWith(
        isLoaded: true,
        syncStatus: FleetSyncStatus.cloudActive,
      );
      await _saveLocalState(state);
    } catch (_) {
      state = state.copyWith(syncStatus: FleetSyncStatus.cloudPaused);
    }
  }

  Future<FleetState?> _readLocalState(String storageKey) async {
    final preferences = await SharedPreferences.getInstance();
    final rawState = preferences.getString(storageKey);
    if (rawState == null) {
      return null;
    }

    try {
      final decoded = jsonDecode(rawState) as Map<String, dynamic>;
      var loadedState = FleetState.fromJson(decoded).copyWith(isLoaded: true);
      final migratedSurfaceSettings =
          !loadedState.appSettings.surfaceSettingsInitialized;
      if (migratedSurfaceSettings) {
        loadedState = loadedState.copyWith(
          appSettings: loadedState.appSettings.copyWith(
            autoOpenDashboardAfterLoading: true,
            surfaceSettingsInitialized: true,
          ),
        );
      }
      final missingDemoFlights = [
        for (final flight in _initialState.flights)
          if (!loadedState.flights.any((item) => item.id == flight.id)) flight,
      ];
      if (missingDemoFlights.isNotEmpty || migratedSurfaceSettings) {
        loadedState = loadedState.copyWith(
          flights: [...missingDemoFlights, ...loadedState.flights],
        );
        await preferences.setString(
            storageKey, jsonEncode(loadedState.toJson()));
      }
      return loadedState;
    } on FormatException {
      await preferences.remove(storageKey);
      return null;
    } on TypeError {
      await preferences.remove(storageKey);
      return null;
    }
  }

  void _persistLater([_CloudWrite? cloudWrite]) {
    unawaited(_persist(cloudWrite));
  }

  Future<void> _persist([_CloudWrite? cloudWrite]) {
    _localRevision++;
    final revision = _localRevision;
    final snapshot = state;
    _hasUnsyncedLocalChanges = true;
    _ignoreCloudRefreshUntil = DateTime.now().add(const Duration(seconds: 12));
    _saveQueue = _saveQueue.catchError((_) {}).then((_) async {
      await _saveLocalState(snapshot);
      await _saveCloudState(snapshot, cloudWrite, revision: revision);
    });
    return _saveQueue;
  }

  Future<void> _saveLocalState(FleetState snapshot) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKeyForUid(_activeUid),
      jsonEncode(snapshot.toJson()),
    );
  }

  Future<bool> _saveCloudState(
    FleetState snapshot,
    _CloudWrite? _, {
    int? revision,
  }) async {
    if (Firebase.apps.isEmpty || _activeUid == null) {
      return false;
    }

    final user = FirebaseAuth.instance.currentUser;
    final repository = _ref.read(fleetCloudRepositoryProvider);
    if (user == null || user.uid != _activeUid || repository == null) {
      return false;
    }

    if (!await _canUseCloudSyncNetwork(snapshot)) {
      if (!_disposed && user.uid == _activeUid) {
        state = snapshot.copyWith(syncStatus: FleetSyncStatus.cloudPaused);
        await _saveLocalState(state);
      }
      return false;
    }

    _pendingCloudWrites++;
    _ignoreCloudRefreshUntil = DateTime.now().add(const Duration(seconds: 12));
    try {
      final preparedSnapshot = await _prepareFilesForCloud(user, snapshot);
      await repository.saveState(
        user: user,
        state: preparedSnapshot,
        replaceCollections: true,
      );
      if (!_disposed && user.uid == _activeUid) {
        final isLatestLocalWrite =
            revision == null || revision == _localRevision;
        if (isLatestLocalWrite) {
          _hasUnsyncedLocalChanges = false;
          state = preparedSnapshot.copyWith(
            syncStatus: FleetSyncStatus.cloudActive,
          );
          await _saveLocalState(state);
        }
      }
      return true;
    } catch (_) {
      if (!_disposed && user.uid == _activeUid) {
        final isLatestLocalWrite =
            revision == null || revision == _localRevision;
        state = isLatestLocalWrite
            ? snapshot.copyWith(syncStatus: FleetSyncStatus.cloudPaused)
            : state.copyWith(syncStatus: FleetSyncStatus.cloudPaused);
        await _saveLocalState(state);
      }
      return false;
    } finally {
      if (_pendingCloudWrites > 0) {
        _pendingCloudWrites--;
      }
      if (_pendingCloudWrites == 0) {
        _ignoreCloudRefreshUntil =
            DateTime.now().add(const Duration(seconds: 3));
      }
    }
  }

  Future<bool> _canUseCloudSyncNetwork(FleetState snapshot) async {
    if (!snapshot.appSettings.wifiOnlySync) {
      return true;
    }

    try {
      final connections = await Connectivity().checkConnectivity();
      return _hasWifiSyncConnection(connections);
    } catch (_) {
      return false;
    }
  }

  Future<FleetState> _prepareFilesForCloud(
    User user,
    FleetState snapshot,
  ) async {
    final storageService = _ref.read(fleetStorageServiceProvider);
    if (storageService == null) {
      return snapshot;
    }
    return storageService.moveEmbeddedFilesToStorage(
      user: user,
      state: snapshot,
    );
  }

  String _storageKeyForUid(String? uid) {
    if (uid == null || uid.isEmpty) {
      return _legacyStorageKey;
    }
    return '${_legacyStorageKey}_$uid';
  }

  bool get _shouldIgnoreCloudRefresh {
    final ignoreUntil = _ignoreCloudRefreshUntil;
    return _hasUnsyncedLocalChanges ||
        _pendingCloudWrites > 0 ||
        (ignoreUntil != null && DateTime.now().isBefore(ignoreUntil));
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_authSubscription?.cancel());
    unawaited(_cloudSubscription?.cancel());
    super.dispose();
  }
}

bool _hasWifiSyncConnection(List<ConnectivityResult> connections) {
  return connections.contains(ConnectivityResult.wifi) ||
      connections.contains(ConnectivityResult.ethernet);
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
    timeZone: 'Europe/Berlin',
    distanceUnit: 'km',
    windUnit: 'km/h',
    temperatureUnit: 'Celsius',
    language: 'Deutsch',
  ),
  pilotProfile: const PilotProfile(
    name: 'Teddy',
    homeAirfield: 'MFC Suedhang',
    flightAreas: ['LMFC-Fluggelaende'],
    club: 'MFC Adler',
    licenseNumber: '',
    phone: '',
    email: '',
    transmitters: ['Jeti DS-16', 'Spektrum NX10'],
    notes: 'Modellpilot mit Fokus auf Segelflugzeuge, Drohnen und Kunstflug.',
  ),
  aircraft: [
    AircraftModel(
      id: 'asw28',
      name: 'ASW 28',
      type: 'Segelflugzeug',
      manufacturer: 'Schleicher',
      registration: 'D-1872',
      wingspanMeters: 3.2,
      lengthMeters: 1.42,
      weightKg: 4.8,
      transmitter: 'Jeti DS-16',
      transmitterMemorySlot: 'ASW28-01',
      receiver: 'Jeti REX 10',
      propeller: 'Klapp 13x8',
      materialFuselageWing: 'GFK-Rumpf / Styro-Abachi-Flaeche',
      wingLoading: '58 g/dm2',
      recommendedDriveBattery: '6S 4000 mAh LiPo',
      servos: '6x KST X10, 2x KST X12',
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
      type: 'Kunstflieger',
      manufacturer: 'Extreme Flight',
      registration: 'D-ACRO',
      wingspanMeters: 1.8,
      lengthMeters: 1.72,
      weightKg: 3.1,
      transmitter: 'Spektrum NX10',
      transmitterMemorySlot: 'EXTRA-300',
      receiver: 'Spektrum AR8020T',
      propeller: '16x8',
      materialFuselageWing: 'Balsa/CFK-Verstaerkungen',
      wingLoading: '72 g/dm2',
      recommendedDriveBattery: '6S 5000 mAh LiPo',
      servos: '4x Savox 1256TG, 2x Mini HV',
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
      type: 'Drohne',
      manufacturer: 'Eigenbau',
      registration: 'FPV-04',
      wingspanMeters: 0.52,
      lengthMeters: 0.52,
      weightKg: 1.2,
      transmitter: 'Radiomaster TX16S',
      transmitterMemorySlot: 'QUAD-X4',
      receiver: 'ELRS 2.4 GHz',
      propeller: '5.1x4.3',
      materialFuselageWing: 'Carbonrahmen / Kunststoffarme',
      wingLoading: '-',
      recommendedDriveBattery: '4S 1500 mAh LiPo',
      servos: 'Keine, Flightcontroller direkt',
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
      inventoryNumber: 1,
      label: '6S 5000 A',
      chemistry: 'LiPo',
      cells: 6,
      capacityMah: 5000,
      chargePercent: 100,
      cycles: 34,
      status: BatteryStatus.charged,
      purchaseDate: DateTime(2025, 8, 22),
      lastUsed: DateTime(2026, 5, 14),
      assignedAircraftId: 'extra300',
      notes: 'Innenwiderstand stabil, fuer Kunstflug freigegeben.',
    ),
    BatteryPack(
      id: 'akku-6s-5000-b',
      inventoryNumber: 2,
      label: '6S 5000 B',
      chemistry: 'LiPo',
      cells: 6,
      capacityMah: 5000,
      chargePercent: 62,
      cycles: 35,
      status: BatteryStatus.storage,
      purchaseDate: DateTime(2025, 8, 22),
      lastUsed: DateTime(2026, 5, 12),
      assignedAircraftId: 'extra300',
      notes: 'Lagerspannung erreicht.',
    ),
    BatteryPack(
      id: 'akku-4s-2200-q1',
      inventoryNumber: 3,
      label: '4S 2200 Q1',
      chemistry: 'LiPo',
      cells: 4,
      capacityMah: 2200,
      chargePercent: 78,
      cycles: 88,
      status: BatteryStatus.service,
      purchaseDate: DateTime(2024, 11, 4),
      lastUsed: DateTime(2026, 5, 9),
      assignedAircraftId: 'quadx4',
      notes: 'Zelle 3 beobachten, Spannungsabfall unter Last.',
    ),
    BatteryPack(
      id: 'akku-2s-rx-asw',
      inventoryNumber: 4,
      label: '2S RX ASW',
      chemistry: 'LiIon',
      cells: 2,
      capacityMah: 3000,
      chargePercent: 100,
      cycles: 21,
      status: BatteryStatus.charged,
      purchaseDate: DateTime(2026, 2, 18),
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
