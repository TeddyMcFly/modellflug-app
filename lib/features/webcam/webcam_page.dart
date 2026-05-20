import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/app_scaffold.dart';
import '../../shared/models/aircraft_model.dart';
import '../../shared/providers/fleet_provider.dart';
import '../../shared/services/open_meteo_service.dart';

class WebcamPage extends ConsumerStatefulWidget {
  const WebcamPage({super.key});

  static const livePlaceholderAsset = 'assets/webcam/lmfc_flugplatz_1.jpg';

  @override
  ConsumerState<WebcamPage> createState() => _WebcamPageState();
}

class _WebcamPageState extends ConsumerState<WebcamPage> {
  late String _selectedWebcam = defaultWebcams.first;
  late String _selectedForecastLocation = 'Flugplatz';

  List<String> _forecastLocations(FleetState fleet) {
    final locations = <String>[
      if (fleet.pilotProfile.homeAirfield.trim().isNotEmpty)
        fleet.pilotProfile.homeAirfield.trim(),
      ...fleet.pilotProfile.flightAreas.where((area) => area.trim().isNotEmpty),
    ];
    final unique = locations.toSet().toList();
    return unique.isEmpty ? ['Flugplatz'] : unique;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final webcams = ref.read(fleetProvider).appSettings.webcams;
    final forecastLocations = _forecastLocations(ref.read(fleetProvider));
    if (webcams.isNotEmpty && !webcams.contains(_selectedWebcam)) {
      _selectedWebcam = webcams.first;
    }
    if (!forecastLocations.contains(_selectedForecastLocation)) {
      _selectedForecastLocation = forecastLocations.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fleet = ref.watch(fleetProvider);
    final webcams = fleet.appSettings.webcams;
    final availableWebcams = webcams.isEmpty ? defaultWebcams : webcams;
    final forecastLocations = _forecastLocations(fleet);
    if (!availableWebcams.contains(_selectedWebcam)) {
      _selectedWebcam = availableWebcams.first;
    }
    if (!forecastLocations.contains(_selectedForecastLocation)) {
      _selectedForecastLocation = forecastLocations.first;
    }

    return AppScaffold(
      title: 'Webcams',
      subtitle:
          'Platzkameras, Wetterhinweise und Sichtbedingungen fuer den Flugtag.',
      action: FilledButton.icon(
        onPressed: () {},
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Aktualisieren'),
      ),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _WebcamChooser(
              webcams: availableWebcams,
              selectedWebcam: _selectedWebcam,
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedWebcam = value);
                }
              },
            ),
            const SizedBox(height: 12),
            _CameraPreview(title: _selectedWebcam),
            const SizedBox(height: 12),
            _AirfieldWeatherCard(webcam: _selectedWebcam),
            const SizedBox(height: 12),
            _WeeklyWeatherCard(
              locations: forecastLocations,
              selectedLocation: _selectedForecastLocation,
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedForecastLocation = value);
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _WebcamChooser extends StatelessWidget {
  final List<String> webcams;
  final String selectedWebcam;
  final ValueChanged<String?> onChanged;

  const _WebcamChooser({
    required this.webcams,
    required this.selectedWebcam,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: DropdownButtonFormField<String>(
          initialValue:
              webcams.contains(selectedWebcam) ? selectedWebcam : webcams.first,
          isExpanded: true,
          style: const TextStyle(
            color: Color(0xFF334155),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          decoration: const InputDecoration(
            labelText: 'Webcam',
            labelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            prefixIcon: Icon(Icons.videocam_rounded, size: 18),
            prefixIconConstraints: BoxConstraints(minWidth: 34),
          ),
          items: [
            for (final webcam in webcams)
              DropdownMenuItem(
                value: webcam,
                child: Text(
                  webcam,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _CameraPreview extends StatelessWidget {
  final String title;

  const _CameraPreview({required this.title});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: 8 / 5,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(WebcamPage.livePlaceholderAsset, fit: BoxFit.cover),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.05),
                    Colors.black.withValues(alpha: 0.35),
                  ],
                ),
              ),
            ),
            const Positioned(
              left: 18,
              top: 18,
              child: _LiveBadge(),
            ),
            Positioned(
              left: 22,
              bottom: 22,
              right: 22,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Letztes Bild vor 18 Sekunden',
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
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFDC2626),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, color: Colors.white, size: 10),
          SizedBox(width: 8),
          Text(
            'LIVE',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _AirfieldWeatherCard extends ConsumerWidget {
  final String webcam;

  const _AirfieldWeatherCard({required this.webcam});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(fleetProvider).appSettings;
    final weatherAsync = ref.watch(
      weatherForecastProvider(
        WeatherQuery(location: webcam, timeZone: settings.timeZone),
      ),
    );
    final weather = weatherAsync.maybeWhen(
      data: (weather) => weather,
      orElse: () => fallbackWeather(webcam),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Wetter am Platz - ${weather.location}${weather.isLive ? '' : ' (Fallback)'}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 38,
              runSpacing: 18,
              children: [
                _WeatherValue(
                  icon: Icons.cloud_rounded,
                  label: 'Bewoelkung',
                  value: '${weather.condition}, ${weather.cloudCover} %',
                ),
                _WeatherValue(
                  icon: Icons.thermostat_rounded,
                  label: 'Temperatur',
                  value: formatTemperature(
                    weather.temperatureC,
                    settings.temperatureUnit,
                  ),
                ),
                _WeatherValue(
                  icon: Icons.air_rounded,
                  label: 'Wind',
                  value:
                      '${windDirectionLabel(weather.windDirection)} ${formatWindSpeed(weather.windSpeedKmh, settings.windUnit)}',
                ),
                _WeatherValue(
                  icon: Icons.speed_rounded,
                  label: 'Boeen',
                  value: formatWindSpeed(weather.gustsKmh, settings.windUnit),
                ),
                _WeatherValue(
                  icon: Icons.compress_rounded,
                  label: 'Luftdruck',
                  value: '${weather.pressureHpa.round()} hPa',
                ),
                _WeatherValue(
                  icon: Icons.visibility_rounded,
                  label: 'Sichtweite',
                  value: formatDistance(
                    weather.visibilityKm,
                    settings.distanceUnit,
                  ),
                ),
                _WeatherValue(
                  icon: Icons.wb_twilight_rounded,
                  label: 'Sonnenuntergang',
                  value: weather.sunset,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WeatherValue extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _WeatherValue({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF0A84FF), size: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
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

class _WeeklyWeatherCard extends ConsumerWidget {
  final List<String> locations;
  final String selectedLocation;
  final ValueChanged<String?> onChanged;

  const _WeeklyWeatherCard({
    required this.locations,
    required this.selectedLocation,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(fleetProvider).appSettings;
    final forecastAsync = ref.watch(
      weeklyWeatherForecastProvider(
        WeatherQuery(location: selectedLocation, timeZone: settings.timeZone),
      ),
    );
    final forecast = forecastAsync.maybeWhen(
      data: (forecast) => forecast,
      orElse: fallbackWeeklyForecast,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Wettervorhersage fuer die naechste Woche',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 14),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: DropdownButtonFormField<String>(
                    initialValue: locations.contains(selectedLocation)
                        ? selectedLocation
                        : locations.first,
                    isExpanded: true,
                    style: const TextStyle(
                      color: Color(0xFF334155),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Fluggebiet',
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      prefixIcon: Icon(Icons.place_rounded, size: 18),
                      prefixIconConstraints: BoxConstraints(minWidth: 34),
                    ),
                    items: [
                      for (final location in locations)
                        DropdownMenuItem(
                          value: location,
                          child: Text(
                            location,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: onChanged,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 38,
                dataRowMinHeight: 42,
                dataRowMaxHeight: 48,
                horizontalMargin: 12,
                columnSpacing: 22,
                headingTextStyle: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
                dataTextStyle: const TextStyle(
                  color: Color(0xFF334155),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                columns: const [
                  DataColumn(label: Text('Tag')),
                  DataColumn(label: Text('Wetter')),
                  DataColumn(label: Text('Temp.')),
                  DataColumn(label: Text('Regen')),
                  DataColumn(label: Text('Wind')),
                  DataColumn(label: Text('Boeen')),
                  DataColumn(label: Text('Sonnenuntergang')),
                  DataColumn(label: Text('Einschaetzung')),
                ],
                rows: [
                  for (final day in forecast)
                    DataRow(
                      cells: [
                        DataCell(Text(day.label)),
                        DataCell(Text(day.condition)),
                        DataCell(
                          Text(
                            '${formatTemperature(day.minTemperatureC, settings.temperatureUnit)} - ${formatTemperature(day.maxTemperatureC, settings.temperatureUnit)}',
                          ),
                        ),
                        DataCell(Text('${day.precipitationProbability} %')),
                        DataCell(
                          Text(formatWindSpeed(
                              day.windSpeedKmh, settings.windUnit)),
                        ),
                        DataCell(
                          Text(
                              formatWindSpeed(day.gustsKmh, settings.windUnit)),
                        ),
                        DataCell(Text('${day.sunset} Uhr')),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                day.assessmentIcon,
                                color: day.assessmentColor,
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              SizedBox(
                                width: 240,
                                child: Text(
                                  day.assessment,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: day.assessmentColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            if (forecast.isNotEmpty && !forecast.first.isLive) ...[
              const SizedBox(height: 10),
              const Text(
                'Fallback-Daten, wenn Open-Meteo fuer dieses Fluggebiet nicht erreichbar ist.',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
