import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/widgets/app_scaffold.dart';
import '../../shared/models/aircraft_model.dart';
import '../../shared/providers/fleet_provider.dart';
import '../../shared/services/open_meteo_service.dart';
import '../../shared/utils/flight_time_format.dart';
import '../../shared/utils/media_source.dart';
import '../webcam/webcam_page.dart';

const _dashboardHeadingStyle = TextStyle(
  color: Color(0xFF06172E),
  fontSize: 18,
  fontWeight: FontWeight.w900,
);
const _dashboardPreviewCardHeight = 318.0;

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fleet = ref.watch(fleetProvider);

    return AppScaffold(
      title: 'Dashboard',
      subtitle: 'Alles, was wichtig ist fuer einen tollen Flugtag...',
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
              value: formatFlightMinutes(fleet.totalMinutes),
            ),
            _MetricCard(
              icon: Icons.flight_takeoff_rounded,
              label: 'Fluege diese Woche',
              value: '${_weeklyFlightCount(fleet.flights)}',
            ),
            _MetricCard(
              icon: Icons.build_circle_rounded,
              label: 'Reparatur offen',
              value:
                  '${fleet.aircraft.where((item) => item.status == AircraftStatus.maintenance).length}',
              onTap: () => _showRepairInfoDialog(context, fleet.aircraft),
            ),
            const _MetricCard(
              icon: Icons.group_rounded,
              label: 'Freunde aktiv',
              value: '2',
            ),
          ],
        ),
        const SizedBox(height: 12),
        _ModelPhotoOverview(fleet: fleet),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;
            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SizedBox(
                      height: _dashboardPreviewCardHeight,
                      child: _WeatherForecastCard(fleet: fleet),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 340,
                    height: _dashboardPreviewCardHeight,
                    child: _HomeAirfieldWebcamCard(fleet: fleet),
                  ),
                ],
              );
            }

            return Column(
              children: [
                _WeatherForecastCard(fleet: fleet),
                const SizedBox(height: 12),
                Center(
                  child: _HomeAirfieldWebcamCard(fleet: fleet),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 820;
            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: _LastFlightCard(fleet: fleet),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: _TransmitterAssignmentsTable(fleet: fleet)),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: _LastFlightCard(fleet: fleet),
                ),
                const SizedBox(height: 12),
                _TransmitterAssignmentsTable(fleet: fleet),
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
    final aircraft = [
      for (final aircraft in widget.fleet.aircraft)
        if (aircraft.status != AircraftStatus.destroyed) aircraft,
    ];

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
                    'Meine Modelle (${aircraft.length})',
                    style: _dashboardHeadingStyle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (aircraft.isEmpty)
              const Text(
                'Keine aktiven Modelle angelegt.',
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
                      child: _AircraftPhotoTile(
                        aircraft: aircraft[index],
                        flightMinutes: widget.fleet.flightMinutesForAircraft(
                          aircraft[index],
                        ),
                        onTap: () =>
                            context.go('/models?model=${aircraft[index].id}'),
                      ),
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
  final int flightMinutes;
  final VoidCallback onTap;

  const _AircraftPhotoTile({
    required this.aircraft,
    required this.flightMinutes,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final photo = aircraft.photos.isEmpty ? null : aircraft.photos.first;
    final statusColor = _statusColor(aircraft.status);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Column(
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
                      : Image(
                          image: mediaImageProvider(photo),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
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
                '${aircraft.status.label} - ${formatFlightMinutes(flightMinutes)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
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
            Center(
              child: SizedBox(
                width: 336,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    height: 252,
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
                            : Image(
                                image: mediaImageProvider(photo),
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
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: 10,
                          child: flight == null
                              ? const Text(
                                  'Noch kein Flug im Flugbuch erfasst.',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black54,
                                        blurRadius: 8,
                                        offset: Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                )
                              : _LastFlightImageInfo(
                                  aircraftName:
                                      aircraft?.name ?? 'Unbekanntes Modell',
                                  date: formatter.format(flight.date),
                                  location: flight.location,
                                  duration: '${flight.durationMinutes} Minuten',
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
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

class _LastFlightImageInfo extends StatelessWidget {
  final String aircraftName;
  final String date;
  final String location;
  final String duration;

  const _LastFlightImageInfo({
    required this.aircraftName,
    required this.date,
    required this.location,
    required this.duration,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _FlightInfoLine(
                    icon: Icons.flight_rounded,
                    text: aircraftName,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _FlightInfoLine(
                    icon: Icons.calendar_month_rounded,
                    text: date,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _FlightInfoLine(
                    icon: Icons.place_rounded,
                    text: location,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _FlightInfoLine(
                    icon: Icons.timer_rounded,
                    text: duration,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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
          Icon(icon, color: Colors.white, size: 15),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                shadows: [
                  Shadow(
                    color: Colors.black54,
                    blurRadius: 6,
                    offset: Offset(0, 1),
                  ),
                ],
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
    final settings = fleet.appSettings;
    final webcamNames =
        settings.webcams.isEmpty ? defaultWebcams : settings.webcams;
    final webcamIndex = _firstWebcamIndexWithUrl(settings, webcamNames);
    final webcamTitle = webcamNames[webcamIndex];
    final webcamUrl = webcamIndex < settings.webcamUrls.length
        ? settings.webcamUrls[webcamIndex].trim()
        : null;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Center(
              child: SizedBox(
                width: 336,
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: WebcamLivePreview(
                      key: ValueKey('$webcamTitle|$webcamUrl'),
                      title: webcamTitle,
                      sourceUrl: webcamUrl,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Center(
              child: SizedBox(
                width: 168,
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
            ),
          ),
        ],
      ),
    );
  }
}

int _firstWebcamIndexWithUrl(AppSettings settings, List<String> webcamNames) {
  for (var index = 0; index < webcamNames.length; index++) {
    if (index < settings.webcamUrls.length &&
        settings.webcamUrls[index].trim().isNotEmpty) {
      return index;
    }
  }
  return 0;
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: IntrinsicWidth(
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(icon, color: const Color(0xFF0A84FF), size: 20),
                  const SizedBox(width: 7),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        value,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
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
      ),
    );
  }
}

Future<void> _showRepairInfoDialog(
  BuildContext context,
  List<AircraftModel> aircraft,
) async {
  final repairAircraft = aircraft
      .where((item) => item.status == AircraftStatus.maintenance)
      .toList();

  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Offene Reparaturen'),
      content: SizedBox(
        width: 460,
        child: repairAircraft.isEmpty
            ? const Text('Aktuell sind keine Reparaturen hinterlegt.')
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var index = 0;
                      index < repairAircraft.length;
                      index++) ...[
                    _RepairInfoRow(aircraft: repairAircraft[index]),
                    if (index < repairAircraft.length - 1)
                      const Divider(height: 18),
                  ],
                ],
              ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Schliessen'),
        ),
      ],
    ),
  );
}

class _RepairInfoRow extends StatelessWidget {
  final AircraftModel aircraft;

  const _RepairInfoRow({required this.aircraft});

  @override
  Widget build(BuildContext context) {
    final photo = aircraft.photos.isNotEmpty ? aircraft.photos.first : null;
    final repairText = aircraft.repairNotes.trim().isNotEmpty
        ? aircraft.repairNotes.trim()
        : 'Noch keine Reparaturhinweise hinterlegt.';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 72,
            height: 54,
            child: photo == null
                ? Container(
                    color: const Color(0xFFEFF6FF),
                    child: const Icon(
                      Icons.airplanemode_active_rounded,
                      color: Color(0xFF0A84FF),
                    ),
                  )
                : Image(
                    image: mediaImageProvider(photo),
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                aircraft.name,
                style: const TextStyle(
                  color: Color(0xFF06172E),
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                repairText,
                style: const TextStyle(
                  color: Color(0xFF475569),
                  fontSize: 12,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WeatherForecastCard extends ConsumerStatefulWidget {
  final FleetState fleet;

  const _WeatherForecastCard({required this.fleet});

  @override
  ConsumerState<_WeatherForecastCard> createState() =>
      _WeatherForecastCardState();
}

class _WeatherForecastCardState extends ConsumerState<_WeatherForecastCard> {
  late String _selectedLocation;
  final TextEditingController _customLocation = TextEditingController();

  List<String> get _knownLocations {
    final profile = widget.fleet.pilotProfile;
    final locations = <String>[
      if (profile.homeAirfield.trim().isNotEmpty) profile.homeAirfield.trim(),
      ...profile.flightAreas.where((area) => area.trim().isNotEmpty),
    ];
    final uniqueLocations = locations.toSet().toList();
    return uniqueLocations.isEmpty ? ['Flugplatz'] : uniqueLocations;
  }

  String get _weatherLocation {
    final custom = _customLocation.text.trim();
    return custom.isNotEmpty ? custom : _selectedLocation;
  }

  @override
  void initState() {
    super.initState();
    _selectedLocation = _knownLocations.first;
  }

  @override
  void didUpdateWidget(covariant _WeatherForecastCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_knownLocations.contains(_selectedLocation)) {
      _selectedLocation = _knownLocations.first;
    }
  }

  @override
  void dispose() {
    _customLocation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.fleet.appSettings;
    final weatherAsync = ref.watch(
      weatherForecastProvider(
        WeatherQuery(
          location: _weatherLocation,
          timeZone: settings.timeZone,
        ),
      ),
    );
    final weather = weatherAsync.maybeWhen(
      data: (weather) => weather,
      orElse: () => fallbackWeather(_weatherLocation),
    );
    final rows = _weatherRows(weather, settings);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.wb_sunny_rounded,
                  color: Color(0xFFF59E0B),
                  size: 28,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Wettervorhersage',
                    style: _dashboardHeadingStyle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _WeatherLocationChooser(
              locations: _knownLocations,
              selectedLocation: _selectedLocation,
              customLocation: _customLocation,
              onSelected: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _selectedLocation = value;
                  _customLocation.clear();
                });
              },
              onCustomChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 28),
            Text(
              '$_weatherLocation - ${weather.condition}${weather.isLive ? '' : ' (Fallback)'}',
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: _WeatherTable(rows: rows),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  weather.assessmentIcon,
                  color: weather.assessmentColor,
                  size: 30,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    weather.assessment,
                    style: TextStyle(
                      color: weather.assessmentColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      height: 1.22,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

List<(IconData, String, String)> _weatherRows(
  OpenMeteoWeather weather,
  AppSettings settings,
) {
  final wind =
      '${windDirectionLabel(weather.windDirection)} ${formatWindSpeed(weather.windSpeedKmh, settings.windUnit)}';
  return [
    (
      Icons.thermostat_rounded,
      'Temperatur',
      '${formatTemperature(weather.temperatureC, settings.temperatureUnit)}, aktuell'
    ),
    (Icons.air_rounded, 'Wind', wind),
    (
      Icons.speed_rounded,
      'Boeen',
      'bis ${formatWindSpeed(weather.gustsKmh, settings.windUnit)}'
    ),
    (
      Icons.water_drop_rounded,
      'Niederschlag',
      '${weather.precipitationProbability} %, heute'
    ),
    (
      Icons.visibility_rounded,
      'Sicht',
      formatDistance(weather.visibilityKm, settings.distanceUnit)
    ),
    (Icons.wb_twilight_rounded, 'Sonnenuntergang', '${weather.sunset} Uhr'),
  ];
}

class _WeatherLocationChooser extends StatelessWidget {
  final List<String> locations;
  final String selectedLocation;
  final TextEditingController customLocation;
  final ValueChanged<String?> onSelected;
  final ValueChanged<String> onCustomChanged;

  const _WeatherLocationChooser({
    required this.locations,
    required this.selectedLocation,
    required this.customLocation,
    required this.onSelected,
    required this.onCustomChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final locationPicker = DropdownButtonFormField<String>(
          initialValue: locations.contains(selectedLocation)
              ? selectedLocation
              : locations.first,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Fluggebiet',
            isDense: true,
            prefixIcon: Icon(Icons.place_rounded, size: 18),
          ),
          items: [
            for (final location in locations)
              DropdownMenuItem(value: location, child: Text(location)),
          ],
          onChanged: onSelected,
        );
        final customField = TextField(
          controller: customLocation,
          onChanged: onCustomChanged,
          decoration: const InputDecoration(
            labelText: 'Freier Ort',
            isDense: true,
            prefixIcon: Icon(Icons.edit_location_alt_rounded, size: 18),
          ),
        );

        if (compact) {
          return Column(
            children: [
              locationPicker,
              const SizedBox(height: 8),
              customField,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: locationPicker),
            const SizedBox(width: 10),
            Expanded(child: customField),
          ],
        );
      },
    );
  }
}

class _WeatherTable extends StatelessWidget {
  final List<(IconData, String, String)> rows;

  const _WeatherTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return _WeatherRowsTable(rows: rows);
        }

        final leftRows = rows.take(3).toList();
        final rightRows = rows.skip(3).toList();

        return Table(
          columnWidths: const {
            0: FixedColumnWidth(30),
            1: FixedColumnWidth(112),
            2: FlexColumnWidth(),
            3: FixedColumnWidth(36),
            4: FixedColumnWidth(30),
            5: FixedColumnWidth(128),
            6: FlexColumnWidth(),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            for (var index = 0; index < leftRows.length; index++)
              TableRow(
                children: [
                  ..._weatherCells(leftRows[index]),
                  const SizedBox(width: 36),
                  ..._weatherCells(rightRows[index]),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _WeatherRowsTable extends StatelessWidget {
  final List<(IconData, String, String)> rows;

  const _WeatherRowsTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Table(
      columnWidths: const {
        0: FixedColumnWidth(32),
        1: FixedColumnWidth(142),
        2: FlexColumnWidth(1.8),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        for (final row in rows)
          TableRow(
            children: _weatherCells(row),
          ),
      ],
    );
  }
}

List<Widget> _weatherCells((IconData, String, String) row) {
  return [
    Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Icon(row.$1, color: const Color(0xFF0A84FF), size: 18),
    ),
    Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        row.$2,
        style: const TextStyle(
          color: Color(0xFF64748B),
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
    Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        row.$3,
        style: const TextStyle(
          color: Color(0xFF334155),
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    ),
  ];
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

class _TransmitterAssignmentsTable extends StatelessWidget {
  final FleetState fleet;

  const _TransmitterAssignmentsTable({required this.fleet});

  @override
  Widget build(BuildContext context) {
    final sortedAircraft = [...fleet.aircraft]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return SizedBox(
      height: 330,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.settings_remote_rounded,
                    color: Color(0xFF0A84FF),
                    size: 26,
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Sender-Zuordnung',
                    style: _dashboardHeadingStyle,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (sortedAircraft.isEmpty)
                const Text(
                  'Noch keine Modelle angelegt.',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                  ),
                )
              else
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SingleChildScrollView(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            headingRowHeight: 38,
                            dataRowMinHeight: 46,
                            dataRowMaxHeight: 50,
                            horizontalMargin: 14,
                            columnSpacing: 26,
                            headingRowColor: WidgetStateProperty.all(
                              const Color(0xFFEAF3FF),
                            ),
                            columns: const [
                              DataColumn(
                                  label: _DashboardTableHeader('Modell')),
                              DataColumn(
                                label: _DashboardTableHeader('Kategorie'),
                              ),
                              DataColumn(
                                  label: _DashboardTableHeader('Sender')),
                              DataColumn(
                                label: SizedBox(
                                  width: 105,
                                  child: Center(
                                    child: _DashboardTableHeader(
                                      'Speicherplatz',
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            rows: [
                              for (final aircraft in sortedAircraft)
                                DataRow(
                                  cells: [
                                    DataCell(
                                      _DashboardAircraftCell(
                                          aircraft: aircraft),
                                    ),
                                    DataCell(
                                        _DashboardTableText(aircraft.type)),
                                    DataCell(
                                      _DashboardTableText(
                                        _tableFallback(aircraft.transmitter),
                                      ),
                                    ),
                                    DataCell(
                                      SizedBox(
                                        width: 105,
                                        child: Center(
                                          child: _DashboardTableText(
                                            _tableFallback(
                                              aircraft.transmitterMemorySlot,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardAircraftCell extends StatelessWidget {
  final AircraftModel aircraft;

  const _DashboardAircraftCell({required this.aircraft});

  @override
  Widget build(BuildContext context) {
    final photo = aircraft.photos.isEmpty ? null : aircraft.photos.first;

    return SizedBox(
      width: 178,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox.square(
              dimension: 34,
              child: photo == null
                  ? Container(
                      color: const Color(0xFFE2E8F0),
                      child: const Icon(
                        Icons.flight_rounded,
                        color: Color(0xFF64748B),
                        size: 18,
                      ),
                    )
                  : Image(
                      image: mediaImageProvider(photo),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: const Color(0xFFE2E8F0),
                        child: const Icon(
                          Icons.flight_rounded,
                          color: Color(0xFF64748B),
                          size: 18,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(child: _DashboardTableText(aircraft.name)),
        ],
      ),
    );
  }
}

class _DashboardTableHeader extends StatelessWidget {
  final String text;

  const _DashboardTableHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF06172E),
        fontSize: 12,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _DashboardTableText extends StatelessWidget {
  final String text;
  final TextAlign textAlign;

  const _DashboardTableText(
    this.text, {
    this.textAlign = TextAlign.left,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: textAlign,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Color(0xFF334155),
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

String _tableFallback(String value) => value.trim().isEmpty ? '-' : value;

Color _statusColor(AircraftStatus status) {
  return switch (status) {
    AircraftStatus.ready => const Color(0xFF16A34A),
    AircraftStatus.maintenance => const Color(0xFFEA580C),
    AircraftStatus.destroyed => const Color(0xFFDC2626),
  };
}
