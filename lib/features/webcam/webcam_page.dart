import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../core/widgets/app_scaffold.dart';
import '../../shared/models/aircraft_model.dart';
import '../../shared/providers/fleet_provider.dart';
import '../../shared/services/open_meteo_service.dart';
import 'webcam_embed_view.dart';

const _lmfcWebcamImageUrl =
    'https://www.lmfc.de/fileadmin/Modellflug/cam/bilder/webcam.jpg';

class WebcamPage extends ConsumerStatefulWidget {
  const WebcamPage({super.key});

  static const livePlaceholderAsset = 'assets/webcam/lmfc_flugplatz_1.jpg';

  @override
  ConsumerState<WebcamPage> createState() => _WebcamPageState();
}

class _WebcamPageState extends ConsumerState<WebcamPage> {
  late String _selectedWebcam = defaultWebcams.first;
  late String _selectedForecastLocation = 'Flugplatz';
  Timer? _weatherRefreshTimer;
  int _cameraRefreshSerial = 0;

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
  void initState() {
    super.initState();
    _weatherRefreshTimer = Timer.periodic(
      const Duration(minutes: 20),
      (_) => _refreshWeather(),
    );
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
  void dispose() {
    _weatherRefreshTimer?.cancel();
    super.dispose();
  }

  void _refreshWeather() {
    if (!mounted) {
      return;
    }

    setState(() => _cameraRefreshSerial++);

    final settings = ref.read(fleetProvider).appSettings;
    final webcamQuery = WeatherQuery(
      location: _selectedWebcam,
      timeZone: settings.timeZone,
    );
    final forecastQuery = WeatherQuery(
      location: _selectedForecastLocation,
      timeZone: settings.timeZone,
    );
    final weatherService = OpenMeteoService.instance;

    weatherService.clearForecastCache(webcamQuery);
    weatherService.clearPressureTrendCache(webcamQuery);
    weatherService.clearForecastCache(forecastQuery);
    weatherService.clearWeeklyForecastCache(forecastQuery);

    ref.invalidate(weatherForecastProvider(webcamQuery));
    ref.invalidate(pressureTrendProvider(webcamQuery));
    ref.invalidate(weatherForecastProvider(forecastQuery));
    ref.invalidate(weeklyWeatherForecastProvider(forecastQuery));
  }

  @override
  Widget build(BuildContext context) {
    final fleet = ref.watch(fleetProvider);
    final settings = fleet.appSettings;
    final webcams = settings.webcams;
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
      headerWeatherLocation: _selectedForecastLocation,
      action: FilledButton.icon(
        onPressed: _refreshWeather,
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
            _CameraPreview(
              title: _selectedWebcam,
              sourceUrl: _webcamUrlFor(settings, _selectedWebcam),
              refreshSerial: _cameraRefreshSerial,
            ),
            const SizedBox(height: 12),
            _AirfieldWeatherCard(webcam: _selectedWebcam),
            const SizedBox(height: 12),
            _PressureTrendCard(location: _selectedWebcam),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_rounded, color: Color(0xFF0A84FF), size: 18),
            SizedBox(width: 6),
            Text(
              'Webcam',
              style: TextStyle(
                color: Color(0xFF334155),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final buttonWidth =
                constraints.maxWidth < 220 ? constraints.maxWidth : 220.0;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var index = 0; index < webcams.length; index++)
                  SizedBox(
                    width: buttonWidth,
                    child: _WebcamChoiceButton(
                      number: index + 1,
                      name: webcams[index],
                      selected: webcams[index] == selectedWebcam,
                      onTap: () => onChanged(webcams[index]),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _WebcamChoiceButton extends StatelessWidget {
  final int number;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  const _WebcamChoiceButton({
    required this.number,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor =
        selected ? const Color(0xFF0A84FF) : const Color(0xFFE2E8F0);
    final backgroundColor =
        selected ? const Color(0xFFEAF3FF) : const Color(0xFFFFFFFF);
    final foregroundColor =
        selected ? const Color(0xFF06172E) : const Color(0xFF475569);

    return Semantics(
      button: true,
      selected: selected,
      label: 'Webcam $number, $name',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected
                      ? const Color(0xFF0A84FF)
                      : const Color(0xFF94A3B8),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Webcam $number',
                        style: TextStyle(
                          color: foregroundColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        name,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
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

String? _webcamUrlFor(AppSettings settings, String webcam) {
  final webcamNames =
      settings.webcams.isEmpty ? defaultWebcams : settings.webcams;
  final index = webcamNames.indexOf(webcam);
  if (index == -1 || index >= settings.webcamUrls.length) {
    return null;
  }

  final url = settings.webcamUrls[index].trim();
  return url.isEmpty ? null : url;
}

String? _normalizedWebcamUrl(String? value) {
  final url = value?.trim() ?? '';
  if (url.isEmpty) {
    return null;
  }

  final lower = url.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    return url;
  }

  return 'https://$url';
}

String _displayWebcamUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) {
    return url;
  }

  final host = uri.host.toLowerCase();
  final path = uri.path.toLowerCase().replaceFirst(RegExp(r'/$'), '');
  final isLmfcWebcamPage = (host == 'lmfc.de' || host == 'www.lmfc.de') &&
      (path.isEmpty || path == '/webcam');

  if (isLmfcWebcamPage) {
    return _lmfcWebcamImageUrl;
  }

  return url;
}

bool _isDirectImageFeed(String url) {
  final lower = url.toLowerCase();
  return lower.contains('.jpg') ||
      lower.contains('.jpeg') ||
      lower.contains('.png') ||
      lower.contains('.webp') ||
      lower.contains('.gif') ||
      lower.contains('.mjpg') ||
      lower.contains('.mjpeg') ||
      lower.contains('snapshot') ||
      lower.contains('image');
}

bool _isDirectVideoFeed(String url) {
  final lower = url.toLowerCase();
  return lower.contains('.m3u8') ||
      lower.contains('.mp4') ||
      lower.contains('.webm') ||
      lower.contains('.mov');
}

String _urlWithRefreshToken(String url, int refreshSerial) {
  if (refreshSerial == 0) {
    return url;
  }

  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) {
    return url;
  }

  final query = Map<String, String>.from(uri.queryParameters);
  query['_modellflug_refresh'] = '$refreshSerial';
  return uri.replace(queryParameters: query).toString();
}

class _CameraPreview extends StatelessWidget {
  final String title;
  final String? sourceUrl;
  final int refreshSerial;

  const _CameraPreview({
    required this.title,
    required this.sourceUrl,
    required this.refreshSerial,
  });

  @override
  Widget build(BuildContext context) {
    final settingsUrl = _normalizedWebcamUrl(sourceUrl);
    final displayUrl =
        settingsUrl == null ? null : _displayWebcamUrl(settingsUrl);
    final hasUrl = displayUrl != null;
    final isDirectImage = displayUrl != null && _isDirectImageFeed(displayUrl);
    final previewAspectRatio = isDirectImage ? 4 / 3 : 8 / 5;
    final statusText =
        hasUrl ? 'Quelle aus Einstellungen' : 'Keine Webadresse hinterlegt';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: previewAspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (displayUrl == null)
              const _CameraFeedStatus(
                icon: Icons.link_off_rounded,
                message: 'Keine Webadresse hinterlegt',
              )
            else if (_isDirectVideoFeed(displayUrl))
              _VideoCameraFeed(url: displayUrl)
            else if (_isDirectImageFeed(displayUrl))
              _NetworkCameraImage(
                url: _urlWithRefreshToken(displayUrl, refreshSerial),
              )
            else
              WebcamEmbedView(url: displayUrl),
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
            if (isDirectImage)
              Positioned(
                left: 18,
                top: 68,
                child: _CameraTitleBadge(
                  title: title,
                  statusText: statusText,
                ),
              )
            else
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
                    Text(
                      statusText,
                      style: const TextStyle(
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

class _CameraTitleBadge extends StatelessWidget {
  final String title;
  final String statusText;

  const _CameraTitleBadge({
    required this.title,
    required this.statusText,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              statusText,
              style: const TextStyle(
                color: Color(0xFFE2E8F0),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NetworkCameraImage extends StatelessWidget {
  final String url;

  const _NetworkCameraImage({required this.url});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF0F172A),
      child: Image(
        image: NetworkImage(
          url,
          webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
        ),
        fit: BoxFit.contain,
        loadingBuilder: (context, child, progress) {
          if (progress == null) {
            return child;
          }
          return const _CameraFeedStatus(
            icon: Icons.sync_rounded,
            message: 'Webcam wird geladen',
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return const _CameraFeedStatus(
            icon: Icons.broken_image_rounded,
            message: 'Webcam-Bild konnte nicht geladen werden',
          );
        },
      ),
    );
  }
}

class _VideoCameraFeed extends StatefulWidget {
  final String url;

  const _VideoCameraFeed({required this.url});

  @override
  State<_VideoCameraFeed> createState() => _VideoCameraFeedState();
}

class _VideoCameraFeedState extends State<_VideoCameraFeed> {
  VideoPlayerController? _controller;
  Object? _error;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadVideo();
  }

  @override
  void didUpdateWidget(covariant _VideoCameraFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _loadVideo();
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _loadVideo() async {
    final loadGeneration = ++_loadGeneration;
    final previousController = _controller;
    _controller = null;
    setState(() => _error = null);
    await previousController?.dispose();

    final uri = Uri.tryParse(widget.url);
    if (uri == null || !uri.hasScheme) {
      if (!mounted || loadGeneration != _loadGeneration) {
        return;
      }
      setState(() => _error = const FormatException('Invalid webcam URL'));
      return;
    }

    late final VideoPlayerController nextController;
    try {
      nextController = VideoPlayerController.networkUrl(uri);
      await nextController.initialize();
      await nextController.setLooping(true);
      await nextController.setVolume(0);
      await nextController.play();
      if (!mounted || loadGeneration != _loadGeneration) {
        await nextController.dispose();
        return;
      }
      setState(() => _controller = nextController);
    } on Object catch (error) {
      try {
        await nextController.dispose();
      } catch (_) {
        // If creating the controller failed, there is nothing useful to clean up.
      }
      if (!mounted || loadGeneration != _loadGeneration) {
        return;
      }
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_error != null) {
      return const _CameraFeedStatus(
        icon: Icons.videocam_off_rounded,
        message: 'Webcam-Video konnte nicht geladen werden',
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return const _CameraFeedStatus(
        icon: Icons.sync_rounded,
        message: 'Webcam-Video wird geladen',
      );
    }

    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: controller.value.size.width,
        height: controller.value.size.height,
        child: VideoPlayer(controller),
      ),
    );
  }
}

class _CameraFeedStatus extends StatelessWidget {
  final IconData icon;
  final String message;

  const _CameraFeedStatus({
    required this.icon,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFF0F172A)),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 34),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
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
    final titlePrefix = weather.isLive ? 'Live-' : 'Fallback-';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 3,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                Text(
                  '${titlePrefix}Wetter am Platz - ${weather.location}${weather.isLive ? '' : ' (Fallback)'}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Text(
                  'Aktualisierung alle 20 Minuten',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 760;
                final valuesWidth = math.min(
                  constraints.maxWidth - (compact ? 0 : 164),
                  880.0,
                );
                final values = Wrap(
                  spacing: 32,
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
                      value:
                          formatWindSpeed(weather.gustsKmh, settings.windUnit),
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
                      icon: Icons.wb_sunny_rounded,
                      label: 'Sonnenaufgang',
                      value: '${weather.sunrise} Uhr',
                    ),
                    _WeatherValue(
                      icon: Icons.wb_twilight_rounded,
                      label: 'Sonnenuntergang',
                      value: '${weather.sunset} Uhr',
                    ),
                  ],
                );

                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      values,
                      const SizedBox(height: 12),
                      _WindCompass(
                        degrees: weather.windDirection,
                        label: windDirectionLabel(weather.windDirection),
                        windSpeed: formatWindSpeed(
                          weather.windSpeedKmh,
                          settings.windUnit,
                        ),
                        gustSpeed: formatWindSpeed(
                          weather.gustsKmh,
                          settings.windUnit,
                        ),
                        windKmh: weather.windSpeedKmh,
                        gustsKmh: weather.gustsKmh,
                      ),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: math.max(0, valuesWidth),
                      child: values,
                    ),
                    const SizedBox(width: 8),
                    _WindCompass(
                      degrees: weather.windDirection,
                      label: windDirectionLabel(weather.windDirection),
                      windSpeed: formatWindSpeed(
                        weather.windSpeedKmh,
                        settings.windUnit,
                      ),
                      gustSpeed: formatWindSpeed(
                        weather.gustsKmh,
                        settings.windUnit,
                      ),
                      windKmh: weather.windSpeedKmh,
                      gustsKmh: weather.gustsKmh,
                    ),
                  ],
                );
              },
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

class _WindCompass extends StatelessWidget {
  final int degrees;
  final String label;
  final String windSpeed;
  final String gustSpeed;
  final double windKmh;
  final double gustsKmh;

  const _WindCompass({
    required this.degrees,
    required this.label,
    required this.windSpeed,
    required this.gustSpeed,
    required this.windKmh,
    required this.gustsKmh,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Windrichtung',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 142,
            height: 142,
            child: _WindCompassInstrument(
              degrees: degrees,
              windKmh: windKmh,
              gustsKmh: gustsKmh,
            ),
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '$label $degrees Grad\n'),
                TextSpan(
                  text: 'Wind $windSpeed',
                  style: const TextStyle(color: Color(0xFF0A84FF)),
                ),
                const TextSpan(text: ' / '),
                TextSpan(
                  text: 'Boeen $gustSpeed',
                  style: const TextStyle(color: Color(0xFFE11D2E)),
                ),
              ],
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF334155),
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _WindCompassInstrument extends StatefulWidget {
  final int degrees;
  final double windKmh;
  final double gustsKmh;

  const _WindCompassInstrument({
    required this.degrees,
    required this.windKmh,
    required this.gustsKmh,
  });

  @override
  State<_WindCompassInstrument> createState() => _WindCompassInstrumentState();
}

class _WindCompassInstrumentState extends State<_WindCompassInstrument>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/widgets/wind_compass_rose.png',
          fit: BoxFit.contain,
        ),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final sway = math.sin(_controller.value * math.pi * 2) * 4.5;
            return CustomPaint(
              painter: _WindDirectionArrowPainter(
                degrees: widget.degrees,
                swayDegrees: sway,
                windKmh: widget.windKmh,
                gustsKmh: widget.gustsKmh,
              ),
            );
          },
        ),
      ],
    );
  }
}

class _WindDirectionArrowPainter extends CustomPainter {
  final int degrees;
  final double swayDegrees;
  final double windKmh;
  final double gustsKmh;

  const _WindDirectionArrowPainter({
    required this.degrees,
    required this.swayDegrees,
    required this.windKmh,
    required this.gustsKmh,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;
    final angle = -math.pi / 2 + (degrees + swayDegrees) * math.pi / 180;
    final direction = Offset(math.cos(angle), math.sin(angle));
    final normal = Offset(-direction.dy, direction.dx);
    _drawSpeedArrow(
      canvas: canvas,
      center: center,
      radius: radius,
      direction: direction,
      normal: normal,
      speedKmh: gustsKmh,
      color: const Color(0xFFE11D2E),
      offset: 0,
      strokeWidth: 6.8,
    );
    _drawSpeedArrow(
      canvas: canvas,
      center: center,
      radius: radius,
      direction: direction,
      normal: normal,
      speedKmh: windKmh,
      color: const Color(0xFF0A84FF),
      offset: 0,
      strokeWidth: 5.4,
    );
  }

  void _drawSpeedArrow({
    required Canvas canvas,
    required Offset center,
    required double radius,
    required Offset direction,
    required Offset normal,
    required double speedKmh,
    required Color color,
    required double offset,
    required double strokeWidth,
  }) {
    const pixelsPerKmh = 2.0;
    final maxLength = radius * 0.78;
    final length = math
        .min(speedKmh.clamp(0.0, double.infinity) * pixelsPerKmh, maxLength)
        .toDouble();
    if (length <= 1) {
      return;
    }
    final sideOffset = normal * offset;
    final tip = center + direction * (radius * 0.72) + sideOffset;
    final tail = tip + direction * length;
    const headLength = 14.0;
    const headWidth = 8.0;
    final shaftEnd = tip + direction * math.min(headLength * 0.65, length);
    final headBase = tip + direction * headLength;
    final arrowHead = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(
        headBase.dx + normal.dx * headWidth,
        headBase.dy + normal.dy * headWidth,
      )
      ..lineTo(
        headBase.dx - normal.dx * headWidth,
        headBase.dy - normal.dy * headWidth,
      )
      ..close();
    final arrowPaint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawLine(tail, shaftEnd, arrowPaint);
    canvas.drawPath(arrowHead, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant _WindDirectionArrowPainter oldDelegate) {
    return oldDelegate.degrees != degrees ||
        oldDelegate.swayDegrees != swayDegrees ||
        oldDelegate.windKmh != windKmh ||
        oldDelegate.gustsKmh != gustsKmh;
  }
}

class _PressureTrendCard extends ConsumerWidget {
  final String location;

  const _PressureTrendCard({required this.location});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(fleetProvider).appSettings;
    final trendAsync = ref.watch(
      pressureTrendProvider(
        WeatherQuery(location: location, timeZone: settings.timeZone),
      ),
    );
    final trend = trendAsync.maybeWhen(
      data: (trend) => trend,
      orElse: fallbackPressureTrend,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.show_chart_rounded, color: Color(0xFF0A84FF)),
                SizedBox(width: 8),
                Text(
                  'Luftdruck-Entwicklung',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '$location - 10 Tage historisch, 3 Tage Ausblick',
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 256,
              child: CustomPaint(
                painter: _PressureTrendPainter(points: trend),
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PressureTrendPainter extends CustomPainter {
  final List<PressureTrendPoint> points;

  const _PressureTrendPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) {
      return;
    }

    final chart = Rect.fromLTWH(48, 18, size.width - 66, size.height - 72);
    final values = points.map((point) => point.pressureHpa).toList();
    final minValue = math.min(values.reduce(math.min), 1013) - 1;
    final maxValue = math.max(values.reduce(math.max), 1013) + 1;
    final range = math.max(1.0, maxValue - minValue);
    final firstForecastIndex = points.indexWhere((point) => point.forecast);
    final todayIndex =
        points.indexWhere((point) => _isSameDate(point.date, DateTime.now()));
    final separatorIndex = todayIndex >= 0 ? todayIndex : firstForecastIndex;
    final gridPaint = Paint()
      ..strokeWidth = 1
      ..color = const Color(0xFFE2E8F0);
    final axisPaint = Paint()
      ..strokeWidth = 1.4
      ..color = const Color(0xFF94A3B8);
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFF0A84FF);
    final forecastPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFF7C3AED);
    final standardPaint = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF22C55E);
    final separatorPaint = Paint()
      ..strokeWidth = 1.4
      ..color = const Color(0xFF0F172A).withValues(alpha: 0.18);
    final historyFillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF0A84FF).withValues(alpha: 0.15),
          const Color(0xFF0A84FF).withValues(alpha: 0.02),
        ],
      ).createShader(chart);
    final forecastFillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF7C3AED).withValues(alpha: 0.18),
          const Color(0xFF7C3AED).withValues(alpha: 0.03),
        ],
      ).createShader(chart);

    for (var i = 0; i <= 4; i++) {
      final y = chart.top + chart.height * i / 4;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
      final labelValue = maxValue - range * i / 4;
      _drawChartText(
        canvas,
        labelValue.round().toString(),
        Offset(chart.left - 8, y),
        align: TextAlign.right,
        anchorRight: true,
      );
    }
    canvas.drawLine(chart.bottomLeft, chart.bottomRight, axisPaint);
    canvas.drawLine(chart.bottomLeft, chart.topLeft, axisPaint);

    Offset pointOffset(int index) {
      final x = points.length == 1
          ? chart.center.dx
          : chart.left + chart.width * index / (points.length - 1);
      final normalized = (points[index].pressureHpa - minValue) / range;
      final y = chart.bottom - chart.height * normalized;
      return Offset(x, y);
    }

    final standardY = chart.bottom - chart.height * ((1013 - minValue) / range);
    if (standardY >= chart.top && standardY <= chart.bottom) {
      canvas.drawLine(
        Offset(chart.left, standardY),
        Offset(chart.right, standardY),
        standardPaint,
      );
      _drawChartText(
        canvas,
        '1013 hPa Standard',
        Offset(chart.right - 4, standardY - 10),
        align: TextAlign.right,
        anchorRight: true,
        color: const Color(0xFF15803D),
        fontSize: 10,
        fontWeight: FontWeight.w900,
      );
    }

    if (separatorIndex >= 0) {
      final separatorX = pointOffset(separatorIndex).dx;
      final sectionLabelY = math.min(chart.bottom - 18, standardY + 30);
      canvas.drawLine(
        Offset(separatorX, chart.top),
        Offset(separatorX, chart.bottom),
        separatorPaint,
      );
      _drawChartText(
        canvas,
        'HEUTE',
        Offset(separatorX, chart.top - 8),
        color: const Color(0xFF0F172A),
        fontSize: 10,
        fontWeight: FontWeight.w900,
      );
      if (separatorX > chart.left + 44) {
        _drawChartText(
          canvas,
          'HISTORISCH',
          Offset(chart.left + (separatorX - chart.left) / 2, sectionLabelY),
          color: const Color(0xFF0A84FF).withValues(alpha: 0.14),
          fontSize: 24,
          fontWeight: FontWeight.w900,
        );
      }
      if (separatorX < chart.right - 44) {
        _drawChartText(
          canvas,
          'AUSBLICK',
          Offset(separatorX + (chart.right - separatorX) / 2, sectionLabelY),
          color: const Color(0xFF7C3AED).withValues(alpha: 0.16),
          fontSize: 24,
          fontWeight: FontWeight.w900,
        );
      }
    }

    final pastPath = Path();
    final forecastPath = Path();
    final pastAreaPath = Path();
    final forecastAreaPath = Path();
    var hasPastPoint = false;
    var hasForecastPoint = false;
    for (var index = 0; index < points.length; index++) {
      final offset = pointOffset(index);
      if (!points[index].forecast) {
        if (!hasPastPoint) {
          pastPath.moveTo(offset.dx, offset.dy);
          pastAreaPath.moveTo(offset.dx, chart.bottom);
          pastAreaPath.lineTo(offset.dx, offset.dy);
          hasPastPoint = true;
        } else {
          pastPath.lineTo(offset.dx, offset.dy);
          pastAreaPath.lineTo(offset.dx, offset.dy);
        }
      } else {
        if (!hasForecastPoint) {
          final previous = pointOffset(math.max(0, index - 1));
          forecastPath.moveTo(previous.dx, previous.dy);
          forecastAreaPath.moveTo(previous.dx, chart.bottom);
          forecastAreaPath.lineTo(previous.dx, previous.dy);
          hasForecastPoint = true;
        }
        forecastPath.lineTo(offset.dx, offset.dy);
        forecastAreaPath.lineTo(offset.dx, offset.dy);
      }
    }

    if (hasPastPoint) {
      final endIndex =
          firstForecastIndex > 0 ? firstForecastIndex - 1 : points.length - 1;
      final end = pointOffset(endIndex);
      pastAreaPath.lineTo(end.dx, chart.bottom);
      pastAreaPath.close();
      canvas.drawPath(pastAreaPath, historyFillPaint);
    }
    if (hasForecastPoint) {
      final end = pointOffset(points.length - 1);
      forecastAreaPath.lineTo(end.dx, chart.bottom);
      forecastAreaPath.close();
      canvas.drawPath(forecastAreaPath, forecastFillPaint);
    }

    canvas.drawPath(pastPath, linePaint);
    canvas.drawPath(forecastPath, forecastPaint);

    for (var index = 0; index < points.length; index++) {
      final offset = pointOffset(index);
      final isToday = index == todayIndex;
      final pointPaint = Paint()
        ..color = points[index].forecast
            ? const Color(0xFF7C3AED)
            : const Color(0xFF0A84FF);
      canvas.drawCircle(offset, 4, Paint()..color = Colors.white);
      canvas.drawCircle(offset, 3.2, pointPaint);
      _drawChartText(
        canvas,
        _formatPressureDate(points[index].date),
        Offset(offset.dx, chart.bottom + 22),
        align: TextAlign.center,
        color: isToday ? const Color(0xFF0F172A) : const Color(0xFF334155),
        fontSize: isToday ? 9.5 : 8.5,
        fontWeight: isToday ? FontWeight.w900 : FontWeight.w700,
      );
    }
  }

  void _drawChartText(
    Canvas canvas,
    String text,
    Offset offset, {
    TextAlign align = TextAlign.left,
    bool anchorRight = false,
    Color color = const Color(0xFF475569),
    double fontSize = 10,
    FontWeight fontWeight = FontWeight.w700,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
        ),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(
        anchorRight ? offset.dx - painter.width : offset.dx - painter.width / 2,
        offset.dy - painter.height / 2,
      ),
    );
  }

  String _formatPressureDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day.$month.';
  }

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  bool shouldRepaint(covariant _PressureTrendPainter oldDelegate) {
    return oldDelegate.points != points;
  }
}

class _WeeklyWeatherCard extends ConsumerStatefulWidget {
  final List<String> locations;
  final String selectedLocation;
  final ValueChanged<String?> onChanged;

  const _WeeklyWeatherCard({
    required this.locations,
    required this.selectedLocation,
    required this.onChanged,
  });

  @override
  ConsumerState<_WeeklyWeatherCard> createState() => _WeeklyWeatherCardState();
}

class _WeeklyWeatherCardState extends ConsumerState<_WeeklyWeatherCard> {
  final ScrollController _tableScrollController = ScrollController();

  @override
  void dispose() {
    _tableScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(fleetProvider).appSettings;
    final forecastAsync = ref.watch(
      weeklyWeatherForecastProvider(
        WeatherQuery(
          location: widget.selectedLocation,
          timeZone: settings.timeZone,
        ),
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
                    initialValue: widget.locations.contains(
                      widget.selectedLocation,
                    )
                        ? widget.selectedLocation
                        : widget.locations.first,
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
                      for (final location in widget.locations)
                        DropdownMenuItem(
                          value: location,
                          child: Text(
                            location,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: widget.onChanged,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                return Scrollbar(
                  controller: _tableScrollController,
                  thumbVisibility: true,
                  trackVisibility: true,
                  interactive: true,
                  child: SingleChildScrollView(
                    controller: _tableScrollController,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: constraints.maxWidth,
                      ),
                      child: DataTable(
                        headingRowHeight: 38,
                        headingRowColor: WidgetStateProperty.all(
                          const Color(0xFFEAF2FF),
                        ),
                        dataRowMinHeight: 42,
                        dataRowMaxHeight: 62,
                        horizontalMargin: 12,
                        columnSpacing: 22,
                        border: TableBorder(
                          top: const BorderSide(color: Color(0xFFBFDBFE)),
                          bottom: const BorderSide(color: Color(0xFFE2E8F0)),
                          horizontalInside: BorderSide(
                            color:
                                const Color(0xFFCBD5E1).withValues(alpha: 0.7),
                          ),
                        ),
                        headingTextStyle: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 12.5,
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
                                DataCell(
                                  Text(
                                    '${day.precipitationProbability} %',
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    formatWindSpeed(
                                      day.windSpeedKmh,
                                      settings.windUnit,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    formatWindSpeed(
                                      day.gustsKmh,
                                      settings.windUnit,
                                    ),
                                  ),
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
                                        width: 320,
                                        child: Text(
                                          day.assessment,
                                          maxLines: 2,
                                          overflow: TextOverflow.fade,
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
                  ),
                );
              },
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
