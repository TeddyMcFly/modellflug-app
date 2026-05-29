import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/admin_page.dart';
import '../../features/auth/login_page.dart';
import '../../features/batteries/batteries_page.dart';
import '../../features/dashboard/dashboard_page.dart';
import '../../features/flightbook/flightbook_page.dart';
import '../../features/friends/friends_page.dart';
import '../../features/landing/landing_page.dart';
import '../../features/models/models_page.dart';
import '../../features/settings/settings_page.dart';
import '../../features/statistics/statistics_page.dart';
import '../../features/webcam/webcam_page.dart';
import '../../shared/services/admin_access.dart';

GoRouter createAppRouter() {
  return GoRouter(
    refreshListenable: _GoRouterRefreshStream(_authStateChanges()),
    redirect: (context, state) {
      final location = state.matchedLocation;
      final user =
          Firebase.apps.isEmpty ? null : FirebaseAuth.instance.currentUser;
      final signedIn = user != null;
      final publicRoute = location == '/' || location == '/login';

      if (!signedIn && !publicRoute) {
        final from = Uri.encodeComponent(state.uri.toString());
        return '/login?from=$from';
      }

      if (signedIn && location == '/login') {
        return _safeRedirect(state.uri.queryParameters['from']) ?? '/dashboard';
      }

      if (signedIn && location == '/admin' && !isAdminEmail(user.email)) {
        return '/dashboard';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (context, state) => _noTransitionPage(
          state: state,
          child: const LandingPage(),
        ),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => _noTransitionPage(
          state: state,
          child: const LoginPage(),
        ),
      ),
      GoRoute(
        path: '/dashboard',
        pageBuilder: (context, state) => _noTransitionPage(
          state: state,
          child: const DashboardPage(),
        ),
      ),
      GoRoute(
        path: '/models',
        pageBuilder: (context, state) => _noTransitionPage(
          state: state,
          child: ModelsPage(
            initialSelectedAircraftId: state.uri.queryParameters['model'],
          ),
        ),
      ),
      GoRoute(
        path: '/aircraft',
        redirect: (context, state) => '/models',
      ),
      GoRoute(
        path: '/flightbook',
        pageBuilder: (context, state) => _noTransitionPage(
          state: state,
          child: const FlightbookPage(),
        ),
      ),
      GoRoute(
        path: '/friends',
        pageBuilder: (context, state) => _noTransitionPage(
          state: state,
          child: const FriendsPage(),
        ),
      ),
      GoRoute(
        path: '/batteries',
        pageBuilder: (context, state) => _noTransitionPage(
          state: state,
          child: const BatteriesPage(),
        ),
      ),
      GoRoute(
        path: '/statistics',
        pageBuilder: (context, state) => _noTransitionPage(
          state: state,
          child: const StatisticsPage(),
        ),
      ),
      GoRoute(
        path: '/webcam',
        pageBuilder: (context, state) => _noTransitionPage(
          state: state,
          child: const WebcamPage(),
        ),
      ),
      GoRoute(
        path: '/settings',
        onExit: (context, state) => confirmLeaveSettingsProfile(context),
        pageBuilder: (context, state) => _noTransitionPage(
          state: state,
          child: const SettingsPage(),
        ),
      ),
      GoRoute(
        path: '/admin',
        pageBuilder: (context, state) => _noTransitionPage(
          state: state,
          child: const AdminPage(),
        ),
      ),
    ],
  );
}

NoTransitionPage<void> _noTransitionPage({
  required GoRouterState state,
  required Widget child,
}) {
  return NoTransitionPage<void>(
    key: state.pageKey,
    child: child,
  );
}

Stream<User?> _authStateChanges() {
  if (Firebase.apps.isEmpty) {
    return Stream<User?>.value(null);
  }
  return FirebaseAuth.instance.authStateChanges();
}

String? _safeRedirect(String? value) {
  if (value == null || value.isEmpty || value == '/login') {
    return null;
  }
  if (!value.startsWith('/') || value.startsWith('//')) {
    return null;
  }
  return value;
}

class _GoRouterRefreshStream extends ChangeNotifier {
  late final StreamSubscription<dynamic> _subscription;

  _GoRouterRefreshStream(Stream<dynamic> stream) {
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
