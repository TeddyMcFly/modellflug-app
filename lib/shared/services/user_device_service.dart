import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../utils/device_info.dart';

final userDeviceServiceProvider = Provider<UserDeviceService?>((ref) {
  if (Firebase.apps.isEmpty) {
    return null;
  }
  return UserDeviceService(FirebaseFirestore.instance);
});

class UserDeviceService {
  static const _deviceIdKey = 'modellflug_admin_device_id';
  static const _deviceFirstSeenKey = 'modellflug_admin_device_first_seen';
  static const _collectionName = 'deviceAccess';

  final FirebaseFirestore _firestore;

  const UserDeviceService(this._firestore);

  CollectionReference<Map<String, dynamic>> get _deviceAccess {
    return _firestore.collection(_collectionName);
  }

  Future<void> recordCurrentDevice({
    required User user,
    required String displayName,
  }) async {
    final deviceId = await _localDeviceId();
    final firstSeenClient = await _localFirstSeenClient();
    final device = detectCurrentDeviceInfo();
    final nowClient = DateTime.now().toUtc().toIso8601String();
    final cleanName = displayName.trim();
    final email = user.email?.trim();

    await _deviceAccess.doc('${user.uid}_$deviceId').set(
      {
        'uid': user.uid,
        'email': email,
        'displayName': cleanName.isEmpty ? email ?? 'Mitglied' : cleanName,
        'deviceId': deviceId,
        'firstSeenClient': firstSeenClient,
        'lastSeenAt': FieldValue.serverTimestamp(),
        'lastSeenClient': nowClient,
        ...device.toJson(),
      },
      SetOptions(merge: true),
    );
  }

  Stream<List<UserDeviceAccess>> watchDeviceAccess({int limit = 100}) {
    return _deviceAccess
        .orderBy('lastSeenAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => [
            for (final doc in snapshot.docs) UserDeviceAccess.fromSnapshot(doc),
          ],
        );
  }

  Future<String> _localDeviceId() async {
    final preferences = await SharedPreferences.getInstance();
    final existing = preferences.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final deviceId = const Uuid().v4();
    await preferences.setString(_deviceIdKey, deviceId);
    return deviceId;
  }

  Future<String> _localFirstSeenClient() async {
    final preferences = await SharedPreferences.getInstance();
    final existing = preferences.getString(_deviceFirstSeenKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final firstSeen = DateTime.now().toUtc().toIso8601String();
    await preferences.setString(_deviceFirstSeenKey, firstSeen);
    return firstSeen;
  }
}

class UserDeviceAccess {
  final String id;
  final String uid;
  final String displayName;
  final String? email;
  final String deviceId;
  final String deviceLabel;
  final String deviceType;
  final String operatingSystem;
  final String browserLabel;
  final String platform;
  final String language;
  final String screenLabel;
  final String viewportLabel;
  final String userAgent;
  final DateTime? firstSeenAt;
  final DateTime? lastSeenAt;

  const UserDeviceAccess({
    required this.id,
    required this.uid,
    required this.displayName,
    required this.email,
    required this.deviceId,
    required this.deviceLabel,
    required this.deviceType,
    required this.operatingSystem,
    required this.browserLabel,
    required this.platform,
    required this.language,
    required this.screenLabel,
    required this.viewportLabel,
    required this.userAgent,
    required this.firstSeenAt,
    required this.lastSeenAt,
  });

  factory UserDeviceAccess.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final email = (data['email'] as String?)?.trim();
    final name = (data['displayName'] as String? ?? '').trim();

    return UserDeviceAccess(
      id: snapshot.id,
      uid: data['uid'] as String? ?? '',
      displayName: name.isNotEmpty
          ? name
          : email != null && email.isNotEmpty
              ? email
              : 'Mitglied',
      email: email,
      deviceId: data['deviceId'] as String? ?? '',
      deviceLabel: data['deviceLabel'] as String? ?? 'Unbekanntes Geraet',
      deviceType: data['deviceType'] as String? ?? '',
      operatingSystem: data['operatingSystem'] as String? ?? '',
      browserLabel: data['browserLabel'] as String? ?? 'Browser',
      platform: data['platform'] as String? ?? '',
      language: data['language'] as String? ?? '',
      screenLabel: data['screenLabel'] as String? ?? '-',
      viewportLabel: data['viewportLabel'] as String? ?? '-',
      userAgent: data['userAgent'] as String? ?? '',
      firstSeenAt: _dateFromFirestoreValue(data['firstSeenClient']),
      lastSeenAt: _dateFromFirestoreValue(data['lastSeenAt']) ??
          _dateFromFirestoreValue(data['lastSeenClient']),
    );
  }

  String get shortDeviceId {
    if (deviceId.length <= 8) {
      return deviceId;
    }
    return deviceId.substring(0, 8);
  }
}

DateTime? _dateFromFirestoreValue(Object? value) {
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
