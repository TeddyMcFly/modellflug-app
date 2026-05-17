import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../shared/models/aircraft_model.dart';
import '../../shared/providers/fleet_provider.dart';

const _appVersion = '1.0.0+1';
const _navigationColor = Color(0xFF06172E);
const _accentColor = Color(0xFF0A84FF);
const _activeNavColor = Color(0xFF0EA5E9);
const _pageBackgroundColor = Color(0xFFE8EDF3);

class AppScaffold extends ConsumerWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;
  final Widget? action;
  final double titleFontSize;

  const AppScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.action,
    this.titleFontSize = 21,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routeState = GoRouterState.of(context);
    final location = routeState.matchedLocation;
    final fleet = ref.watch(fleetProvider);
    final pilotProfile = fleet.pilotProfile;

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
                    child: SingleChildScrollView(
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
                            action: action,
                            titleFontSize: titleFontSize,
                          ),
                          const SizedBox(height: 12),
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

class _PageHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final PilotProfile pilotProfile;
  final Widget? action;
  final double titleFontSize;

  const _PageHeader({
    required this.title,
    required this.subtitle,
    required this.pilotProfile,
    this.action,
    required this.titleFontSize,
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

          final headerTools = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (action != null) ...[
                action!,
                const SizedBox(width: 12),
              ],
              _HeaderSunsetBadge(homeAirfield: pilotProfile.homeAirfield),
              const SizedBox(width: 12),
              _HeaderPilotAvatar(photoDataUri: pilotProfile.photoDataUri),
              const SizedBox(width: 12),
              _HeaderWeatherBadge(homeAirfield: pilotProfile.homeAirfield),
            ],
          );

          if (constraints.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleBlock,
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: headerTools,
                  ),
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

class _HeaderSunsetBadge extends StatelessWidget {
  final String homeAirfield;

  const _HeaderSunsetBadge({required this.homeAirfield});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Sonnenuntergang am $homeAirfield',
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wb_twilight_rounded, color: Color(0xFFF59E0B), size: 21),
          SizedBox(width: 7),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '21:17',
                style: TextStyle(
                  color: _navigationColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                'Sonnenuntergang',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
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

  const _HeaderPilotAvatar({required this.photoDataUri});

  @override
  Widget build(BuildContext context) {
    final photo = photoDataUri;

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _accentColor, width: 2),
      ),
      child: ClipOval(
        child: photo == null || photo.isEmpty
            ? Container(
                color: _accentColor.withValues(alpha: 0.14),
                child: const Icon(
                  Icons.person_rounded,
                  color: _navigationColor,
                  size: 26,
                ),
              )
            : Image.memory(
                _bytesFromDataUri(photo),
                fit: BoxFit.cover,
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

  const _HeaderWeatherBadge({required this.homeAirfield});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Wetter am $homeAirfield',
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wb_cloudy_rounded, color: _accentColor, size: 19),
          SizedBox(width: 7),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '19 C',
                style: TextStyle(
                  color: _navigationColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                'SW 12 km/h',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
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

class _SideNav extends StatelessWidget {
  final String location;
  final PilotProfile pilotProfile;
  final AppSettings appSettings;

  const _SideNav({
    required this.location,
    required this.pilotProfile,
    required this.appSettings,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _BrandBlock(),
          const SizedBox(height: 12),
          const _NavigationDateClock(),
          const SizedBox(height: 12),
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
            label: 'Webcam',
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
          const SizedBox(height: 12),
          const _StatusBadge(),
        ],
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
          _PilotAvatar(photoDataUri: profile.photoDataUri),
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
  const _NavigationDateClock();

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
    final formattedDate = DateFormat('dd.MM.yyyy HH:mm').format(_now);

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

class _AppVersionLabel extends StatelessWidget {
  const _AppVersionLabel();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Version $_appVersion',
      textAlign: TextAlign.center,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
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
            : Image.memory(
                _bytesFromDataUri(photo),
                fit: BoxFit.cover,
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _BrandIcon(),
          SizedBox(height: 7),
          Text(
            'Modellflug-App',
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
    return const SizedBox(
      width: 68,
      height: 46,
      child: CustomPaint(
        painter: _BrandIconPainter(),
        child: Center(
          child: Icon(
            Icons.airplanemode_active_rounded,
            color: Colors.white,
            size: 25,
          ),
        ),
      ),
    );
  }
}

class _BrandIconPainter extends CustomPainter {
  const _BrandIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final ringPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.96)
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke;

    void drawWing({
      required bool left,
      required double top,
      required double outerInset,
      required double inner,
      required double thickness,
      required double alpha,
    }) {
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: alpha)
        ..style = PaintingStyle.fill;
      final path = Path();

      if (left) {
        path
          ..moveTo(size.width * outerInset, size.height * top)
          ..lineTo(size.width * inner, size.height * top)
          ..lineTo(
              size.width * (inner - 0.055), size.height * (top + thickness))
          ..lineTo(
            size.width * (outerInset + 0.075),
            size.height * (top + thickness),
          )
          ..close();
      } else {
        path
          ..moveTo(size.width * (1 - inner), size.height * top)
          ..lineTo(size.width * (1 - outerInset), size.height * top)
          ..lineTo(
            size.width * (1 - outerInset - 0.075),
            size.height * (top + thickness),
          )
          ..lineTo(
            size.width * (1 - inner + 0.055),
            size.height * (top + thickness),
          )
          ..close();
      }

      canvas.drawPath(path, paint);
    }

    for (final side in [true, false]) {
      drawWing(
        left: side,
        top: 0.31,
        outerInset: 0.00,
        inner: 0.42,
        thickness: 0.12,
        alpha: 0.94,
      );
      drawWing(
        left: side,
        top: 0.48,
        outerInset: 0.035,
        inner: 0.38,
        thickness: 0.11,
        alpha: 0.82,
      );
      drawWing(
        left: side,
        top: 0.64,
        outerInset: 0.075,
        inner: 0.34,
        thickness: 0.09,
        alpha: 0.68,
      );
    }

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: size.height * 0.37),
      -2.65,
      5.3,
      false,
      ringPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _BrandIconPainter oldDelegate) => false;
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
              label: 'Webcam',
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
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => context.go(path),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
      child: ChoiceChip(
        selected: selected,
        avatar: Icon(
          icon,
          size: 18,
          color: selected ? Colors.white : const Color(0xFFBFDBFE),
        ),
        label: Text(label),
        labelStyle: TextStyle(
          color: selected ? Colors.white : const Color(0xFFE0F2FE),
          fontWeight: FontWeight.w800,
        ),
        selectedColor: _activeNavColor,
        backgroundColor: Colors.white.withValues(alpha: 0.08),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        onSelected: (_) => context.go(path),
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
  const _StatusBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: const Row(
        children: [
          Icon(Icons.cloud_done_rounded, color: Color(0xFF4ADE80)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Lokaler Bestand aktiv',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

Uint8List _bytesFromDataUri(String dataUri) {
  final commaIndex = dataUri.indexOf(',');
  final encoded =
      commaIndex == -1 ? dataUri : dataUri.substring(commaIndex + 1);
  return base64Decode(encoded);
}
