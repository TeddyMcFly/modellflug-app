import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../features/batteries/batteries_page.dart';
import '../../features/dashboard/dashboard_page.dart';
import '../../features/flightbook/flightbook_page.dart';
import '../../features/friends/friends_page.dart';
import '../../features/landing/landing_page.dart';
import '../../features/models/models_page.dart';
import '../../features/settings/settings_page.dart';
import '../../features/statistics/statistics_page.dart';
import '../../features/webcam/webcam_page.dart';

final appRouter = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      pageBuilder: (context, state) => _noTransitionPage(
        state: state,
        child: const LandingPage(),
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
      pageBuilder: (context, state) => _noTransitionPage(
        state: state,
        child: const SettingsPage(),
      ),
    ),
  ],
);

NoTransitionPage<void> _noTransitionPage({
  required GoRouterState state,
  required Widget child,
}) {
  return NoTransitionPage<void>(
    key: state.pageKey,
    child: child,
  );
}
