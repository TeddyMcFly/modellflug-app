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
      builder: (context, state) => const LandingPage(),
    ),
    GoRoute(
      path: '/dashboard',
      builder: (context, state) => const DashboardPage(),
    ),
    GoRoute(
      path: '/models',
      builder: (context, state) => const ModelsPage(),
    ),
    GoRoute(
      path: '/aircraft',
      redirect: (context, state) => '/models',
    ),
    GoRoute(
      path: '/flightbook',
      builder: (context, state) => const FlightbookPage(),
    ),
    GoRoute(
      path: '/friends',
      builder: (context, state) => const FriendsPage(),
    ),
    GoRoute(
      path: '/batteries',
      builder: (context, state) => const BatteriesPage(),
    ),
    GoRoute(
      path: '/statistics',
      builder: (context, state) => const StatisticsPage(),
    ),
    GoRoute(
      path: '/webcam',
      builder: (context, state) => const WebcamPage(),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsPage(),
    ),
  ],
);
