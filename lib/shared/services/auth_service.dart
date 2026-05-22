import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  return AuthController(ref.watch(firebaseAuthProvider));
});

class AuthController {
  final FirebaseAuth _auth;

  const AuthController(this._auth);

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

  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(code: 'user-not-found');
    }
    await user.sendEmailVerification();
  }

  Future<void> signOut() {
    return _auth.signOut();
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
    'operation-not-allowed' =>
      'E-Mail/Passwort muss in Firebase noch aktiviert werden.',
    'too-many-requests' =>
      'Zu viele Versuche. Bitte warte kurz und probiere es spaeter erneut.',
    'weak-password' =>
      'Das Passwort ist zu schwach. Bitte nutze mindestens 6 Zeichen.',
    _ => 'Die Anmeldung ist fehlgeschlagen: ${error.message ?? error.code}',
  };
}
