import 'package:flutter/material.dart';

import '../../core/widgets/app_scaffold.dart';

class WebcamPage extends StatelessWidget {
  const WebcamPage({super.key});

  static const livePlaceholderAsset = 'assets/webcam/home_airfield.jpg';

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Webcam',
      subtitle:
          'Platzkameras, Wetterhinweise und Sichtbedingungen fuer den Flugtag.',
      action: FilledButton.icon(
        onPressed: () {},
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Aktualisieren'),
      ),
      children: const [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CameraPreview(),
            SizedBox(height: 12),
            _AirfieldWeatherCard(),
            SizedBox(height: 12),
            _WeeklyWebcamShots(),
          ],
        ),
      ],
    );
  }
}

class _CameraPreview extends StatelessWidget {
  const _CameraPreview();

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
            const Positioned(
              left: 22,
              bottom: 22,
              right: 22,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'LMFC-Fluggelaende',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
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

class _AirfieldWeatherCard extends StatelessWidget {
  const _AirfieldWeatherCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Wetter am Platz',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 16),
            Wrap(
              spacing: 24,
              runSpacing: 16,
              children: [
                _WeatherValue(
                  icon: Icons.cloud_rounded,
                  label: 'Bewoelkung',
                  value: 'leicht bewoelkt',
                ),
                _WeatherValue(
                  icon: Icons.thermostat_rounded,
                  label: 'Temperatur',
                  value: '22 C',
                ),
                _WeatherValue(
                  icon: Icons.air_rounded,
                  label: 'Wind',
                  value: '8 km/h NW',
                ),
                _WeatherValue(
                  icon: Icons.speed_rounded,
                  label: 'Boeen',
                  value: '18 km/h',
                ),
                _WeatherValue(
                  icon: Icons.compress_rounded,
                  label: 'Luftdruck',
                  value: '1016 hPa',
                ),
                _WeatherValue(
                  icon: Icons.visibility_rounded,
                  label: 'Sichtweite',
                  value: '12 km',
                ),
                _WeatherValue(
                  icon: Icons.wb_twilight_rounded,
                  label: 'Sonnenuntergang',
                  value: '21:17',
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
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
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

class _WeeklyWebcamShots extends StatelessWidget {
  const _WeeklyWebcamShots();

  @override
  Widget build(BuildContext context) {
    const days = [
      'Heute',
      'Gestern',
      '14.05.',
      '13.05.',
      '12.05.',
      '11.05.',
      '10.05.',
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Webcam-Aufnahmen der letzten Tage',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 126,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: days.length,
                separatorBuilder: (context, index) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  return SizedBox(
                    width: 150,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: AspectRatio(
                            aspectRatio: 8 / 5,
                            child: Image.asset(
                              WebcamPage.livePlaceholderAsset,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          days[index],
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
