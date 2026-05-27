import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_service.dart';

const _programOwnerEmails = {'teddroste@me.com'};

bool _isProgramOwnerEmail(String? email) {
  final normalized = email?.trim().toLowerCase();
  return normalized != null && _programOwnerEmails.contains(normalized);
}

final subscriptionServiceProvider = Provider<SubscriptionService?>((ref) {
  if (Firebase.apps.isEmpty) {
    return null;
  }
  return SubscriptionService(FirebaseFirestore.instance);
});

final accountAccessProvider = StreamProvider<AccountAccess>((ref) {
  final authState = ref.watch(authStateProvider);
  final user = authState.valueOrNull;
  final service = ref.watch(subscriptionServiceProvider);

  if (user == null) {
    return Stream.value(AccountAccess.signedOut());
  }
  if (service == null) {
    return Stream.value(AccountAccess.localDevelopment());
  }

  return service.watchAccountAccess(user);
});

enum AccountAccessStatus {
  signedOut,
  localDevelopment,
  owner,
  trial,
  active,
  activationRequested,
  expired,
}

class AccountAccess {
  static const trialLength = Duration(days: 30);

  final AccountAccessStatus status;
  final DateTime? trialStartedAt;
  final DateTime? trialEndsAt;
  final DateTime? subscriptionEndsAt;
  final DateTime? activationRequestedAt;

  const AccountAccess({
    required this.status,
    this.trialStartedAt,
    this.trialEndsAt,
    this.subscriptionEndsAt,
    this.activationRequestedAt,
  });

  factory AccountAccess.signedOut() {
    return const AccountAccess(status: AccountAccessStatus.signedOut);
  }

  factory AccountAccess.localDevelopment() {
    return const AccountAccess(status: AccountAccessStatus.localDevelopment);
  }

  factory AccountAccess.fromUserData(
    Map<String, dynamic> data, {
    String? userEmail,
  }) {
    final now = DateTime.now().toUtc();
    final rawStatus = data['subscriptionStatus'] as String? ?? 'trial';
    final trialStartedAt = _dateFromFirestoreValue(data['trialStartedAt']) ??
        now.subtract(const Duration(days: 0));
    final trialEndsAt = _dateFromFirestoreValue(data['trialEndsAt']) ??
        trialStartedAt.add(trialLength);
    final subscriptionEndsAt =
        _dateFromFirestoreValue(data['subscriptionEndsAt']);
    final activationRequestedAt =
        _dateFromFirestoreValue(data['activationRequestedAt']) ??
            _dateFromFirestoreValue(data['activationRequestedAtClient']);

    if (_isProgramOwnerEmail(userEmail) || rawStatus == 'owner') {
      return AccountAccess(
        status: AccountAccessStatus.owner,
        trialStartedAt: trialStartedAt,
        trialEndsAt: trialEndsAt,
        subscriptionEndsAt: subscriptionEndsAt,
        activationRequestedAt: activationRequestedAt,
      );
    }

    if (rawStatus == 'active' && !_isPast(subscriptionEndsAt, now)) {
      return AccountAccess(
        status: AccountAccessStatus.active,
        trialStartedAt: trialStartedAt,
        trialEndsAt: trialEndsAt,
        subscriptionEndsAt: subscriptionEndsAt,
        activationRequestedAt: activationRequestedAt,
      );
    }

    if (rawStatus == 'activationRequested') {
      return AccountAccess(
        status: AccountAccessStatus.activationRequested,
        trialStartedAt: trialStartedAt,
        trialEndsAt: trialEndsAt,
        subscriptionEndsAt: subscriptionEndsAt,
        activationRequestedAt: activationRequestedAt,
      );
    }

    if (rawStatus == 'expired') {
      return AccountAccess(
        status: AccountAccessStatus.expired,
        trialStartedAt: trialStartedAt,
        trialEndsAt: trialEndsAt,
        subscriptionEndsAt: subscriptionEndsAt,
        activationRequestedAt: activationRequestedAt,
      );
    }

    if (_isPast(trialEndsAt, now)) {
      return AccountAccess(
        status: AccountAccessStatus.expired,
        trialStartedAt: trialStartedAt,
        trialEndsAt: trialEndsAt,
        subscriptionEndsAt: subscriptionEndsAt,
        activationRequestedAt: activationRequestedAt,
      );
    }

    return AccountAccess(
      status: AccountAccessStatus.trial,
      trialStartedAt: trialStartedAt,
      trialEndsAt: trialEndsAt,
      subscriptionEndsAt: subscriptionEndsAt,
      activationRequestedAt: activationRequestedAt,
    );
  }

  bool get hasFullAccess {
    final now = DateTime.now().toUtc();
    return switch (status) {
      AccountAccessStatus.signedOut => false,
      AccountAccessStatus.localDevelopment => true,
      AccountAccessStatus.owner => true,
      AccountAccessStatus.active => !_isPast(subscriptionEndsAt, now),
      AccountAccessStatus.trial ||
      AccountAccessStatus.activationRequested =>
        !_isPast(trialEndsAt, now),
      AccountAccessStatus.expired => false,
    };
  }

  bool get isExpired => !hasFullAccess;

  bool get shouldShowNotice {
    if (status == AccountAccessStatus.localDevelopment ||
        status == AccountAccessStatus.owner ||
        status == AccountAccessStatus.signedOut) {
      return false;
    }
    return status == AccountAccessStatus.expired ||
        status == AccountAccessStatus.activationRequested ||
        trialDaysRemaining <= 7;
  }

  bool get canRequestActivation {
    return status == AccountAccessStatus.trial ||
        status == AccountAccessStatus.expired;
  }

  int get trialDaysRemaining {
    final endsAt = trialEndsAt;
    if (endsAt == null) {
      return 0;
    }
    final remaining = endsAt.toUtc().difference(DateTime.now().toUtc());
    if (remaining.isNegative) {
      return 0;
    }
    final days = (remaining.inHours / 24).ceil();
    return days < 1 ? 1 : days;
  }

  String get title {
    return switch (status) {
      AccountAccessStatus.signedOut => 'Kein Konto aktiv',
      AccountAccessStatus.localDevelopment => 'Lokale Entwicklung',
      AccountAccessStatus.owner => 'Programmbesitzer',
      AccountAccessStatus.trial => 'Testversion',
      AccountAccessStatus.active => 'Bezahlversion aktiv',
      AccountAccessStatus.activationRequested => 'Freischaltung angefragt',
      AccountAccessStatus.expired => 'Testzeit abgelaufen',
    };
  }

  String get detail {
    return switch (status) {
      AccountAccessStatus.signedOut =>
        'Bitte anmelden, damit die Testzeit geprueft werden kann.',
      AccountAccessStatus.localDevelopment =>
        'Firebase ist nicht aktiv. Die App bleibt lokal frei nutzbar.',
      AccountAccessStatus.owner =>
        'Dein Besitzerkonto bleibt dauerhaft freigeschaltet.',
      AccountAccessStatus.trial => 'Noch $trialDaysRemaining Tage Testzeit.',
      AccountAccessStatus.active => subscriptionEndsAt == null
          ? 'Dein Konto ist dauerhaft freigeschaltet.'
          : 'Freigeschaltet bis ${_formatDate(subscriptionEndsAt!)}.',
      AccountAccessStatus.activationRequested => hasFullAccess
          ? 'Anfrage ist gespeichert. Bis zum Testende bleibt die App nutzbar.'
          : 'Anfrage ist gespeichert. Nach Freischaltung ist Bearbeiten wieder moeglich.',
      AccountAccessStatus.expired =>
        'Daten ansehen und exportieren bleibt moeglich. Bearbeiten braucht die Bezahlversion.',
    };
  }

  String get compactLabel {
    return switch (status) {
      AccountAccessStatus.trial => 'Testversion: $trialDaysRemaining Tage',
      AccountAccessStatus.active => 'Bezahlversion aktiv',
      AccountAccessStatus.owner => 'Programmbesitzer',
      AccountAccessStatus.activationRequested => 'Freischaltung angefragt',
      AccountAccessStatus.expired => 'Testzeit abgelaufen',
      AccountAccessStatus.localDevelopment => 'Lokal frei nutzbar',
      AccountAccessStatus.signedOut => 'Nicht angemeldet',
    };
  }
}

class SubscriptionService {
  final FirebaseFirestore _firestore;

  const SubscriptionService(this._firestore);

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) {
    return _firestore.collection('users').doc(uid);
  }

  Stream<AccountAccess> watchAccountAccess(User user) async* {
    await ensureTrial(user);
    yield* _userDoc(user.uid).snapshots().map((snapshot) {
      return AccountAccess.fromUserData(
        snapshot.data() ?? const {},
        userEmail: user.email,
      );
    });
  }

  Future<void> ensureTrial(User user) async {
    final userDoc = _userDoc(user.uid);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(userDoc);
      final data = snapshot.data();
      final now = DateTime.now().toUtc();
      if (_isProgramOwnerEmail(user.email)) {
        transaction.set(
          userDoc,
          {
            'email': user.email,
            'displayName': user.displayName,
            'subscriptionStatus': 'owner',
            'subscriptionUpdatedAt': FieldValue.serverTimestamp(),
            'subscriptionUpdatedAtClient': now.toIso8601String(),
          },
          SetOptions(merge: true),
        );
        return;
      }

      final hasTrial = data != null &&
          data['trialStartedAt'] != null &&
          data['trialEndsAt'] != null &&
          data['subscriptionStatus'] != null;

      if (hasTrial) {
        return;
      }

      final trialEndsAt = now.add(AccountAccess.trialLength);
      transaction.set(
        userDoc,
        {
          'email': user.email,
          'displayName': user.displayName,
          'subscriptionStatus': 'trial',
          'trialStartedAt': Timestamp.fromDate(now),
          'trialStartedAtClient': now.toIso8601String(),
          'trialEndsAt': Timestamp.fromDate(trialEndsAt),
          'trialEndsAtClient': trialEndsAt.toIso8601String(),
          'subscriptionUpdatedAt': FieldValue.serverTimestamp(),
          'subscriptionUpdatedAtClient': now.toIso8601String(),
        },
        SetOptions(merge: true),
      );
    });
  }

  Future<void> requestActivation(User user) async {
    final now = DateTime.now().toUtc();
    await _userDoc(user.uid).set(
      {
        'email': user.email,
        'displayName': user.displayName,
        'subscriptionStatus': 'activationRequested',
        'activationRequestedAt': FieldValue.serverTimestamp(),
        'activationRequestedAtClient': now.toIso8601String(),
        'subscriptionUpdatedAt': FieldValue.serverTimestamp(),
        'subscriptionUpdatedAtClient': now.toIso8601String(),
      },
      SetOptions(merge: true),
    );
  }
}

DateTime? _dateFromFirestoreValue(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is Timestamp) {
    return value.toDate().toUtc();
  }
  if (value is DateTime) {
    return value.toUtc();
  }
  if (value is String) {
    return DateTime.tryParse(value)?.toUtc();
  }
  return null;
}

bool _isPast(DateTime? value, DateTime now) {
  if (value == null) {
    return false;
  }
  return now.isAfter(value.toUtc());
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  return '$day.$month.${local.year}';
}
