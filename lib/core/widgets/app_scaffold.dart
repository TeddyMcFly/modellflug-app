import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../shared/models/aircraft_model.dart';
import '../../shared/providers/app_info_provider.dart';
import '../../shared/providers/fleet_provider.dart';
import '../../shared/services/auth_service.dart';
import '../../shared/services/member_chat_service.dart';
import '../../shared/services/open_meteo_service.dart';
import '../../shared/services/subscription_service.dart';
import '../../shared/utils/media_source.dart';

const _navigationColor = Color(0xFF06172E);
const _accentColor = Color(0xFF0A84FF);
const _activeNavColor = _accentColor;
const _pageBackgroundColor = Color(0xFFF3F5F8);
const _navigationHeaderLogoAsset = 'assets/icons/navigation_header_logo.png';

final _headerChatSummariesProvider =
    StreamProvider.autoDispose.family<List<ChatSummary>, String>((ref, uid) {
  final service = ref.watch(memberChatServiceProvider);
  if (service == null) {
    return Stream.value(const <ChatSummary>[]);
  }
  return service.watchChatSummaries(uid);
});

class AppScaffold extends ConsumerWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;
  final Widget? action;
  final double titleFontSize;
  final String? headerWeatherLocation;

  const AppScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.action,
    this.titleFontSize = 21,
    this.headerWeatherLocation,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routeState = GoRouterState.of(context);
    final location = routeState.matchedLocation;
    final fleet = ref.watch(fleetProvider);
    final accountAccess = ref.watch(accountAccessProvider);
    final subscriptionNotice = accountAccess.maybeWhen(
      data: (value) => value.shouldShowNotice ? value : null,
      orElse: () => null,
    );
    final subscriptionLocked = accountAccess.maybeWhen(
      data: (value) => value.isExpired && _routeRequiresFullAccess(location),
      orElse: () => false,
    );
    final authUser = ref.watch(authStateProvider).maybeWhen(
          data: (user) => user,
          orElse: () => null,
        );
    final userEmail = authUser?.email;
    final pilotProfile = fleet.pilotProfile;
    final weatherLocation = headerWeatherLocation ?? pilotProfile.homeAirfield;
    final headerWeather = ref.watch(
      weatherForecastProvider(
        WeatherQuery(
          location: weatherLocation,
          timeZone: fleet.appSettings.timeZone,
        ),
      ),
    );
    final chatNotifications = authUser == null
        ? const <_HeaderNotification>[]
        : _chatNotifications(
            ref.watch(_headerChatSummariesProvider(authUser.uid)),
            authUser.uid,
          );
    final notifications = _visibleHeaderNotifications(
      fleet,
      headerWeather,
      weatherLocation,
      chatNotifications,
    );

    return Scaffold(
      backgroundColor: _pageBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: _AppShellFrame(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 1020;
                final content = Expanded(
                  child: _ContentFrame(
                    child: _ScrollablePageContent(
                      padding: EdgeInsets.fromLTRB(
                        isWide ? 30 : 16,
                        isWide ? 12 : 10,
                        isWide ? 30 : 16,
                        30,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _PageHeader(
                            title: title,
                            subtitle: subtitle,
                            pilotProfile: pilotProfile,
                            appSettings: fleet.appSettings,
                            weatherLocation: weatherLocation,
                            notifications: notifications,
                            headerWeather: headerWeather,
                            action: subscriptionLocked ? null : action,
                            titleFontSize: titleFontSize,
                            userEmail: userEmail,
                            onSignOut: () => unawaited(_signOut(context, ref)),
                          ),
                          const SizedBox(height: 12),
                          if (subscriptionNotice != null) ...[
                            _SubscriptionAccessBanner(
                              access: subscriptionNotice,
                              onOpenSettings: () => context.go('/settings'),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (subscriptionLocked)
                            _SubscriptionExpiredContent(
                              onOpenSettings: () => context.go('/settings'),
                            )
                          else
                            ...children,
                        ],
                      ),
                    ),
                  ),
                );

                if (isWide) {
                  return Row(
                    children: [
                      _SideNav(
                        location: location,
                        pilotProfile: pilotProfile,
                        appSettings: fleet.appSettings,
                        syncStatus: fleet.syncStatus,
                        userEmail: userEmail,
                      ),
                      content,
                    ],
                  );
                }

                return Column(
                  children: [
                    _TopNav(location: location),
                    content,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    await ref.read(authControllerProvider).signOut();
    if (context.mounted) {
      context.go('/login');
    }
  }
}

bool _routeRequiresFullAccess(String location) {
  return switch (location) {
    '/models' || '/flightbook' || '/batteries' || '/friends' => true,
    _ => false,
  };
}

class _SubscriptionAccessBanner extends StatelessWidget {
  final AccountAccess access;
  final VoidCallback onOpenSettings;

  const _SubscriptionAccessBanner({
    required this.access,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final expired = access.isExpired;
    final color = expired ? const Color(0xFFB91C1C) : const Color(0xFFB45309);
    final background =
        expired ? const Color(0xFFFFF1F2) : const Color(0xFFFFFBEB);
    final border = expired ? const Color(0xFFFECACA) : const Color(0xFFFDE68A);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(
            expired ? Icons.lock_clock_rounded : Icons.hourglass_top_rounded,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  access.compactLabel,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  access.detail,
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: onOpenSettings,
            icon: const Icon(Icons.settings_rounded),
            label: const Text('Einstellungen'),
          ),
        ],
      ),
    );
  }
}

class _SubscriptionExpiredContent extends StatelessWidget {
  final VoidCallback onOpenSettings;

  const _SubscriptionExpiredContent({required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.lock_clock_rounded, color: Color(0xFFB91C1C)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Testzeit abgelaufen',
                      style: TextStyle(
                        color: Color(0xFF06172E),
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'Deine Daten bleiben erhalten. Dashboard, Statistik, Webcam und Einstellungen bleiben sichtbar. Neue Modelle, Fluege, Akkus und Chat-Aenderungen sind nach der Freischaltung wieder moeglich.',
                style: TextStyle(
                  color: Color(0xFF475569),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onOpenSettings,
                icon: const Icon(Icons.workspace_premium_rounded),
                label: const Text('Bezahlversion aktivieren'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppShellFrame extends StatelessWidget {
  final Widget child;

  const _AppShellFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _pageBackgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _navigationColor, width: 6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: child,
      ),
    );
  }
}

class _ContentFrame extends StatelessWidget {
  final Widget child;

  const _ContentFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: _pageBackgroundColor, child: child);
  }
}

class _ScrollablePageContent extends StatefulWidget {
  final EdgeInsetsGeometry padding;
  final Widget child;

  const _ScrollablePageContent({
    required this.padding,
    required this.child,
  });

  @override
  State<_ScrollablePageContent> createState() => _ScrollablePageContentState();
}

class _ScrollablePageContentState extends State<_ScrollablePageContent> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _controller,
      thumbVisibility: true,
      trackVisibility: true,
      interactive: true,
      child: SingleChildScrollView(
        controller: _controller,
        padding: widget.padding,
        child: widget.child,
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final PilotProfile pilotProfile;
  final AppSettings appSettings;
  final String weatherLocation;
  final List<_HeaderNotification> notifications;
  final AsyncValue<OpenMeteoWeather> headerWeather;
  final Widget? action;
  final double titleFontSize;
  final String? userEmail;
  final VoidCallback onSignOut;

  const _PageHeader({
    required this.title,
    required this.subtitle,
    required this.pilotProfile,
    required this.appSettings,
    required this.weatherLocation,
    required this.notifications,
    required this.headerWeather,
    this.action,
    required this.titleFontSize,
    required this.userEmail,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 18),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: _navigationColor.withValues(alpha: 0.14)),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final titleBlock = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: _accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.flight_takeoff_rounded,
                      color: _accentColor,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'VERWALTEN. WARTEN. FLIEGEN.',
                    style: TextStyle(
                      color: _accentColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.w900,
                      color: _navigationColor,
                      letterSpacing: 0,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF475569),
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
              ),
            ],
          );

          final headerToolItems = <Widget>[
            if (action != null) action!,
            _HeaderNotificationButton(notifications: notifications),
            _HeaderSunsetBadge(
              homeAirfield: pilotProfile.homeAirfield,
              weather: headerWeather,
            ),
            _HeaderPilotAvatar(
              photoDataUri: pilotProfile.photoSource,
              email: userEmail,
              onSignOut: onSignOut,
            ),
            _HeaderWeatherBadge(
              homeAirfield: weatherLocation,
              appSettings: appSettings,
              weather: headerWeather,
            ),
          ];

          final headerTools = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < headerToolItems.length; index++) ...[
                if (index > 0) const SizedBox(width: 12),
                headerToolItems[index],
              ],
            ],
          );

          final compactHeaderTools = Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: headerToolItems,
          );

          if (constraints.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleBlock,
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: compactHeaderTools,
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: titleBlock),
              const SizedBox(width: 18),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: headerTools,
              ),
            ],
          );
        },
      ),
    );
  }
}

typedef _HeaderNotification = ({
  String id,
  IconData icon,
  String title,
  String text,
  String time,
});

final Set<String> _dismissedNotificationIds = {};

List<_HeaderNotification> _visibleHeaderNotifications(
  FleetState fleet,
  AsyncValue<OpenMeteoWeather> headerWeather,
  String weatherLocation,
  List<_HeaderNotification> chatNotifications,
) {
  final notifications = [
    ...chatNotifications,
    if (fleet.appSettings.notifyRepairs) ..._repairNotifications(fleet),
    if (fleet.appSettings.notifyBatteryLimits)
      ..._batteryLimitNotifications(fleet),
    if (fleet.appSettings.notifyGoodWeather)
      ..._weatherOpportunityNotifications(
          fleet, headerWeather, weatherLocation),
  ];

  return [
    for (final notification in notifications)
      if (!_dismissedNotificationIds.contains(notification.id)) notification,
  ];
}

List<_HeaderNotification> _chatNotifications(
  AsyncValue<List<ChatSummary>> chatSummaries,
  String currentUid,
) {
  return chatSummaries.maybeWhen(
    data: (chats) {
      final unreadChats = [
        for (final chat in chats)
          if (chat.isUnreadFor(currentUid)) chat,
      ];
      unreadChats.sort((a, b) {
        final aDate = a.lastMessageAt ?? a.updatedAt ?? DateTime(0);
        final bDate = b.lastMessageAt ?? b.updatedAt ?? DateTime(0);
        return bDate.compareTo(aDate);
      });

      return [
        for (final chat in unreadChats)
          (
            id: _chatNotificationId(chat, currentUid),
            icon: Icons.mark_chat_unread_rounded,
            title: _chatNotificationTitle(chat, currentUid),
            text: _chatNotificationText(chat, currentUid),
            time: _chatNotificationTime(chat),
          ),
      ];
    },
    orElse: () => const <_HeaderNotification>[],
  );
}

String _chatNotificationId(ChatSummary chat, String currentUid) {
  final date = chat.lastMessageAt ?? chat.updatedAt;
  final token = date?.toIso8601String() ?? chat.lastMessageFor(currentUid);
  return 'chat-${chat.id}-${chat.unreadCountFor(currentUid)}-$token';
}

String _chatNotificationTitle(ChatSummary chat, String currentUid) {
  if (chat.isDirect) {
    return '${_chatSenderName(chat)} hat geantwortet';
  }
  return 'Neue Nachricht in ${chat.titleFor(currentUid)}';
}

String _chatNotificationText(ChatSummary chat, String currentUid) {
  final room = chat.titleFor(currentUid);
  final message = chat.lastMessageFor(currentUid).trim();
  if (message.isEmpty) {
    return 'In $room wartet eine neue Chatnachricht.';
  }
  return '$room: $message';
}

String _chatNotificationTime(ChatSummary chat) {
  final date = chat.lastMessageAt ?? chat.updatedAt;
  if (date == null) {
    return 'Chat';
  }
  return DateFormat('HH:mm').format(date.toLocal());
}

String _chatSenderName(ChatSummary chat) {
  final name = chat.participantNames[chat.lastSenderId]?.trim();
  if (name != null && name.isNotEmpty) {
    return name;
  }
  return 'Jemand';
}

List<_HeaderNotification> _repairNotifications(FleetState fleet) {
  return [
    for (final aircraft in fleet.aircraft)
      if (aircraft.repairNotes.trim().isNotEmpty)
        (
          id: 'repair-${aircraft.id}-${_stableTextToken(aircraft.repairNotes)}',
          icon: Icons.build_circle_rounded,
          title: 'Reparaturarbeit eingetragen',
          text: '${aircraft.name}: ${aircraft.repairNotes.trim()}',
          time: 'Automatisch',
        ),
  ];
}

List<_HeaderNotification> _weatherOpportunityNotifications(
  FleetState fleet,
  AsyncValue<OpenMeteoWeather> headerWeather,
  String weatherLocation,
) {
  final weather = headerWeather.maybeWhen<OpenMeteoWeather?>(
    data: (weather) => weather,
    orElse: () => null,
  );
  if (weather == null || !hasGoodFlyingWeather(weather)) {
    return const [];
  }

  final now = DateTime.now();
  final dayToken =
      '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  final areas = [
    weatherLocation,
    fleet.pilotProfile.homeAirfield,
    ...fleet.pilotProfile.flightAreas,
  ].where((area) => area.trim().isNotEmpty).toSet().toList();

  if (areas.isEmpty) {
    return const [];
  }

  final area =
      weatherLocation.trim().isNotEmpty ? weatherLocation.trim() : areas.first;
  final wind = formatWindSpeed(
    weather.windSpeedKmh,
    fleet.appSettings.windUnit,
  );
  final gusts = formatWindSpeed(weather.gustsKmh, fleet.appSettings.windUnit);
  return [
    (
      id: 'weather-good-$dayToken-${_stableTextToken(area)}',
      icon: Icons.wb_sunny_rounded,
      title: 'Gute Flugbedingungen',
      text:
          '$area: ${weather.condition}, Wind $wind, Boeen bis $gusts und ${weather.precipitationProbability} % Regenrisiko. Das sieht nach einem guten Flugfenster aus.',
      time: 'Live-Wetter',
    ),
  ];
}

List<_HeaderNotification> _batteryLimitNotifications(FleetState fleet) {
  final settings = fleet.appSettings;
  final now = DateTime.now();
  final notifications = <_HeaderNotification>[];

  for (final battery in fleet.batteries) {
    if (battery.cycles >= settings.batteryProblemCycleThreshold) {
      notifications.add(
        (
          id: 'battery-cycles-${battery.id}-${settings.batteryProblemCycleThreshold}',
          icon: Icons.battery_alert_rounded,
          title: 'Akku-Grenzwert erreicht',
          text:
              '${battery.label}: ${battery.cycles} Zyklen erreicht. Eingestellter Grenzwert: ${settings.batteryProblemCycleThreshold} Zyklen.',
          time: 'Automatisch',
        ),
      );
    }

    final ageYears = _fullYearsSince(battery.purchaseDate, now);
    if (ageYears >= settings.batteryAgeWarningYears) {
      notifications.add(
        (
          id: 'battery-age-${battery.id}-${settings.batteryAgeWarningYears}',
          icon: Icons.schedule_rounded,
          title: 'Akku-Alter pruefen',
          text:
              '${battery.label}: $ageYears Jahre alt. Eingestellter Alters-Hinweis: ${settings.batteryAgeWarningYears} Jahre.',
          time: 'Automatisch',
        ),
      );
    }
  }

  return notifications;
}

String _stableTextToken(String text) {
  var hash = 0;
  for (final unit in text.codeUnits) {
    hash = (hash * 31 + unit) & 0x3fffffff;
  }
  return '${text.trim().length}-$hash';
}

int _fullYearsSince(DateTime start, DateTime now) {
  var years = now.year - start.year;
  if (now.month < start.month ||
      (now.month == start.month && now.day < start.day)) {
    years -= 1;
  }
  return years.clamp(0, 999);
}

class _HeaderNotificationButton extends StatefulWidget {
  final List<_HeaderNotification> notifications;

  const _HeaderNotificationButton({required this.notifications});

  @override
  State<_HeaderNotificationButton> createState() =>
      _HeaderNotificationButtonState();
}

class _HeaderNotificationButtonState extends State<_HeaderNotificationButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bellController;
  late final Animation<double> _bellTurns;
  Set<String> _lastNotificationIds = const {};

  @override
  void initState() {
    super.initState();
    _lastNotificationIds = {
      for (final notification in widget.notifications) notification.id,
    };
    _bellController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _bellTurns = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -0.08), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -0.08, end: 0.08), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 0.08, end: -0.06), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -0.06, end: 0.06), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 0.06, end: 0), weight: 1),
    ]).animate(
      CurvedAnimation(parent: _bellController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(covariant _HeaderNotificationButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextIds = {
      for (final notification in widget.notifications) notification.id,
    };
    final hasNew = nextIds.difference(_lastNotificationIds).isNotEmpty;
    _lastNotificationIds = nextIds;
    if (hasNew && nextIds.isNotEmpty) {
      _bellController
        ..reset()
        ..repeat(count: 6);
    }
  }

  @override
  void dispose() {
    _bellController.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final notifications = widget.notifications;
    final count = notifications.length;
    return Tooltip(
      message: '$count Benachrichtigungen',
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => _showNotificationsDialog(
          context,
          notifications: notifications,
          onDeleted: (ids) {
            setState(() {
              _dismissedNotificationIds.addAll(ids);
            });
            _refresh();
          },
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            RotationTransition(
              turns: _bellTurns,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border:
                      Border.all(color: _accentColor.withValues(alpha: 0.28)),
                ),
                child: const Icon(
                  Icons.notifications_rounded,
                  color: _navigationColor,
                  size: 22,
                ),
              ),
            ),
            if (count > 0)
              Positioned(
                right: -3,
                top: -4,
                child: Container(
                  height: 18,
                  constraints: const BoxConstraints(minWidth: 18),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showNotificationsDialog(
  BuildContext context, {
  required List<_HeaderNotification> notifications,
  required ValueChanged<Set<String>> onDeleted,
}) async {
  final selectedIds = <String>{};
  final hiddenInDialog = <String>{};

  await showDialog<void>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final visibleNotifications = [
            for (var index = 0; index < notifications.length; index++)
              if (!hiddenInDialog.contains(notifications[index].id))
                (index, notifications[index]),
          ];

          return AlertDialog(
            title: const Text('Benachrichtigungen'),
            content: SizedBox(
              width: 460,
              child: visibleNotifications.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Text(
                        'Keine Nachrichten vorhanden.',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var listIndex = 0;
                            listIndex < visibleNotifications.length;
                            listIndex++) ...[
                          _NotificationListTile(
                            notification: visibleNotifications[listIndex].$2,
                            selected: selectedIds.contains(
                              visibleNotifications[listIndex].$2.id,
                            ),
                            onSelectedChanged: (value) {
                              setDialogState(() {
                                final id =
                                    visibleNotifications[listIndex].$2.id;
                                if (value) {
                                  selectedIds.add(id);
                                } else {
                                  selectedIds.remove(id);
                                }
                              });
                            },
                          ),
                          if (listIndex < visibleNotifications.length - 1)
                            const Divider(height: 18),
                        ],
                      ],
                    ),
            ),
            actions: [
              TextButton(
                onPressed: selectedIds.isEmpty
                    ? null
                    : () => setDialogState(() {
                          final ids = {...selectedIds};
                          selectedIds.clear();
                          hiddenInDialog.addAll(ids);
                          onDeleted(ids);
                        }),
                child: const Text('Auswahl loeschen'),
              ),
              TextButton(
                onPressed: visibleNotifications.isEmpty
                    ? null
                    : () => setDialogState(() {
                          final ids = {
                            for (final item in visibleNotifications) item.$2.id,
                          };
                          selectedIds.clear();
                          hiddenInDialog.addAll(ids);
                          onDeleted(ids);
                        }),
                child: const Text('Alles loeschen'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Schliessen'),
              ),
            ],
          );
        },
      );
    },
  );
}

class _NotificationListTile extends StatelessWidget {
  final _HeaderNotification notification;
  final bool selected;
  final ValueChanged<bool> onSelectedChanged;

  const _NotificationListTile({
    required this.notification,
    required this.selected,
    required this.onSelectedChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: selected,
          onChanged: (value) => onSelectedChanged(value ?? false),
        ),
        const SizedBox(width: 4),
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: _accentColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Icon(notification.icon, color: _navigationColor, size: 19),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                notification.title,
                style: const TextStyle(
                  color: _navigationColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                notification.text,
                style: const TextStyle(
                  color: Color(0xFF475569),
                  fontSize: 12,
                  height: 1.25,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                notification.time,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeaderSunsetBadge extends StatelessWidget {
  final String homeAirfield;
  final AsyncValue<OpenMeteoWeather> weather;

  const _HeaderSunsetBadge({
    required this.homeAirfield,
    required this.weather,
  });

  @override
  Widget build(BuildContext context) {
    final sunset = weather.maybeWhen(
      data: (weather) => weather.sunset,
      orElse: () => fallbackWeather(homeAirfield).sunset,
    );
    final sourceLabel = weather.maybeWhen(
      data: (weather) => weather.isLive ? 'Open-Meteo live' : 'Fallback-Daten',
      orElse: () => 'lade Daten',
    );

    return Tooltip(
      message: 'Sonnenuntergang am $homeAirfield',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.wb_twilight_rounded,
            color: Color(0xFFF59E0B),
            size: 21,
          ),
          const SizedBox(width: 7),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                sunset,
                style: const TextStyle(
                  color: _navigationColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                sourceLabel,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF475569),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderPilotAvatar extends StatelessWidget {
  final String? photoDataUri;
  final String? email;
  final VoidCallback onSignOut;

  const _HeaderPilotAvatar({
    required this.photoDataUri,
    required this.email,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final photo = photoDataUri;

    return PopupMenuButton<String>(
      tooltip: 'Konto',
      onSelected: (value) {
        if (value == 'signOut') {
          onSignOut();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: Text(
            email ?? 'Konto',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF334155),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'signOut',
          child: Row(
            children: [
              Icon(Icons.logout_rounded, size: 18),
              SizedBox(width: 8),
              Text('Abmelden'),
            ],
          ),
        ),
      ],
      child: _HeaderPilotAvatarImage(photo: photo),
    );
  }
}

class _HeaderPilotAvatarImage extends StatelessWidget {
  final String? photo;

  const _HeaderPilotAvatarImage({required this.photo});

  @override
  Widget build(BuildContext context) {
    final avatarPhoto = photo;

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _accentColor, width: 2),
      ),
      child: ClipOval(
        child: avatarPhoto == null || avatarPhoto.isEmpty
            ? Container(
                color: _accentColor.withValues(alpha: 0.14),
                child: const Icon(
                  Icons.person_rounded,
                  color: _navigationColor,
                  size: 26,
                ),
              )
            : Image(
                image: mediaImageProvider(avatarPhoto),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: _accentColor.withValues(alpha: 0.14),
                  child: const Icon(
                    Icons.person_rounded,
                    color: _navigationColor,
                    size: 26,
                  ),
                ),
              ),
      ),
    );
  }
}

class _HeaderWeatherBadge extends StatelessWidget {
  final String homeAirfield;
  final AppSettings appSettings;
  final AsyncValue<OpenMeteoWeather> weather;

  const _HeaderWeatherBadge({
    required this.homeAirfield,
    required this.appSettings,
    required this.weather,
  });

  @override
  Widget build(BuildContext context) {
    final data = weather.maybeWhen(
      data: (weather) => weather,
      orElse: () => fallbackWeather(homeAirfield),
    );
    final sourceLabel = weather.maybeWhen(
      data: (weather) => weather.isLive ? 'Live' : 'Fallback',
      orElse: () => 'lade',
    );
    final temperature =
        formatTemperature(data.temperatureC, appSettings.temperatureUnit);
    final wind =
        '${windDirectionLabel(data.windDirection)} ${formatWindSpeed(data.windSpeedKmh, appSettings.windUnit)}';
    final gusts = formatWindSpeed(data.gustsKmh, appSettings.windUnit);
    final visibility =
        formatDistance(data.visibilityKm, appSettings.distanceUnit);
    final locationLabel = _compactWeatherLocationLabel(homeAirfield);

    final detailItems = [
      sourceLabel,
      'Wind $wind',
      'Boeen $gusts',
      'Sicht $visibility',
    ];

    return Tooltip(
      message: 'Wetter am $homeAirfield: ${data.assessment}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(data.assessmentIcon, color: data.assessmentColor, size: 22),
          const SizedBox(width: 7),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 230),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$locationLabel:',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '$temperature  ${data.condition}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _navigationColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 1),
                Wrap(
                  spacing: 7,
                  runSpacing: 1,
                  children: [
                    for (final item in detailItems)
                      Text(
                        item,
                        style: const TextStyle(
                          color: Color(0xFF475569),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _compactWeatherLocationLabel(String location) {
  final trimmed = location.trim();
  if (trimmed.isEmpty) {
    return 'Flugplatz';
  }
  return trimmed;
}

class _SideNav extends StatelessWidget {
  final String location;
  final PilotProfile pilotProfile;
  final AppSettings appSettings;
  final FleetSyncStatus syncStatus;
  final String? userEmail;

  const _SideNav({
    required this.location,
    required this.pilotProfile,
    required this.appSettings,
    required this.syncStatus,
    required this.userEmail,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 230,
      padding: const EdgeInsets.all(10),
      decoration: const BoxDecoration(
        color: _navigationColor,
        border: Border(
          right: BorderSide(color: _navigationColor, width: 6),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _BrandBlock(),
                    const SizedBox(height: 8),
                    _NavigationDateClock(timeZone: appSettings.timeZone),
                    const SizedBox(height: 8),
                    _NavTile(
                      icon: Icons.dashboard_rounded,
                      label: 'Dashboard',
                      path: '/dashboard',
                      location: location,
                    ),
                    _NavTile(
                      icon: Icons.airplanemode_active_rounded,
                      label: 'Modelle',
                      path: '/models',
                      location: location,
                    ),
                    _NavTile(
                      icon: Icons.battery_charging_full_rounded,
                      label: 'Akkus',
                      path: '/batteries',
                      location: location,
                    ),
                    _NavTile(
                      icon: Icons.query_stats_rounded,
                      label: 'Statistiken',
                      path: '/statistics',
                      location: location,
                    ),
                    _NavTile(
                      icon: Icons.videocam_rounded,
                      label: 'Webcams/Wetter',
                      path: '/webcam',
                      location: location,
                    ),
                    _NavTile(
                      icon: Icons.menu_book_rounded,
                      label: 'Flugbuch',
                      path: '/flightbook',
                      location: location,
                    ),
                    _NavTile(
                      icon: Icons.group_rounded,
                      label: 'Freunde',
                      path: '/friends',
                      location: location,
                    ),
                    _NavTile(
                      icon: Icons.tune_rounded,
                      label: 'Einstellungen',
                      path: '/settings',
                      location: location,
                    ),
                    const Spacer(),
                    _PilotNavBadge(
                      profile: pilotProfile,
                      appSettings: appSettings,
                    ),
                    const SizedBox(height: 8),
                    _StatusBadge(
                      syncStatus: syncStatus,
                      userEmail: userEmail,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PilotNavBadge extends StatelessWidget {
  final PilotProfile profile;
  final AppSettings appSettings;

  const _PilotNavBadge({
    required this.profile,
    required this.appSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _PilotAvatar(photoDataUri: profile.photoSource),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (appSettings.shareLocationWithFriends) ...[
                _PresenceDot(status: appSettings.presenceStatus),
                const SizedBox(width: 7),
              ],
              Flexible(
                child: Text(
                  profile.name,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          if (appSettings.shareLocationWithFriends) ...[
            const SizedBox(height: 4),
            Text(
              appSettings.presenceStatus.label,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF93C5FD),
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          const SizedBox(height: 5),
          Text(
            profile.homeAirfield,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFBFDBFE),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          const _AppVersionLabel(),
        ],
      ),
    );
  }
}

class _NavigationDateClock extends StatefulWidget {
  final String timeZone;

  const _NavigationDateClock({required this.timeZone});

  @override
  State<_NavigationDateClock> createState() => _NavigationDateClockState();
}

class _PresenceDot extends StatelessWidget {
  final LocationPresenceStatus status;

  const _PresenceDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      LocationPresenceStatus.offline => const Color(0xFF94A3B8),
      LocationPresenceStatus.atField => const Color(0xFFFACC15),
      LocationPresenceStatus.flying => const Color(0xFF22C55E),
    };

    return Tooltip(
      message: status.label,
      child: Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.45),
              blurRadius: 8,
            ),
          ],
        ),
      ),
    );
  }
}

class _NavigationDateClockState extends State<_NavigationDateClock> {
  late DateTime _now = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clockTime = _timeForConfiguredZone(_now, widget.timeZone);
    final formattedDate = DateFormat('dd.MM.yyyy HH:mm').format(clockTime);

    return SizedBox(
      width: double.infinity,
      height: 28,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.schedule_rounded,
              color: Color(0xFF93C5FD), size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              formattedDate,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFE0F2FE),
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

DateTime _timeForConfiguredZone(DateTime localNow, String timeZone) {
  final utcNow = localNow.toUtc();
  final offset = switch (timeZone) {
    'Europe/Berlin' => const Duration(hours: 2),
    'Europe/London' => const Duration(hours: 1),
    'America/New_York' => const Duration(hours: -4),
    'UTC' => Duration.zero,
    _ => localNow.timeZoneOffset,
  };
  return utcNow.add(offset);
}

class _AppVersionLabel extends ConsumerWidget {
  const _AppVersionLabel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appInfo = ref.watch(appInfoProvider);
    final label = appInfo.maybeWhen(
      data: formatNavigationAppVersion,
      orElse: () => 'Version wird geladen',
    );

    return Text(
      label,
      textAlign: TextAlign.center,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Color(0xFF93C5FD),
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _PilotAvatar extends StatelessWidget {
  final String? photoDataUri;

  const _PilotAvatar({required this.photoDataUri});

  @override
  Widget build(BuildContext context) {
    final photo = photoDataUri;

    return Container(
      width: 70,
      height: 70,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF35A3FF), width: 2),
      ),
      child: ClipOval(
        child: photo == null || photo.isEmpty
            ? Container(
                color: const Color(0xFF0A84FF).withValues(alpha: 0.22),
                child: const Icon(
                  Icons.person_rounded,
                  color: Colors.white,
                  size: 38,
                ),
              )
            : Image(
                image: mediaImageProvider(photo),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: const Color(0xFF0A84FF).withValues(alpha: 0.22),
                  child: const Icon(
                    Icons.person_rounded,
                    color: Colors.white,
                    size: 38,
                  ),
                ),
              ),
      ),
    );
  }
}

class _BrandBlock extends StatelessWidget {
  const _BrandBlock();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _BrandIcon(),
          SizedBox(height: 5),
          Text(
            'Modellflug-Heaven',
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandIcon extends StatelessWidget {
  const _BrandIcon();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      _navigationHeaderLogoAsset,
      width: 104,
      height: 44,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: 'Modellflug-Heaven',
    );
  }
}

class _TopNav extends StatelessWidget {
  final String location;

  const _TopNav({required this.location});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        color: _navigationColor,
        border: Border(
          bottom: BorderSide(color: _navigationColor, width: 6),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _NavChip(
              icon: Icons.dashboard_rounded,
              label: 'Dashboard',
              path: '/dashboard',
              location: location,
            ),
            _NavChip(
              icon: Icons.airplanemode_active_rounded,
              label: 'Modelle',
              path: '/models',
              location: location,
            ),
            _NavChip(
              icon: Icons.battery_charging_full_rounded,
              label: 'Akkus',
              path: '/batteries',
              location: location,
            ),
            _NavChip(
              icon: Icons.query_stats_rounded,
              label: 'Statistiken',
              path: '/statistics',
              location: location,
            ),
            _NavChip(
              icon: Icons.videocam_rounded,
              label: 'Webcams/Wetter',
              path: '/webcam',
              location: location,
            ),
            _NavChip(
              icon: Icons.menu_book_rounded,
              label: 'Flugbuch',
              path: '/flightbook',
              location: location,
            ),
            _NavChip(
              icon: Icons.group_rounded,
              label: 'Freunde',
              path: '/friends',
              location: location,
            ),
            _NavChip(
              icon: Icons.tune_rounded,
              label: 'Einstellungen',
              path: '/settings',
              location: location,
            ),
          ],
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String path;
  final String location;

  const _NavTile({
    required this.icon,
    required this.label,
    required this.path,
    required this.location,
  });

  @override
  Widget build(BuildContext context) {
    final selected = _isSelectedLocation(location, path);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          hoverColor: Colors.white.withValues(alpha: 0.05),
          onTap: selected ? null : () => context.go(path),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? _activeNavColor : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? Colors.white.withValues(alpha: 0.36)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: selected ? Colors.white : const Color(0xFFBFDBFE),
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.white : const Color(0xFFE0F2FE),
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String path;
  final String location;

  const _NavChip({
    required this.icon,
    required this.label,
    required this.path,
    required this.location,
  });

  @override
  Widget build(BuildContext context) {
    final selected = _isSelectedLocation(location, path);

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: selected ? null : () => context.go(path),
          borderRadius: BorderRadius.circular(999),
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          hoverColor: Colors.white.withValues(alpha: 0.06),
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? _activeNavColor
                  : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected
                    ? Colors.white.withValues(alpha: 0.36)
                    : Colors.white.withValues(alpha: 0.12),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? Colors.white : const Color(0xFFBFDBFE),
                ),
                const SizedBox(width: 7),
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.white : const Color(0xFFE0F2FE),
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

bool _isSelectedLocation(String location, String path) {
  if (location == path) {
    return true;
  }
  if (path == '/dashboard' && (location == '/' || location.isEmpty)) {
    return true;
  }
  return location.startsWith('$path/');
}

class _StatusBadge extends StatelessWidget {
  final FleetSyncStatus syncStatus;
  final String? userEmail;

  const _StatusBadge({
    required this.syncStatus,
    required this.userEmail,
  });

  @override
  Widget build(BuildContext context) {
    final status = _syncBadgeStatus(syncStatus, userEmail);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: [
          Icon(status.icon, color: status.color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (status.detail != null)
                  Text(
                    status.detail!,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.68),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

({IconData icon, Color color, String title, String? detail}) _syncBadgeStatus(
  FleetSyncStatus syncStatus,
  String? userEmail,
) {
  return switch (syncStatus) {
    FleetSyncStatus.cloudActive => (
        icon: Icons.cloud_done_rounded,
        color: const Color(0xFF4ADE80),
        title: 'Cloud-Sync aktiv',
        detail: userEmail,
      ),
    FleetSyncStatus.syncing => (
        icon: Icons.cloud_sync_rounded,
        color: const Color(0xFF7DD3FC),
        title: 'Cloud wird verbunden',
        detail: userEmail,
      ),
    FleetSyncStatus.cloudPaused => (
        icon: Icons.cloud_off_rounded,
        color: const Color(0xFFFBBF24),
        title: 'Cloud-Sync pausiert',
        detail: 'Lokal gespeichert',
      ),
    FleetSyncStatus.localOnly => (
        icon: Icons.storage_rounded,
        color: const Color(0xFFCBD5E1),
        title: 'Lokaler Bestand aktiv',
        detail: userEmail,
      ),
  };
}
