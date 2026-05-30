import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'fleet_cloud_repository.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final authStateProvider = StreamProvider<User?>((ref) {
  if (Firebase.apps.isEmpty) {
    return Stream<User?>.value(null);
  }
  return ref.watch(firebaseAuthProvider).authStateChanges();
});

final authControllerProvider = Provider<AuthController>((ref) {
  return AuthController(
    ref.watch(firebaseAuthProvider),
    ref.watch(fleetCloudRepositoryProvider),
  );
});

class AuthController {
  final FirebaseAuth _auth;
  final FleetCloudRepository? _cloudRepository;

  const AuthController(this._auth, this._cloudRepository);

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final trimmedName = displayName.trim();
    if (trimmedName.isNotEmpty) {
      await credential.user?.updateDisplayName(trimmedName);
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    final email = user?.email?.trim();
    if (user == null) {
      throw FirebaseAuthException(code: 'user-not-found');
    }
    if (email == null || email.isEmpty) {
      throw FirebaseAuthException(code: 'missing-email');
    }

    final credential = EmailAuthProvider.credential(
      email: email,
      password: currentPassword,
    );
    await user.reauthenticateWithCredential(credential);
    await user.updatePassword(newPassword);
  }

  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(code: 'user-not-found');
    }
    await user.reload();
    final refreshedUser = _auth.currentUser;
    if (refreshedUser == null) {
      throw FirebaseAuthException(code: 'user-not-found');
    }
    if (refreshedUser.emailVerified) {
      return;
    }
    await refreshedUser.sendEmailVerification();
  }

  Future<User?> reloadCurrentUser() async {
    final user = _auth.currentUser;
    if (user == null) {
      return null;
    }
    await user.reload();
    return _auth.currentUser;
  }

  Future<void> signOut() async {
    final user = _auth.currentUser;
    if (user != null) {
      try {
        await _cloudRepository?.markPresenceOffline(user);
      } catch (_) {
        // Abmelden soll trotzdem funktionieren, auch wenn Firebase kurz hakt.
      }
    }
    await _auth.signOut();
  }
}

String authErrorMessage(Object error) {
  if (error is! FirebaseAuthException) {
    return 'Die Anmeldung ist fehlgeschlagen. Bitte versuche es erneut.';
  }

  return switch (error.code) {
    'email-already-in-use' => 'Diese E-Mail-Adresse hat bereits ein Konto.',
    'invalid-email' => 'Bitte gib eine gueltige E-Mail-Adresse ein.',
    'invalid-credential' ||
    'user-not-found' ||
    'wrong-password' =>
      'E-Mail oder Passwort passt nicht.',
    'network-request-failed' =>
      'Firebase ist gerade nicht erreichbar. Bitte pruefe die Internetverbindung.',
    'missing-email' => 'Fuer dieses Konto fehlt die E-Mail-Adresse.',
    'operation-not-allowed' =>
      'E-Mail/Passwort muss in Firebase noch aktiviert werden.',
    'requires-recent-login' =>
      'Bitte melde dich neu an und versuche es dann noch einmal.',
    'too-many-requests' =>
      'Zu viele Versuche. Bitte warte kurz und probiere es spaeter erneut.',
    'weak-password' =>
      'Das Passwort ist zu schwach. Bitte nutze mindestens 6 Zeichen.',
    _ => 'Die Anmeldung ist fehlgeschlagen: ${error.message ?? error.code}',
  };
}
