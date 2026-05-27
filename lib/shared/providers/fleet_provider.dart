import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/aircraft_model.dart';
import '../models/fleet_state.dart';
import '../services/fleet_cloud_repository.dart';
import '../services/fleet_storage_service.dart';
import '../services/member_chat_service.dart';
import '../utils/image_thumbnail.dart';

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

enum AutomaticBackupResult {
  created,
  disabled,
  notDue,
  unchanged,
  cloudUnavailable,
  wifiRequired,
  failed,
  alreadyRunning,
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
  bool _automaticBackupRunning = false;
  bool _disposed = false;
  String? _lastPublishedMemberSignature;

  FleetNotifier(this._ref) : super(_initialState) {
    _bootstrapFuture = _loadBootstrapState();
    if (Firebase.apps.isNotEmpty) {
      _authSubscription =
          FirebaseAuth.instance.authStateChanges().listen(_handleAuthState);
    }
  }

  static const _legacyStorageKey = 'modellflug_fleet_state';
  static const _automaticBackupInterval = Duration(days: 1);

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

  void saveAircraftWithBatteryAssignment(
    AircraftModel aircraft, {
    required Iterable<String> selectedBatteryIds,
  }) {
    final aircraftExists = state.aircraft.any((item) => item.id == aircraft.id);
    state = state.copyWith(
      aircraft: aircraftExists
          ? [
              for (final item in state.aircraft)
                if (item.id == aircraft.id) aircraft else item,
            ]
          : [aircraft, ...state.aircraft],
      batteries: _batteriesWithAircraftAssignment(
        state.batteries,
        aircraftId: aircraft.id,
        selectedBatteryIds: selectedBatteryIds,
      ),
    );
    _persistLater();
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
    _publishMemberProfileLater();
  }

  void updateLocationSharing(bool enabled) {
    state = state.copyWith(
      appSettings: state.appSettings.copyWith(
        shareLocationWithFriends: enabled,
        presenceStatus: enabled
            ? LocationPresenceStatus.atField
            : LocationPresenceStatus.offline,
      ),
    );
    _persistAppSettingsLater();
    _publishMemberProfileLater();
  }

  void updateFlightTimerPresence(bool running) {
    if (!state.appSettings.shareLocationWithFriends) {
      return;
    }

    final nextStatus = running
        ? LocationPresenceStatus.flying
        : LocationPresenceStatus.atField;
    if (state.appSettings.presenceStatus == nextStatus) {
      return;
    }

    state = state.copyWith(
      appSettings: state.appSettings.copyWith(presenceStatus: nextStatus),
    );
    _persistAppSettingsLater();
    _publishMemberProfileLater();
  }

  void updateChatReachability(bool enabled) {
    state = state.copyWith(
      appSettings: state.appSettings.copyWith(reachableByChat: enabled),
    );
    _persistAppSettingsLater();
    _publishMemberProfileLater();
  }

  void updateAppSettings(AppSettings settings) {
    state = state.copyWith(appSettings: settings);
    _persistAppSettingsLater();
    _publishMemberProfileLater();
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

  Future<AutomaticBackupResult> runAutomaticBackupCheck() async {
    await _bootstrapFuture;
    return _createAutomaticBackupIfNeeded();
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

  void addFlight(FlightLogEntry entry, {String? usedBatteryId}) {
    final countedBatteryId = usedBatteryId ?? entry.batteryId.trim();
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
    final updatedBatteries = [
      for (final item in state.batteries)
        if (item.id == countedBatteryId)
          item.copyWith(cycles: item.cycles + 1, lastUsed: entry.date)
        else
          item,
    ];

    state = state.copyWith(
      aircraft: updatedAircraft,
      batteries: updatedBatteries,
      flights: [entry, ...state.flights],
    );
    final changedAircraft = [
      for (final aircraft in updatedAircraft)
        if (aircraft.id == entry.aircraftId) aircraft,
    ];
    final changedBatteries = [
      for (final battery in updatedBatteries)
        if (battery.id == countedBatteryId) battery,
    ];
    _persistLater(
      (repository, user, snapshot) => repository.saveFlight(
        user: user,
        state: snapshot,
        flight: entry,
        changedAircraft: changedAircraft,
        changedBatteries: changedBatteries,
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

  void deleteFlight(String flightId) {
    final deleted = state.flights.cast<FlightLogEntry?>().firstWhere(
          (item) => item?.id == flightId,
          orElse: () => null,
        );
    if (deleted == null) {
      return;
    }

    final remainingFlights = [
      for (final item in state.flights)
        if (item.id != flightId) item,
    ];
    final updatedAircraft = [
      for (final item in state.aircraft)
        if (item.id == deleted.aircraftId)
          item.copyWith(
            totalFlights: item.totalFlights > 0 ? item.totalFlights - 1 : 0,
            flightHours: item.flightHours > deleted.durationMinutes / 60
                ? item.flightHours - deleted.durationMinutes / 60
                : 0,
          )
        else
          item,
    ];

    final deletedBatteryId = deleted.batteryId.trim();
    final updatedBatteries = deletedBatteryId.isEmpty
        ? state.batteries
        : [
            for (final item in state.batteries)
              if (item.id == deletedBatteryId)
                item.copyWith(
                  cycles: item.cycles > 0 ? item.cycles - 1 : 0,
                  lastUsed: _lastUsedAfterFlightDelete(
                    item,
                    deleted,
                    remainingFlights,
                  ),
                )
              else
                item,
          ];

    state = state.copyWith(
      aircraft: updatedAircraft,
      batteries: updatedBatteries,
      flights: remainingFlights,
    );

    final changedAircraft = [
      for (final aircraft in updatedAircraft)
        if (aircraft.id == deleted.aircraftId) aircraft,
    ];
    final changedBatteries = [
      for (final battery in updatedBatteries)
        if (battery.id == deletedBatteryId) battery,
    ];
    _persistLater(
      (repository, user, snapshot) => repository.deleteFlight(
        user: user,
        state: snapshot,
        flightId: flightId,
        changedAircraft: changedAircraft,
        changedBatteries: changedBatteries,
      ),
    );
  }

  DateTime _lastUsedAfterFlightDelete(
    BatteryPack battery,
    FlightLogEntry deleted,
    List<FlightLogEntry> remainingFlights,
  ) {
    DateTime? latest;
    for (final flight in remainingFlights) {
      if (flight.batteryId.trim() != battery.id) {
        continue;
      }
      if (latest == null || flight.date.isAfter(latest)) {
        latest = flight.date;
      }
    }
    if (latest != null) {
      return latest;
    }
    return battery.lastUsed == deleted.date
        ? battery.purchaseDate
        : battery.lastUsed;
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
      _lastPublishedMemberSignature = null;
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
    final localState =
        accountLocalState == null || _isOldUntouchedDemoState(accountLocalState)
            ? _starterStateForUser()
            : _withStarterDemoModelPhotos(accountLocalState);
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

      final preparedCloudState =
          cloudState == null ? null : _withStarterDemoModelPhotos(cloudState);
      if (preparedCloudState == null ||
          _isOldUntouchedDemoState(preparedCloudState)) {
        if (_isOldUntouchedDemoState(state)) {
          state = _starterStateForUser().copyWith(
            syncStatus: FleetSyncStatus.syncing,
          );
        }
        await _saveCloudState(state, null);
        await _saveLocalState(state);
      } else {
        final migratedDemoPhotos = !identical(preparedCloudState, cloudState);
        _hasUnsyncedLocalChanges = false;
        state = preparedCloudState.copyWith(
          isLoaded: true,
          syncStatus: FleetSyncStatus.cloudActive,
        );
        await _saveLocalState(state);
        if (migratedDemoPhotos) {
          await _saveCloudState(state, null);
        }
      }

      _cloudSubscription = repository.watchFleetMeta(user.uid).listen(
        (snapshot) {
          if (snapshot.metadata.hasPendingWrites) {
            return;
          }
          unawaited(_refreshFromCloud(user.uid));
        },
      );
      unawaited(_createAutomaticBackupIfNeeded());
      _publishMemberProfileLater();
    } catch (_) {
      state = state.copyWith(syncStatus: FleetSyncStatus.cloudPaused);
      await _saveLocalState(state);
      _publishMemberProfileLater();
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
      final preparedCloudState = _withStarterDemoModelPhotos(cloudState);
      final migratedDemoPhotos = !identical(preparedCloudState, cloudState);
      state = preparedCloudState.copyWith(
        isLoaded: true,
        syncStatus: FleetSyncStatus.cloudActive,
      );
      await _saveLocalState(state);
      if (migratedDemoPhotos) {
        await _saveCloudState(state, null);
      }
      _publishMemberProfileLater();
    } catch (_) {
      state = state.copyWith(syncStatus: FleetSyncStatus.cloudPaused);
    }
  }

  void _publishMemberProfileLater() {
    unawaited(_publishMemberProfile());
  }

  Future<void> _publishMemberProfile() async {
    if (Firebase.apps.isEmpty || _activeUid == null) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    final service = _ref.read(memberChatServiceProvider);
    if (user == null || user.uid != _activeUid || service == null) {
      return;
    }

    final snapshot = state;
    final displayName = _memberDisplayNameFor(user, snapshot.pilotProfile);
    final photoSource = await _memberPhotoSourceFor(
      user,
      snapshot.pilotProfile,
    );
    final signature = [
      user.uid,
      displayName,
      snapshot.pilotProfile.club,
      snapshot.appSettings.reachableByChat,
      snapshot.appSettings.shareLocationWithFriends,
      snapshot.appSettings.presenceStatus.name,
      _hasProfilePhoto(user, snapshot.pilotProfile),
      photoSource ?? '',
    ].join('|');

    if (_lastPublishedMemberSignature == signature) {
      return;
    }
    _lastPublishedMemberSignature = signature;

    try {
      await service.saveCurrentMemberProfile(
        user: user,
        displayName: displayName,
        club: snapshot.pilotProfile.club,
        reachableByChat: snapshot.appSettings.reachableByChat,
        shareLocation: snapshot.appSettings.shareLocationWithFriends,
        presenceStatus: snapshot.appSettings.presenceStatus.name,
        photoSource: photoSource,
        clearPhotoSource: !_hasProfilePhoto(user, snapshot.pilotProfile),
      );
    } catch (_) {
      _lastPublishedMemberSignature = null;
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
      final stateWithDemoPhotos = _withStarterDemoModelPhotos(loadedState);
      final migratedDemoPhotos = !identical(stateWithDemoPhotos, loadedState);
      loadedState = stateWithDemoPhotos;
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
      if (migratedDemoPhotos || migratedSurfaceSettings) {
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
      unawaited(_createAutomaticBackupIfNeeded());
    });
    return _saveQueue;
  }

  Future<AutomaticBackupResult> _createAutomaticBackupIfNeeded() async {
    if (_automaticBackupRunning) {
      return AutomaticBackupResult.alreadyRunning;
    }

    _automaticBackupRunning = true;
    try {
      final snapshot = state;
      final settings = snapshot.appSettings;
      if (!settings.automaticBackupEnabled) {
        return AutomaticBackupResult.disabled;
      }

      if (!_automaticBackupDue(settings, DateTime.now())) {
        return AutomaticBackupResult.notDue;
      }

      final signature = _automaticBackupSignature(snapshot);
      if (signature == settings.lastAutomaticBackupSignature) {
        return AutomaticBackupResult.unchanged;
      }

      if (Firebase.apps.isEmpty || _activeUid == null) {
        return AutomaticBackupResult.cloudUnavailable;
      }

      final user = FirebaseAuth.instance.currentUser;
      final repository = _ref.read(fleetCloudRepositoryProvider);
      if (user == null || user.uid != _activeUid || repository == null) {
        return AutomaticBackupResult.cloudUnavailable;
      }

      if (!await _canUseCloudSyncNetwork(snapshot)) {
        if (!_disposed && user.uid == _activeUid) {
          state = snapshot.copyWith(syncStatus: FleetSyncStatus.cloudPaused);
          await _saveLocalState(state);
        }
        return AutomaticBackupResult.wifiRequired;
      }

      final now = DateTime.now();
      final completedAt = now.toUtc().toIso8601String();
      final preparedSnapshot = await _prepareFilesForCloud(user, snapshot);
      final backupState = preparedSnapshot.copyWith(
        appSettings: preparedSnapshot.appSettings.copyWith(
          lastAutomaticBackupAt: completedAt,
          lastAutomaticBackupSignature: signature,
        ),
        syncStatus: FleetSyncStatus.cloudActive,
      );

      _ignoreCloudRefreshUntil =
          DateTime.now().add(const Duration(seconds: 12));
      await repository.saveAutomaticBackup(
        user: user,
        state: backupState,
        backupId: _automaticBackupId(now),
        signature: signature,
      );

      if (!_disposed && user.uid == _activeUid) {
        final currentState = state.copyWith(
          appSettings: state.appSettings.copyWith(
            lastAutomaticBackupAt: completedAt,
            lastAutomaticBackupSignature: signature,
          ),
          syncStatus: FleetSyncStatus.cloudActive,
        );
        state = currentState;
        await _saveLocalState(currentState);
        await repository.saveAppSettings(user: user, state: currentState);
      }

      return AutomaticBackupResult.created;
    } catch (_) {
      return AutomaticBackupResult.failed;
    } finally {
      _automaticBackupRunning = false;
    }
  }

  bool _automaticBackupDue(AppSettings settings, DateTime now) {
    final lastBackupAt = _parseIsoDate(settings.lastAutomaticBackupAt);
    if (lastBackupAt == null) {
      return true;
    }
    return !now
        .toUtc()
        .isBefore(lastBackupAt.toUtc().add(_automaticBackupInterval));
  }

  DateTime? _parseIsoDate(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
  }

  String _automaticBackupId(DateTime now) {
    final local = now.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }

  String _automaticBackupSignature(FleetState snapshot) {
    final settingsJson = Map<String, dynamic>.from(
      snapshot.appSettings.toJson(),
    )
      ..remove('lastAutomaticBackupAt')
      ..remove('lastAutomaticBackupSignature');
    final raw = jsonEncode({
      'aircraft': [for (final item in snapshot.aircraft) item.toJson()],
      'flights': [for (final item in snapshot.flights) item.toJson()],
      'batteries': [for (final item in snapshot.batteries) item.toJson()],
      'pilotProfile': snapshot.pilotProfile.toJson(),
      'appSettings': settingsJson,
    });
    return _stableChecksum(raw);
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

String _stableChecksum(String value) {
  var hash = 0x811c9dc5;
  for (final codeUnit in value.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

String _memberDisplayNameFor(User user, PilotProfile profile) {
  final authName = user.displayName?.trim();
  if (authName != null && authName.isNotEmpty) {
    return authName;
  }
  final profileName = profile.name.trim();
  if (profileName.isNotEmpty) {
    return profileName;
  }
  return user.email ?? 'Mitglied';
}

Future<String?> _memberPhotoSourceFor(User user, PilotProfile profile) async {
  final thumbnail = profile.memberPhotoSource?.trim();
  if (thumbnail != null && thumbnail.isNotEmpty) {
    return thumbnail;
  }
  final embeddedPhoto = profile.photoDataUri?.trim();
  if (embeddedPhoto != null && embeddedPhoto.isNotEmpty) {
    return createImageThumbnailDataUriFromDataUri(embeddedPhoto);
  }
  final profilePhoto = profile.photoDownloadUrl?.trim();
  if (profilePhoto != null && profilePhoto.isNotEmpty) {
    return _thumbnailFromNetworkImage(profilePhoto);
  }
  final authPhoto = user.photoURL?.trim();
  if (authPhoto != null && authPhoto.isNotEmpty) {
    return _thumbnailFromNetworkImage(authPhoto);
  }
  return null;
}

bool _hasProfilePhoto(User user, PilotProfile profile) {
  final thumbnail = profile.memberPhotoSource?.trim();
  final embeddedPhoto = profile.photoDataUri?.trim();
  final profilePhoto = profile.photoDownloadUrl?.trim();
  final authPhoto = user.photoURL?.trim();
  return (thumbnail != null && thumbnail.isNotEmpty) ||
      (embeddedPhoto != null && embeddedPhoto.isNotEmpty) ||
      (profilePhoto != null && profilePhoto.isNotEmpty) ||
      (authPhoto != null && authPhoto.isNotEmpty);
}

Future<String?> _thumbnailFromNetworkImage(String source) async {
  try {
    final response =
        await http.get(Uri.parse(source)).timeout(const Duration(seconds: 8));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }
    return createImageThumbnailDataUri(response.bodyBytes);
  } catch (_) {
    return null;
  }
}

List<BatteryPack> _batteriesWithAircraftAssignment(
  List<BatteryPack> batteries, {
  required String aircraftId,
  required Iterable<String> selectedBatteryIds,
}) {
  final selectedIds = {
    for (final id in selectedBatteryIds)
      if (id.trim().isNotEmpty) id.trim(),
  };
  return [
    for (final battery in batteries)
      _batteryWithAircraftAssignment(
        battery,
        aircraftId: aircraftId,
        selected: selectedIds.contains(battery.id),
      ),
  ];
}

BatteryPack _batteryWithAircraftAssignment(
  BatteryPack battery, {
  required String aircraftId,
  required bool selected,
}) {
  final ids = [
    for (final id in battery.aircraftIds)
      if (id != aircraftId) id,
  ];
  if (selected) {
    ids.add(aircraftId);
  }
  if (_sameStringList(ids, battery.aircraftIds)) {
    return battery;
  }
  return battery.copyWith(
    assignedAircraftId: ids.isEmpty ? '' : ids.first,
    assignedAircraftIds: List.unmodifiable(ids),
  );
}

bool _sameStringList(List<String> a, List<String> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) {
      return false;
    }
  }
  return true;
}

bool _isOldUntouchedDemoState(FleetState state) {
  final aircraftIds = {for (final aircraft in state.aircraft) aircraft.id};
  final batteryIds = {for (final battery in state.batteries) battery.id};
  final flightIds = {for (final flight in state.flights) flight.id};

  return state.pilotProfile.name == 'Teddy' &&
      !state.appSettings.shareLocationWithFriends &&
      state.aircraft.length == 3 &&
      state.batteries.length == 4 &&
      state.flights.length >= 20 &&
      aircraftIds.containsAll({'asw28', 'extra300', 'quadx4'}) &&
      batteryIds.containsAll({
        'akku-6s-5000-a',
        'akku-6s-5000-b',
        'akku-4s-2200-q1',
        'akku-2s-rx-asw',
      }) &&
      flightIds.contains('f1') &&
      flightIds.contains('f23');
}

FleetState _starterStateForUser() {
  return _starterDemoState.copyWith(isLoaded: true);
}

const _demoSeglerPhotoAsset = 'assets/aircraft/beispiel_segler.png';
const _demoKunstflugPhotoAsset = 'assets/aircraft/beispiel_kunstflieger.png';

FleetState _withStarterDemoModelPhotos(FleetState state) {
  var changed = false;
  final aircraft = [
    for (final item in state.aircraft)
      switch (item.id) {
        'demo-segler' => _withStarterDemoModelPhoto(
            item,
            expectedName: 'Beispiel Segler',
            photoAsset: _demoSeglerPhotoAsset,
            onChanged: () => changed = true,
          ),
        'demo-kunstflug' => _withStarterDemoModelPhoto(
            item,
            expectedName: 'Beispiel Kunstflug',
            photoAsset: _demoKunstflugPhotoAsset,
            onChanged: () => changed = true,
          ),
        _ => item,
      },
  ];

  return changed ? state.copyWith(aircraft: aircraft) : state;
}

AircraftModel _withStarterDemoModelPhoto(
  AircraftModel aircraft, {
  required String expectedName,
  required String photoAsset,
  required void Function() onChanged,
}) {
  if (aircraft.photos.isNotEmpty || aircraft.name.trim() != expectedName) {
    return aircraft;
  }
  onChanged();
  return aircraft.copyWith(
    photoDataUri: null,
    photoDataUris: [photoAsset],
    photoStoragePaths: const [],
    photoDownloadUrls: const [],
  );
}

final _starterDemoState = FleetState(
  appSettings: const AppSettings(
    shareLocationWithFriends: true,
    reachableByChat: true,
    presenceStatus: LocationPresenceStatus.atField,
    timeZone: 'Europe/Berlin',
    distanceUnit: 'km',
    windUnit: 'km/h',
    temperatureUnit: 'Celsius',
    language: 'Deutsch',
  ),
  pilotProfile: const PilotProfile(
    name: '',
    homeAirfield: '',
    flightAreas: [],
    club: '',
    licenseNumber: '',
    phone: '',
    email: '',
    transmitters: [],
    notes: '',
  ),
  aircraft: [
    AircraftModel(
      id: 'demo-segler',
      name: 'Beispiel Segler',
      type: 'Segelflugzeug',
      manufacturer: 'Beispiel',
      registration: '',
      wingspanMeters: 2.4,
      lengthMeters: 1.18,
      weightKg: 2.1,
      transmitter: 'Mein Sender',
      transmitterMemorySlot: 'SEG-01',
      receiver: 'Beispiel RX',
      propeller: 'Klapp 12x6',
      materialFuselageWing: 'GFK / Schaum',
      wingLoading: '42 g/dm2',
      recommendedDriveBattery: '3S 2200 mAh LiPo',
      servos: '4x Standard-Micro',
      purchaseDate: DateTime(2026, 5, 1),
      drive: 'Elektrosegler',
      batteryCount: 3,
      batteryCellOptions: const [3],
      totalFlights: 1,
      flightHours: 25 / 60,
      status: AircraftStatus.ready,
      lastService: DateTime(2026, 5, 1),
      nextService: DateTime(2026, 7, 1),
      photoDataUris: const [_demoSeglerPhotoAsset],
      notes:
          'Beispielmodell: Hier kannst du spaeter dein eigenes Segelflugzeug eintragen.',
    ),
    AircraftModel(
      id: 'demo-kunstflug',
      name: 'Beispiel Kunstflug',
      type: 'Kunstflieger',
      manufacturer: 'Beispiel',
      registration: '',
      wingspanMeters: 1.35,
      lengthMeters: 1.25,
      weightKg: 1.9,
      transmitter: 'Mein Sender',
      transmitterMemorySlot: 'KUNST-01',
      receiver: 'Beispiel RX',
      propeller: '13x6.5',
      materialFuselageWing: 'Balsa / Folie',
      wingLoading: '55 g/dm2',
      recommendedDriveBattery: '4S 2600 mAh LiPo',
      servos: '4x Digital-Micro',
      purchaseDate: DateTime(2026, 5, 1),
      drive: 'Brushless 4S',
      batteryCount: 4,
      batteryCellOptions: const [4],
      totalFlights: 1,
      flightHours: 9 / 60,
      status: AircraftStatus.ready,
      lastService: DateTime(2026, 5, 1),
      nextService: DateTime(2026, 7, 1),
      photoDataUris: const [_demoKunstflugPhotoAsset],
      notes:
          'Beispielmodell: Nutze diesen Eintrag zum Ausprobieren oder loesche ihn.',
    ),
  ],
  batteries: [
    BatteryPack(
      id: 'demo-akku-1s-450',
      inventoryNumber: 1,
      label: 'Beispiel 1S 450',
      chemistry: 'LiPo',
      cells: 1,
      capacityMah: 450,
      chargePercent: 100,
      cycles: 1,
      status: BatteryStatus.charged,
      purchaseDate: DateTime(2026, 5, 1),
      lastUsed: DateTime(2026, 5, 18),
      assignedAircraftId: '',
      notes: 'Beispielakku fuer kleine Indoor-Modelle.',
    ),
    BatteryPack(
      id: 'demo-akku-2s-850',
      inventoryNumber: 2,
      label: 'Beispiel 2S 850',
      chemistry: 'LiPo',
      cells: 2,
      capacityMah: 850,
      chargePercent: 75,
      cycles: 1,
      status: BatteryStatus.storage,
      purchaseDate: DateTime(2026, 5, 1),
      lastUsed: DateTime(2026, 5, 19),
      assignedAircraftId: '',
      notes: 'Beispielakku fuer Parkflyer oder Empfaenger-Test.',
    ),
    BatteryPack(
      id: 'demo-akku-3s-2200',
      inventoryNumber: 3,
      label: 'Beispiel 3S 2200',
      chemistry: 'LiPo',
      cells: 3,
      capacityMah: 2200,
      chargePercent: 100,
      cycles: 1,
      status: BatteryStatus.charged,
      purchaseDate: DateTime(2026, 5, 1),
      lastUsed: DateTime(2026, 5, 20),
      assignedAircraftId: 'demo-segler',
      assignedAircraftIds: const ['demo-segler'],
      notes: 'Beispielakku fuer den Segler.',
    ),
    BatteryPack(
      id: 'demo-akku-4s-2600',
      inventoryNumber: 4,
      label: 'Beispiel 4S 2600',
      chemistry: 'LiPo',
      cells: 4,
      capacityMah: 2600,
      chargePercent: 62,
      cycles: 1,
      status: BatteryStatus.storage,
      purchaseDate: DateTime(2026, 5, 1),
      lastUsed: DateTime(2026, 5, 21),
      assignedAircraftId: 'demo-kunstflug',
      assignedAircraftIds: const ['demo-kunstflug'],
      notes: 'Beispielakku fuer das Kunstflugmodell.',
    ),
  ],
  flights: [
    FlightLogEntry(
      id: 'demo-flug-segler',
      aircraftId: 'demo-segler',
      date: DateTime(2026, 5, 20, 17, 15),
      location: 'Mein Flugplatz',
      durationMinutes: 25,
      batteryPacks: 1,
      batteryId: 'demo-akku-3s-2200',
      batteryLabel: 'Beispiel 3S 2200',
      pilot: 'Neuer Pilot',
      notes: 'Beispielflug: ruhige Platzrunde und erste Landung.',
    ),
    FlightLogEntry(
      id: 'demo-flug-kunstflug',
      aircraftId: 'demo-kunstflug',
      date: DateTime(2026, 5, 21, 18, 30),
      location: 'Mein Flugplatz',
      durationMinutes: 9,
      batteryPacks: 1,
      batteryId: 'demo-akku-4s-2600',
      batteryLabel: 'Beispiel 4S 2600',
      pilot: 'Neuer Pilot',
      notes: 'Beispielflug: Looping, Rollen und kurze Motorkontrolle.',
    ),
  ],
);

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
