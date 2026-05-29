import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/aircraft_model.dart';
import '../models/fleet_state.dart';
import 'member_chat_service.dart';

final fleetCloudRepositoryProvider = Provider<FleetCloudRepository?>((ref) {
  if (Firebase.apps.isEmpty) {
    return null;
  }
  return FleetCloudRepository(FirebaseFirestore.instance);
});

class FleetCloudBackup {
  final String id;
  final DateTime? createdAt;
  final String signature;
  final int aircraftCount;
  final int batteryCount;
  final int flightCount;

  const FleetCloudBackup({
    required this.id,
    required this.createdAt,
    required this.signature,
    required this.aircraftCount,
    required this.batteryCount,
    required this.flightCount,
  });

  factory FleetCloudBackup.fromJson({
    required String id,
    required Map<String, dynamic> json,
  }) {
    return FleetCloudBackup(
      id: id,
      createdAt: _dateFromFirestoreValue(json['createdAt']) ??
          _dateFromFirestoreValue(json['createdAtClient']),
      signature: json['signature'] as String? ?? '',
      aircraftCount: json['aircraftCount'] as int? ?? 0,
      batteryCount: json['batteryCount'] as int? ?? 0,
      flightCount: json['flightCount'] as int? ?? 0,
    );
  }
}

class FleetCloudRepository {
  static const schemaVersion = 1;

  final FirebaseFirestore _firestore;

  const FleetCloudRepository(this._firestore);

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) {
    return _firestore.collection('users').doc(uid);
  }

  DocumentReference<Map<String, dynamic>> _memberDoc(String uid) {
    return _firestore.collection('members').doc(uid);
  }

  CollectionReference<Map<String, dynamic>> _aircraft(String uid) {
    return _userDoc(uid).collection('aircraft');
  }

  CollectionReference<Map<String, dynamic>> _batteries(String uid) {
    return _userDoc(uid).collection('batteries');
  }

  CollectionReference<Map<String, dynamic>> _flights(String uid) {
    return _userDoc(uid).collection('flights');
  }

  CollectionReference<Map<String, dynamic>> _automaticBackups(String uid) {
    return _userDoc(uid).collection('backups');
  }

  DocumentReference<Map<String, dynamic>> _pilotProfile(String uid) {
    return _userDoc(uid).collection('profile').doc('current');
  }

  DocumentReference<Map<String, dynamic>> _appSettings(String uid) {
    return _userDoc(uid).collection('settings').doc('current');
  }

  DocumentReference<Map<String, dynamic>> _fleetMeta(String uid) {
    return _userDoc(uid).collection('meta').doc('fleet');
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchFleetMeta(String uid) {
    return _fleetMeta(uid).snapshots(includeMetadataChanges: true);
  }

  Future<FleetState?> loadState(String uid) async {
    final results = await Future.wait([
      _aircraft(uid).get(),
      _batteries(uid).get(),
      _flights(uid).get(),
      _pilotProfile(uid).get(),
      _appSettings(uid).get(),
    ]);

    final aircraftSnapshot = results[0] as QuerySnapshot<Map<String, dynamic>>;
    final batterySnapshot = results[1] as QuerySnapshot<Map<String, dynamic>>;
    final flightSnapshot = results[2] as QuerySnapshot<Map<String, dynamic>>;
    final profileSnapshot =
        results[3] as DocumentSnapshot<Map<String, dynamic>>;
    final settingsSnapshot =
        results[4] as DocumentSnapshot<Map<String, dynamic>>;

    final hasRemoteData = aircraftSnapshot.docs.isNotEmpty ||
        batterySnapshot.docs.isNotEmpty ||
        flightSnapshot.docs.isNotEmpty ||
        profileSnapshot.exists ||
        settingsSnapshot.exists;
    if (!hasRemoteData) {
      return null;
    }

    final aircraft = [
      for (final doc in aircraftSnapshot.docs)
        Map<String, dynamic>.from(doc.data()),
    ]..sort(_compareAircraft);
    final batteries = [
      for (final doc in batterySnapshot.docs)
        Map<String, dynamic>.from(doc.data()),
    ]..sort(_compareBatteries);
    final flights = [
      for (final doc in flightSnapshot.docs)
        Map<String, dynamic>.from(doc.data()),
    ]..sort(_compareFlights);

    return FleetState.fromJson({
      'aircraft': aircraft,
      'batteries': batteries,
      'flights': flights,
      'pilotProfile': profileSnapshot.data() ?? const <String, dynamic>{},
      'appSettings': settingsSnapshot.data() ?? const <String, dynamic>{},
    }).copyWith(isLoaded: true);
  }

  Future<void> saveState({
    required User user,
    required FleetState state,
    bool replaceCollections = false,
  }) async {
    final batch = _firestore.batch();
    _queueUserTouch(batch, user, state);

    if (replaceCollections) {
      await _queueCollectionDeletes(
        batch,
        uid: user.uid,
        aircraftIds: state.aircraft.map((item) => item.id).toSet(),
        batteryIds: state.batteries.map((item) => item.id).toSet(),
        flightIds: state.flights.map((item) => item.id).toSet(),
      );
    }

    for (final aircraft in state.aircraft) {
      batch.set(
        _aircraft(user.uid).doc(aircraft.id),
        _withDocumentMeta(aircraft.toJson()),
        SetOptions(merge: true),
      );
    }
    for (final battery in state.batteries) {
      batch.set(
        _batteries(user.uid).doc(battery.id),
        _withDocumentMeta(battery.toJson()),
        SetOptions(merge: true),
      );
    }
    for (final flight in state.flights) {
      batch.set(
        _flights(user.uid).doc(flight.id),
        _withDocumentMeta(flight.toJson()),
        SetOptions(merge: true),
      );
    }
    batch.set(
      _pilotProfile(user.uid),
      _withDocumentMeta(state.pilotProfile.toJson()),
      SetOptions(merge: true),
    );
    batch.set(
      _appSettings(user.uid),
      _withDocumentMeta(state.appSettings.toJson()),
      SetOptions(merge: true),
    );

    await batch.commit();
  }

  Future<void> saveAircraft({
    required User user,
    required FleetState state,
    required AircraftModel aircraft,
  }) {
    return _writeWithUserTouch(user, state, (batch) {
      batch.set(
        _aircraft(user.uid).doc(aircraft.id),
        _withDocumentMeta(aircraft.toJson()),
        SetOptions(merge: true),
      );
    });
  }

  Future<void> saveBattery({
    required User user,
    required FleetState state,
    required BatteryPack battery,
  }) {
    return _writeWithUserTouch(user, state, (batch) {
      batch.set(
        _batteries(user.uid).doc(battery.id),
        _withDocumentMeta(battery.toJson()),
        SetOptions(merge: true),
      );
    });
  }

  Future<void> saveFlight({
    required User user,
    required FleetState state,
    required FlightLogEntry flight,
    List<AircraftModel> changedAircraft = const [],
    List<BatteryPack> changedBatteries = const [],
  }) {
    return _writeWithUserTouch(user, state, (batch) {
      batch.set(
        _flights(user.uid).doc(flight.id),
        _withDocumentMeta(flight.toJson()),
        SetOptions(merge: true),
      );
      for (final aircraft in changedAircraft) {
        batch.set(
          _aircraft(user.uid).doc(aircraft.id),
          _withDocumentMeta(aircraft.toJson()),
          SetOptions(merge: true),
        );
      }
      for (final battery in changedBatteries) {
        batch.set(
          _batteries(user.uid).doc(battery.id),
          _withDocumentMeta(battery.toJson()),
          SetOptions(merge: true),
        );
      }
    });
  }

  Future<void> savePilotProfile({
    required User user,
    required FleetState state,
  }) {
    return _writeWithUserTouch(user, state, (batch) {
      batch.set(
        _pilotProfile(user.uid),
        _withDocumentMeta(state.pilotProfile.toJson()),
        SetOptions(merge: true),
      );
    });
  }

  Future<void> saveAppSettings({
    required User user,
    required FleetState state,
  }) {
    return _writeWithUserTouch(user, state, (batch) {
      batch.set(
        _appSettings(user.uid),
        _withDocumentMeta(state.appSettings.toJson()),
        SetOptions(merge: true),
      );
    });
  }

  Future<void> saveAutomaticBackup({
    required User user,
    required FleetState state,
    required String backupId,
    required String signature,
  }) {
    return _writeWithUserTouch(user, state, (batch) {
      batch.set(
        _automaticBackups(user.uid).doc(backupId),
        {
          'schemaVersion': schemaVersion,
          'createdAt': FieldValue.serverTimestamp(),
          'createdAtClient': DateTime.now().toUtc().toIso8601String(),
          'signature': signature,
          'aircraftCount': state.aircraft.length,
          'batteryCount': state.batteries.length,
          'flightCount': state.flights.length,
          'state': state.toJson(),
        },
        SetOptions(merge: true),
      );
    });
  }

  Future<List<FleetCloudBackup>> loadAutomaticBackups(
    String uid, {
    int limit = 10,
  }) async {
    final snapshot = await _automaticBackups(uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return [
      for (final doc in snapshot.docs)
        FleetCloudBackup.fromJson(
          id: doc.id,
          json: doc.data(),
        ),
    ];
  }

  Future<FleetState?> loadAutomaticBackupState({
    required String uid,
    required String backupId,
  }) async {
    final snapshot = await _automaticBackups(uid).doc(backupId).get();
    final data = snapshot.data();
    final stateJson = data?['state'];
    if (stateJson is! Map<String, dynamic>) {
      return null;
    }
    return FleetState.fromJson(stateJson);
  }

  Future<void> deleteAircraft({
    required User user,
    required FleetState state,
    required String aircraftId,
    required Iterable<String> deletedFlightIds,
  }) {
    return _writeWithUserTouch(user, state, (batch) {
      batch.delete(_aircraft(user.uid).doc(aircraftId));
      for (final flightId in deletedFlightIds) {
        batch.delete(_flights(user.uid).doc(flightId));
      }
      for (final battery in state.batteries) {
        batch.set(
          _batteries(user.uid).doc(battery.id),
          _withDocumentMeta(battery.toJson()),
          SetOptions(merge: true),
        );
      }
    });
  }

  Future<void> deleteBattery({
    required User user,
    required FleetState state,
    required String batteryId,
  }) {
    return _writeWithUserTouch(user, state, (batch) {
      batch.delete(_batteries(user.uid).doc(batteryId));
    });
  }

  Future<void> deleteFlight({
    required User user,
    required FleetState state,
    required String flightId,
    required List<AircraftModel> changedAircraft,
    List<BatteryPack> changedBatteries = const [],
  }) {
    return _writeWithUserTouch(user, state, (batch) {
      batch.delete(_flights(user.uid).doc(flightId));
      for (final aircraft in changedAircraft) {
        batch.set(
          _aircraft(user.uid).doc(aircraft.id),
          _withDocumentMeta(aircraft.toJson()),
          SetOptions(merge: true),
        );
      }
      for (final battery in changedBatteries) {
        batch.set(
          _batteries(user.uid).doc(battery.id),
          _withDocumentMeta(battery.toJson()),
          SetOptions(merge: true),
        );
      }
    });
  }

  Future<void> _writeWithUserTouch(
    User user,
    FleetState state,
    void Function(WriteBatch batch) queueWrites,
  ) async {
    final batch = _firestore.batch();
    _queueUserTouch(batch, user, state);
    queueWrites(batch);
    await batch.commit();
  }

  void _queueUserTouch(WriteBatch batch, User user, FleetState state) {
    final now = DateTime.now().toUtc().toIso8601String();
    final publicName = _publicNameFor(user, state);
    final publicPhotoSource = _publicPhotoSourceFor(state);
    final hasProfilePhoto = _hasProfilePhoto(user, state);
    final userData = <String, dynamic>{
      'email': user.email,
      'displayName': user.displayName,
      'publicName': publicName,
      'club': state.pilotProfile.club.trim(),
      'reachableByChat': state.appSettings.reachableByChat,
      'shareLocation': state.appSettings.shareLocationWithFriends,
      'presenceStatus': state.appSettings.shareLocationWithFriends
          ? state.appSettings.presenceStatus.name
          : 'offline',
      'lastSeen': FieldValue.serverTimestamp(),
      'lastSeenClient': now,
      'schemaVersion': schemaVersion,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedAtClient': now,
    };
    final memberData = <String, dynamic>{
      'uid': user.uid,
      'active': true,
      'memberSchemaVersion': MemberChatService.memberSchemaVersion,
      'displayName': publicName,
      'displayNameLower': publicName.toLowerCase(),
      'email': user.email,
      'club': state.pilotProfile.club.trim(),
      'reachableByChat': state.appSettings.reachableByChat,
      'shareLocation': state.appSettings.shareLocationWithFriends,
      'presenceStatus': state.appSettings.shareLocationWithFriends
          ? state.appSettings.presenceStatus.name
          : 'offline',
      'lastSeen': FieldValue.serverTimestamp(),
      'lastSeenClient': now,
    };

    if (publicPhotoSource != null && publicPhotoSource.isNotEmpty) {
      userData['photoSource'] = publicPhotoSource;
      memberData['photoSource'] = publicPhotoSource;
    } else if (!hasProfilePhoto) {
      userData['photoSource'] = null;
      memberData['photoSource'] = null;
    }

    batch.set(_userDoc(user.uid), userData, SetOptions(merge: true));
    batch.set(_memberDoc(user.uid), memberData, SetOptions(merge: true));
    batch.set(
      _fleetMeta(user.uid),
      {
        'schemaVersion': schemaVersion,
        'aircraftCount': state.aircraft.length,
        'batteryCount': state.batteries.length,
        'flightCount': state.flights.length,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedAtClient': now,
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _queueCollectionDeletes(
    WriteBatch batch, {
    required String uid,
    required Set<String> aircraftIds,
    required Set<String> batteryIds,
    required Set<String> flightIds,
  }) async {
    final snapshots = await Future.wait([
      _aircraft(uid).get(),
      _batteries(uid).get(),
      _flights(uid).get(),
    ]);

    final aircraftSnapshot = snapshots[0];
    for (final doc in aircraftSnapshot.docs) {
      if (!aircraftIds.contains(doc.id)) {
        batch.delete(doc.reference);
      }
    }

    final batterySnapshot = snapshots[1];
    for (final doc in batterySnapshot.docs) {
      if (!batteryIds.contains(doc.id)) {
        batch.delete(doc.reference);
      }
    }

    final flightSnapshot = snapshots[2];
    for (final doc in flightSnapshot.docs) {
      if (!flightIds.contains(doc.id)) {
        batch.delete(doc.reference);
      }
    }
  }
}

String _publicNameFor(User user, FleetState state) {
  final authName = user.displayName?.trim();
  if (authName != null && authName.isNotEmpty) {
    return authName;
  }
  final profileName = state.pilotProfile.name.trim();
  if (profileName.isNotEmpty) {
    return profileName;
  }
  return user.email ?? 'Mitglied';
}

String? _publicPhotoSourceFor(FleetState state) {
  final thumbnail = state.pilotProfile.memberPhotoSource?.trim();
  if (thumbnail != null && thumbnail.isNotEmpty) {
    return thumbnail;
  }
  return null;
}

bool _hasProfilePhoto(User user, FleetState state) {
  final thumbnail = state.pilotProfile.memberPhotoSource?.trim();
  final embeddedPhoto = state.pilotProfile.photoDataUri?.trim();
  final downloadUrl = state.pilotProfile.photoDownloadUrl?.trim();
  final authPhoto = user.photoURL?.trim();
  return (thumbnail != null && thumbnail.isNotEmpty) ||
      (embeddedPhoto != null && embeddedPhoto.isNotEmpty) ||
      (downloadUrl != null && downloadUrl.isNotEmpty) ||
      (authPhoto != null && authPhoto.isNotEmpty);
}

Map<String, dynamic> _withDocumentMeta(Map<String, dynamic> data) {
  return {
    ...data,
    'updatedAt': FieldValue.serverTimestamp(),
    'updatedAtClient': DateTime.now().toUtc().toIso8601String(),
  };
}

int _compareAircraft(Map<String, dynamic> a, Map<String, dynamic> b) {
  return (a['name'] as String? ?? '').compareTo(b['name'] as String? ?? '');
}

int _compareBatteries(Map<String, dynamic> a, Map<String, dynamic> b) {
  final aNumber = a['inventoryNumber'] as int? ?? 0;
  final bNumber = b['inventoryNumber'] as int? ?? 0;
  if (aNumber != bNumber) {
    return aNumber.compareTo(bNumber);
  }
  return (a['label'] as String? ?? '').compareTo(b['label'] as String? ?? '');
}

int _compareFlights(Map<String, dynamic> a, Map<String, dynamic> b) {
  final aDate = DateTime.tryParse(a['date'] as String? ?? '') ?? DateTime(0);
  final bDate = DateTime.tryParse(b['date'] as String? ?? '') ?? DateTime(0);
  return bDate.compareTo(aDate);
}

DateTime? _dateFromFirestoreValue(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    return DateTime.tryParse(value);
  }
  return null;
}
