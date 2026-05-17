import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/widgets/app_scaffold.dart';
import '../webcam/webcam_page.dart';
import '../../shared/models/aircraft_model.dart';
import '../../shared/providers/fleet_provider.dart';

const _dashboardHeadingStyle = TextStyle(
  color: Color(0xFF06172E),
  fontSize: 18,
  fontWeight: FontWeight.w900,
);

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fleet = ref.watch(fleetProvider);

    return AppScaffold(
      title: 'Dashboard',
      subtitle:
          'Flotte, Wartung und letzte Fluege auf einen Blick fuer den naechsten Flugtag.',
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _MetricCard(
              icon: Icons.check_circle_rounded,
              label: 'Flugbereit',
              value: '${fleet.readyCount}',
            ),
            _MetricCard(
              icon: Icons.timelapse_rounded,
              label: 'Gesamtflugzeit',
              value: '${fleet.totalHours.toStringAsFixed(1)} h',
            ),
            _MetricCard(
              icon: Icons.flight_takeoff_rounded,
              label: 'Fluege diese Woche',
              value: '${_weeklyFlightCount(fleet.flights)}',
            ),
            _MetricCard(
              icon: Icons.build_circle_rounded,
              label: 'Wartung offen',
              value: '${fleet.serviceDueCount}',
            ),
            _WeatherForecastCard(fleet: fleet),
          ],
        ),
        const SizedBox(height: 12),
        _ModelPhotoOverview(fleet: fleet),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 920;
            const previewHeight = 375.0;
            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: previewHeight,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 390),
                      child: _LastFlightCard(fleet: fleet),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: previewHeight,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: _HomeAirfieldWebcamCard(fleet: fleet),
                    ),
                  ),
                ],
              );
            }

            return Column(
              children: [
                SizedBox(
                  height: previewHeight,
                  child: _LastFlightCard(fleet: fleet),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: previewHeight,
                  child: _HomeAirfieldWebcamCard(fleet: fleet),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 760;
            final maintenance = ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 390),
              child: _MaintenanceList(fleet: fleet),
            );
            final activeFriends = ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 390),
              child: const _ActiveFriendsCard(),
            );

            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  maintenance,
                  const SizedBox(width: 12),
                  activeFriends,
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                maintenance,
                const SizedBox(height: 12),
                activeFriends,
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ModelPhotoOverview extends StatefulWidget {
  final FleetState fleet;

  const _ModelPhotoOverview({required this.fleet});

  @override
  State<_ModelPhotoOverview> createState() => _ModelPhotoOverviewState();
}

class _ModelPhotoOverviewState extends State<_ModelPhotoOverview> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aircraft = widget.fleet.aircraft;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.airplanemode_active_rounded,
                  color: Color(0xFF0A84FF),
                  size: 28,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Meine Modelle (${widget.fleet.aircraft.length})',
                    style: _dashboardHeadingStyle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (aircraft.isEmpty)
              const Text(
                'Noch keine Modelle angelegt.',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                ),
              )
            else
              SizedBox(
                height: 176,
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  trackVisibility: true,
                  interactive: true,
                  child: ListView.separated(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 12),
                    itemCount: aircraft.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 12),
                    itemBuilder: (context, index) => SizedBox(
                      width: 122,
                      child: _AircraftPhotoTile(aircraft: aircraft[index]),
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

class _AircraftPhotoTile extends StatelessWidget {
  final AircraftModel aircraft;

  const _AircraftPhotoTile({required this.aircraft});

  @override
  Widget build(BuildContext context) {
    final photo = aircraft.photos.isEmpty ? null : aircraft.photos.first;
    final statusColor = _statusColor(aircraft.status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox.square(
            dimension: 108,
            child: photo == null
                ? Container(
                    color: const Color(0xFFE2E8F0),
                    child: const Icon(
                      Icons.flight_rounded,
                      color: Color(0xFF64748B),
                      size: 32,
                    ),
                  )
                : Image.memory(
                    _bytesFromDataUri(photo),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: const Color(0xFFE2E8F0),
                      child: const Icon(
                        Icons.flight_rounded,
                        color: Color(0xFF64748B),
                        size: 32,
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          aircraft.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF06172E),
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${aircraft.status.label} - ${aircraft.flightHours.toStringAsFixed(1)} h',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: statusColor,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _LastFlightCard extends StatelessWidget {
  final FleetState fleet;

  const _LastFlightCard({required this.fleet});

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('dd.MM.yyyy');
    final sortedFlights = [...fleet.flights]
      ..sort((a, b) => b.date.compareTo(a.date));
    final flight = sortedFlights.isEmpty ? null : sortedFlights.first;
    final aircraft = flight == null
        ? (fleet.aircraft.isEmpty ? null : fleet.aircraft.first)
        : _aircraftForFlight(fleet.aircraft, flight.aircraftId);
    final photo = aircraft == null || aircraft.photos.isEmpty
        ? null
        : aircraft.photos.first;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: double.infinity,
                height: 188,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    photo == null
                        ? Container(
                            color: const Color(0xFFE2E8F0),
                            child: const Icon(
                              Icons.flight_takeoff_rounded,
                              color: Color(0xFF64748B),
                              size: 44,
                            ),
                          )
                        : Image.memory(
                            _bytesFromDataUri(photo),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                              color: const Color(0xFFE2E8F0),
                              child: const Icon(
                                Icons.flight_takeoff_rounded,
                                color: Color(0xFF64748B),
                                size: 44,
                              ),
                            ),
                          ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.42),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.08),
                          ],
                        ),
                      ),
                    ),
                    const Positioned(
                      left: 12,
                      top: 10,
                      child: Text(
                        'Letzter Flug',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          shadows: [
                            Shadow(
                              color: Colors.black54,
                              blurRadius: 8,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 64,
              child: flight == null
                  ? const Text(
                      'Noch kein Flug im Flugbuch erfasst.',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _FlightInfoLine(
                                icon: Icons.flight_rounded,
                                text: aircraft?.name ?? 'Unbekanntes Modell',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _FlightInfoLine(
                                icon: Icons.calendar_month_rounded,
                                text: formatter.format(flight.date),
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: _FlightInfoLine(
                                icon: Icons.place_rounded,
                                text: flight.location,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _FlightInfoLine(
                                icon: Icons.timer_rounded,
                                text: '${flight.durationMinutes} Minuten',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
            const Spacer(),
            Center(
              child: SizedBox(
                width: 168,
                child: FilledButton.icon(
                  onPressed: () => context.go('/flightbook'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    textStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  icon: const Icon(Icons.menu_book_rounded, size: 16),
                  label: const Text(
                    'Flugbuch oeffnen',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  AircraftModel? _aircraftForFlight(
    List<AircraftModel> aircraft,
    String aircraftId,
  ) {
    for (final item in aircraft) {
      if (item.id == aircraftId) {
        return item;
      }
    }
    return null;
  }
}

class _FlightInfoLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _FlightInfoLine({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF0A84FF), size: 15),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF334155),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeAirfieldWebcamCard extends StatelessWidget {
  final FleetState fleet;

  const _HomeAirfieldWebcamCard({required this.fleet});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(WebcamPage.livePlaceholderAsset, fit: BoxFit.cover),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.02),
                        Colors.black.withValues(alpha: 0.38),
                      ],
                    ),
                  ),
                ),
                const Positioned(
                  left: 12,
                  top: 12,
                  child: _DashboardLiveBadge(),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Webcam ${fleet.pilotProfile.homeAirfield}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Bahnansicht - letztes Bild vor 18 Sekunden',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Color(0xFFE2E8F0),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: FilledButton.icon(
              onPressed: () => context.go('/webcam'),
              style: FilledButton.styleFrom(
                textStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
              icon: const Icon(Icons.videocam_rounded),
              label: const Text(
                'Webcam oeffnen',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardLiveBadge extends StatelessWidget {
  const _DashboardLiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFDC2626),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, color: Colors.white, size: 9),
          SizedBox(width: 7),
          Text(
            'LIVE',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: IntrinsicWidth(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, color: const Color(0xFF0A84FF), size: 24),
                const SizedBox(width: 8),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WeatherForecastCard extends StatelessWidget {
  final FleetState fleet;

  const _WeatherForecastCard({required this.fleet});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: IntrinsicWidth(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(
                  Icons.wb_cloudy_rounded,
                  color: Color(0xFF0A84FF),
                  size: 24,
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Wettervorhersage',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 1),
                    const Text(
                      '19 C - leicht bewoelkt',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${fleet.pilotProfile.homeAirfield} - SW 12 km/h',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

int _weeklyFlightCount(List<FlightLogEntry> flights) {
  final monday = _currentWeekMonday();
  final nextMonday = monday.add(const Duration(days: 7));

  return flights.where((flight) {
    final flightDay =
        DateTime(flight.date.year, flight.date.month, flight.date.day);
    return !flightDay.isBefore(monday) && flightDay.isBefore(nextMonday);
  }).length;
}

DateTime _currentWeekMonday() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: now.weekday - 1));
}

class _MaintenanceList extends StatelessWidget {
  final FleetState fleet;

  const _MaintenanceList({required this.fleet});

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('dd.MM.yyyy');
    final sorted = [...fleet.aircraft]
      ..sort((a, b) => a.nextService.compareTo(b.nextService));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Naechste Wartungen',
              style: _dashboardHeadingStyle,
            ),
            const SizedBox(height: 10),
            for (final aircraft in sorted)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    _StatusDot(status: aircraft.status),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            aircraft.name,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          Text(
                            formatter.format(aircraft.nextService),
                            style: const TextStyle(color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      aircraft.status.label,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActiveFriendsCard extends StatelessWidget {
  const _ActiveFriendsCard();

  static const _friends = [
    _ActiveFriend(
      name: 'Martin Keller',
      club: 'LMFC Lohburg',
      status: _ActiveFriendStatus.atField,
      flyingModel: 'ASW 28',
      initials: 'MK',
      color: Color(0xFF0A84FF),
    ),
    _ActiveFriend(
      name: 'Sabine Wolf',
      club: 'LMFC Lohburg',
      status: _ActiveFriendStatus.flying,
      flyingModel: 'Slowflyer',
      initials: 'SW',
      color: Color(0xFFEA580C),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Freunde aktiv',
              style: _dashboardHeadingStyle,
            ),
            const SizedBox(height: 10),
            for (final friend in _friends)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: friend.color,
                      child: Text(
                        friend.initials,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            friend.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF06172E),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            friend.flyingModel.isEmpty
                                ? friend.club
                                : '${friend.club} - ${friend.flyingModel}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _ActiveFriendStatusBadge(status: friend.status),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActiveFriend {
  final String name;
  final String club;
  final _ActiveFriendStatus status;
  final String flyingModel;
  final String initials;
  final Color color;

  const _ActiveFriend({
    required this.name,
    required this.club,
    required this.status,
    required this.flyingModel,
    required this.initials,
    required this.color,
  });
}

enum _ActiveFriendStatus {
  atField('Am Platz', Color(0xFFFACC15)),
  flying('Fliegt', Color(0xFF22C55E));

  final String label;
  final Color color;

  const _ActiveFriendStatus(this.label, this.color);
}

class _ActiveFriendStatusBadge extends StatelessWidget {
  final _ActiveFriendStatus status;

  const _ActiveFriendStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: status.color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: status.color.withValues(alpha: 0.38),
                blurRadius: 8,
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          status.label,
          style: const TextStyle(
            color: Color(0xFF334155),
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _StatusDot extends StatelessWidget {
  final AircraftStatus status;

  const _StatusDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      AircraftStatus.ready => const Color(0xFF16A34A),
      AircraftStatus.maintenance => const Color(0xFFEA580C),
      AircraftStatus.destroyed => const Color(0xFFDC2626),
    };

    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

Color _statusColor(AircraftStatus status) {
  return switch (status) {
    AircraftStatus.ready => const Color(0xFF16A34A),
    AircraftStatus.maintenance => const Color(0xFFEA580C),
    AircraftStatus.destroyed => const Color(0xFFDC2626),
  };
}

Uint8List _bytesFromDataUri(String dataUri) {
  final commaIndex = dataUri.indexOf(',');
  final encoded =
      commaIndex == -1 ? dataUri : dataUri.substring(commaIndex + 1);
  return base64Decode(encoded);
}
