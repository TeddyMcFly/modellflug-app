import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

final weatherForecastProvider =
    FutureProvider.family<OpenMeteoWeather, WeatherQuery>((ref, query) {
  return OpenMeteoService.instance.forecast(query);
});

final weeklyWeatherForecastProvider = FutureProvider.family
    .autoDispose<List<DailyWeatherForecast>, WeatherQuery>((ref, query) {
  return OpenMeteoService.instance.weeklyForecast(query);
});

class WeatherQuery {
  final String location;
  final String timeZone;

  const WeatherQuery({
    required this.location,
    required this.timeZone,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WeatherQuery &&
          other.location == location &&
          other.timeZone == timeZone;

  @override
  int get hashCode => Object.hash(location, timeZone);
}

class AirfieldCoordinates {
  final String name;
  final double latitude;
  final double longitude;

  const AirfieldCoordinates({
    required this.name,
    required this.latitude,
    required this.longitude,
  });
}

class OpenMeteoWeather {
  final String location;
  final String condition;
  final double temperatureC;
  final double windSpeedKmh;
  final int windDirection;
  final double gustsKmh;
  final double pressureHpa;
  final double visibilityKm;
  final int precipitationProbability;
  final int cloudCover;
  final String sunset;
  final String assessment;
  final Color assessmentColor;
  final IconData assessmentIcon;
  final bool isLive;

  const OpenMeteoWeather({
    required this.location,
    required this.condition,
    required this.temperatureC,
    required this.windSpeedKmh,
    required this.windDirection,
    required this.gustsKmh,
    required this.pressureHpa,
    required this.visibilityKm,
    required this.precipitationProbability,
    required this.cloudCover,
    required this.sunset,
    required this.assessment,
    required this.assessmentColor,
    required this.assessmentIcon,
    required this.isLive,
  });
}

class DailyWeatherForecast {
  final DateTime date;
  final String label;
  final String condition;
  final double minTemperatureC;
  final double maxTemperatureC;
  final int precipitationProbability;
  final double windSpeedKmh;
  final double gustsKmh;
  final String sunset;
  final String assessment;
  final Color assessmentColor;
  final IconData assessmentIcon;
  final bool isLive;

  const DailyWeatherForecast({
    required this.date,
    required this.label,
    required this.condition,
    required this.minTemperatureC,
    required this.maxTemperatureC,
    required this.precipitationProbability,
    required this.windSpeedKmh,
    required this.gustsKmh,
    required this.sunset,
    required this.assessment,
    required this.assessmentColor,
    required this.assessmentIcon,
    required this.isLive,
  });
}

class OpenMeteoService {
  OpenMeteoService._();

  static final instance = OpenMeteoService._();
  static const _apiBase = 'https://api.open-meteo.com';
  static const _geocodingBase = 'https://geocoding-api.open-meteo.com';
  final _cache = <WeatherQuery, _WeatherCacheEntry>{};
  final _weeklyCache = <WeatherQuery, _WeeklyWeatherCacheEntry>{};
  final _coordinateCache = <String, AirfieldCoordinates>{};

  Future<OpenMeteoWeather> forecast(WeatherQuery query) async {
    final cached = _cache[query];
    if (cached != null &&
        DateTime.now().difference(cached.loadedAt) <
            const Duration(minutes: 20)) {
      return cached.weather;
    }

    try {
      final coordinates = await _coordinatesForLocation(query.location);
      final params = {
        'latitude': coordinates.latitude.toStringAsFixed(5),
        'longitude': coordinates.longitude.toStringAsFixed(5),
        'current':
            'temperature_2m,weather_code,wind_speed_10m,wind_direction_10m,wind_gusts_10m,surface_pressure,precipitation,cloud_cover',
        'hourly': 'visibility',
        'daily': 'sunset,precipitation_probability_max',
        'timezone': query.timeZone,
        'wind_speed_unit': 'kmh',
      };
      final uri = Uri.parse('$_apiBase/v1/forecast').replace(
        queryParameters: params,
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Open-Meteo HTTP ${response.statusCode}');
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final weather = _weatherFromJson(query.location, json);
      _cache[query] = _WeatherCacheEntry(weather, DateTime.now());
      return weather;
    } catch (_) {
      final fallback = fallbackWeather(query.location);
      _cache[query] = _WeatherCacheEntry(fallback, DateTime.now());
      return fallback;
    }
  }

  Future<List<DailyWeatherForecast>> weeklyForecast(WeatherQuery query) async {
    final cached = _weeklyCache[query];
    if (cached != null &&
        DateTime.now().difference(cached.loadedAt) <
            const Duration(minutes: 30)) {
      return cached.forecast;
    }

    try {
      final coordinates = await _coordinatesForLocation(query.location);
      final params = {
        'latitude': coordinates.latitude.toStringAsFixed(5),
        'longitude': coordinates.longitude.toStringAsFixed(5),
        'daily':
            'weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,wind_speed_10m_max,wind_gusts_10m_max,sunset',
        'timezone': query.timeZone,
        'wind_speed_unit': 'kmh',
        'forecast_days': '7',
      };
      final uri = Uri.parse('$_apiBase/v1/forecast').replace(
        queryParameters: params,
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Open-Meteo HTTP ${response.statusCode}');
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final forecast = _weeklyForecastFromJson(json);
      _weeklyCache[query] = _WeeklyWeatherCacheEntry(forecast, DateTime.now());
      return forecast;
    } catch (_) {
      final fallback = fallbackWeeklyForecast();
      _weeklyCache[query] = _WeeklyWeatherCacheEntry(fallback, DateTime.now());
      return fallback;
    }
  }

  Future<AirfieldCoordinates> _coordinatesForLocation(String location) async {
    final known = _knownCoordinatesForLocation(location);
    if (known != null) {
      return known;
    }

    final normalized = location.trim().toLowerCase();
    final cached = _coordinateCache[normalized];
    if (cached != null) {
      return cached;
    }

    if (normalized.length < 2) {
      throw StateError('Ort ist zu kurz fuer Geocoding.');
    }

    final uri = Uri.parse('$_geocodingBase/v1/search').replace(
      queryParameters: {
        'name': location.trim(),
        'count': '1',
        'language': 'de',
        'format': 'json',
      },
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Open-Meteo Geocoding HTTP ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final results = json['results'] as List<dynamic>? ?? const [];
    if (results.isEmpty || results.first is! Map<String, dynamic>) {
      throw StateError('Keine Koordinaten fuer "$location" gefunden.');
    }

    final first = results.first as Map<String, dynamic>;
    final latitude = _number(first['latitude'], fallback: double.nan);
    final longitude = _number(first['longitude'], fallback: double.nan);
    if (latitude.isNaN || longitude.isNaN) {
      throw StateError('Ungueltige Koordinaten fuer "$location".');
    }

    final name = first['name']?.toString().trim();
    final country = first['country']?.toString().trim();
    final resolved = AirfieldCoordinates(
      name: [
        if (name != null && name.isNotEmpty) name else location.trim(),
        if (country != null && country.isNotEmpty) country,
      ].join(', '),
      latitude: latitude,
      longitude: longitude,
    );
    _coordinateCache[normalized] = resolved;
    return resolved;
  }
}

class _WeatherCacheEntry {
  final OpenMeteoWeather weather;
  final DateTime loadedAt;

  const _WeatherCacheEntry(this.weather, this.loadedAt);
}

class _WeeklyWeatherCacheEntry {
  final List<DailyWeatherForecast> forecast;
  final DateTime loadedAt;

  const _WeeklyWeatherCacheEntry(this.forecast, this.loadedAt);
}

AirfieldCoordinates? _knownCoordinatesForLocation(String location) {
  final normalized = location.toLowerCase();

  if (normalized.contains('lmfc') ||
      normalized.contains('lohburg') ||
      normalized.contains('waltrop')) {
    return const AirfieldCoordinates(
      name: 'LMFC-Fluggelaende',
      latitude: 51.621,
      longitude: 7.397,
    );
  }

  if (normalized.contains('bochum') ||
      normalized.contains('suedhang') ||
      normalized.contains('südhang')) {
    return const AirfieldCoordinates(
      name: 'Bochum',
      latitude: 51.4818,
      longitude: 7.2162,
    );
  }

  if (normalized.contains('nord')) {
    return const AirfieldCoordinates(
      name: 'Startbahn Nord',
      latitude: 51.625,
      longitude: 7.401,
    );
  }

  return null;
}

OpenMeteoWeather _weatherFromJson(String location, Map<String, dynamic> json) {
  final current = json['current'] as Map<String, dynamic>? ?? const {};
  final hourly = json['hourly'] as Map<String, dynamic>? ?? const {};
  final daily = json['daily'] as Map<String, dynamic>? ?? const {};
  final visibilityValues = hourly['visibility'] as List<dynamic>? ?? const [];
  final sunsetValues = daily['sunset'] as List<dynamic>? ?? const [];
  final rainProbabilityValues =
      daily['precipitation_probability_max'] as List<dynamic>? ?? const [];

  final code = _number(current['weather_code']).round();
  final temperature = _number(current['temperature_2m']);
  final wind = _number(current['wind_speed_10m']);
  final gusts = _number(current['wind_gusts_10m']);
  final rainProbability = rainProbabilityValues.isEmpty
      ? (_number(current['precipitation']) > 0 ? 70 : 10)
      : _number(rainProbabilityValues.first).round();
  final cloudCover = _number(current['cloud_cover']).round();
  final weather = _buildAssessment(
    windKmh: wind,
    gustsKmh: gusts,
    rainProbability: rainProbability,
    cloudCover: cloudCover,
    weatherCode: code,
  );

  return OpenMeteoWeather(
    location: location,
    condition: _conditionForCode(code, cloudCover),
    temperatureC: temperature,
    windSpeedKmh: wind,
    windDirection: _number(current['wind_direction_10m']).round(),
    gustsKmh: gusts,
    pressureHpa: _number(current['surface_pressure'], fallback: 1015),
    visibilityKm: visibilityValues.isEmpty
        ? 10
        : (_number(visibilityValues.first) / 1000).clamp(0.0, 99.0),
    precipitationProbability: rainProbability,
    cloudCover: cloudCover,
    sunset: _formatSunset(sunsetValues.isEmpty ? null : sunsetValues.first),
    assessment: weather.$1,
    assessmentColor: weather.$2,
    assessmentIcon: weather.$3,
    isLive: true,
  );
}

List<DailyWeatherForecast> _weeklyForecastFromJson(Map<String, dynamic> json) {
  final daily = json['daily'] as Map<String, dynamic>? ?? const {};
  final dates = daily['time'] as List<dynamic>? ?? const [];
  final codes = daily['weather_code'] as List<dynamic>? ?? const [];
  final maxTemps = daily['temperature_2m_max'] as List<dynamic>? ?? const [];
  final minTemps = daily['temperature_2m_min'] as List<dynamic>? ?? const [];
  final rainValues =
      daily['precipitation_probability_max'] as List<dynamic>? ?? const [];
  final windValues = daily['wind_speed_10m_max'] as List<dynamic>? ?? const [];
  final gustValues = daily['wind_gusts_10m_max'] as List<dynamic>? ?? const [];
  final sunsetValues = daily['sunset'] as List<dynamic>? ?? const [];
  final count = dates.length.clamp(0, 7);

  return [
    for (var index = 0; index < count; index++)
      _dailyForecastAt(
        dates: dates,
        codes: codes,
        maxTemps: maxTemps,
        minTemps: minTemps,
        rainValues: rainValues,
        windValues: windValues,
        gustValues: gustValues,
        sunsetValues: sunsetValues,
        index: index,
      ),
  ];
}

DailyWeatherForecast _dailyForecastAt({
  required List<dynamic> dates,
  required List<dynamic> codes,
  required List<dynamic> maxTemps,
  required List<dynamic> minTemps,
  required List<dynamic> rainValues,
  required List<dynamic> windValues,
  required List<dynamic> gustValues,
  required List<dynamic> sunsetValues,
  required int index,
}) {
  final date = DateTime.tryParse(dates[index].toString()) ?? DateTime.now();
  final code = index < codes.length ? _number(codes[index]).round() : 0;
  final wind = index < windValues.length ? _number(windValues[index]) : 0.0;
  final gusts = index < gustValues.length ? _number(gustValues[index]) : 0.0;
  final rain =
      index < rainValues.length ? _number(rainValues[index]).round() : 0;
  final weather = _buildAssessment(
    windKmh: wind,
    gustsKmh: gusts,
    rainProbability: rain,
    cloudCover: code <= 3 ? 35 : 70,
    weatherCode: code,
  );

  return DailyWeatherForecast(
    date: date,
    label: _dayLabel(date, index),
    condition: _conditionForCode(code, code <= 3 ? 35 : 70),
    minTemperatureC: index < minTemps.length ? _number(minTemps[index]) : 0.0,
    maxTemperatureC: index < maxTemps.length ? _number(maxTemps[index]) : 0.0,
    precipitationProbability: rain,
    windSpeedKmh: wind,
    gustsKmh: gusts,
    sunset:
        _formatSunset(index < sunsetValues.length ? sunsetValues[index] : null),
    assessment: weather.$1,
    assessmentColor: weather.$2,
    assessmentIcon: weather.$3,
    isLive: true,
  );
}

OpenMeteoWeather fallbackWeather(String location) {
  return OpenMeteoWeather(
    location: location,
    condition: 'leicht bewoelkt',
    temperatureC: 19,
    windSpeedKmh: 12,
    windDirection: 225,
    gustsKmh: 19,
    pressureHpa: 1016,
    visibilityKm: 12,
    precipitationProbability: 10,
    cloudCover: 35,
    sunset: '21:17',
    assessment:
        'Sehr gute Bedingungen. Wenig Wind, trocken und hell genug fuer einen Flugplatzbesuch.',
    assessmentColor: const Color(0xFF166534),
    assessmentIcon: Icons.thumb_up_alt_rounded,
    isLive: false,
  );
}

List<DailyWeatherForecast> fallbackWeeklyForecast() {
  final now = DateTime.now();
  const rain = [10, 15, 20, 35, 45, 25, 15];
  const wind = [12, 14, 18, 22, 26, 16, 13];
  const gusts = [19, 22, 28, 35, 42, 25, 21];
  const codes = [1, 2, 3, 51, 61, 2, 1];
  return [
    for (var index = 0; index < 7; index++)
      () {
        final weather = _buildAssessment(
          windKmh: wind[index].toDouble(),
          gustsKmh: gusts[index].toDouble(),
          rainProbability: rain[index],
          cloudCover: codes[index] <= 3 ? 45 : 80,
          weatherCode: codes[index],
        );
        final date = now.add(Duration(days: index));
        return DailyWeatherForecast(
          date: date,
          label: _dayLabel(date, index),
          condition:
              _conditionForCode(codes[index], codes[index] <= 3 ? 45 : 80),
          minTemperatureC: 11 + index % 3,
          maxTemperatureC: 19 + index % 4,
          precipitationProbability: rain[index],
          windSpeedKmh: wind[index].toDouble(),
          gustsKmh: gusts[index].toDouble(),
          sunset: '21:${(17 + index).toString().padLeft(2, '0')}',
          assessment: weather.$1,
          assessmentColor: weather.$2,
          assessmentIcon: weather.$3,
          isLive: false,
        );
      }(),
  ];
}

double _number(Object? value, {double fallback = 0}) {
  if (value is num) {
    return value.toDouble();
  }
  return fallback;
}

String _dayLabel(DateTime date, int index) {
  if (index == 0) {
    return 'Heute';
  }
  if (index == 1) {
    return 'Morgen';
  }
  const weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
  return '${weekdays[date.weekday - 1]} ${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.';
}

String _formatSunset(Object? value) {
  final raw = value?.toString() ?? '';
  if (raw.length >= 16) {
    return raw.substring(11, 16);
  }
  return '21:17';
}

String _conditionForCode(int code, int cloudCover) {
  if (code == 0) return 'sonnig';
  if (code <= 3) {
    return cloudCover < 45 ? 'leicht bewoelkt' : 'bewoelkt';
  }
  if (code == 45 || code == 48) return 'neblig';
  if (code >= 51 && code <= 67) return 'Regen moeglich';
  if (code >= 71 && code <= 77) return 'Schnee';
  if (code >= 80 && code <= 82) return 'Schauer';
  if (code >= 95) return 'Gewitter';
  return 'wechselhaft';
}

(String, Color, IconData) _buildAssessment({
  required double windKmh,
  required double gustsKmh,
  required int rainProbability,
  required int cloudCover,
  required int weatherCode,
}) {
  final dry = rainProbability <= 20 && weatherCode < 51;
  final calm = windKmh <= 16 && gustsKmh <= 25;
  final sunny = cloudCover <= 55 && weatherCode <= 3;

  if (dry && calm && sunny) {
    return (
      'Sehr gute Bedingungen. Wenig Wind, trocken und freundlich - das lohnt sich fuer den Flugplatz.',
      const Color(0xFF166534),
      Icons.thumb_up_alt_rounded,
    );
  }

  if (!dry || gustsKmh > 35 || windKmh > 25 || weatherCode >= 80) {
    return (
      'Lieber vorsichtig planen. Regen, Wind oder starke Boeen koennen den Flugtag deutlich stoeren.',
      const Color(0xFFB45309),
      Icons.warning_amber_rounded,
    );
  }

  return (
    'Solide Bedingungen. Vor dem Start Windrichtung, Boeen und Platzsituation kurz pruefen.',
    const Color(0xFF1D4ED8),
    Icons.info_rounded,
  );
}

String formatTemperature(double celsius, String unit) {
  if (unit == 'Fahrenheit') {
    return '${(celsius * 9 / 5 + 32).round()} F';
  }
  return '${celsius.round()} C';
}

String formatWindSpeed(double kmh, String unit) {
  return switch (unit) {
    'm/s' => '${(kmh / 3.6).toStringAsFixed(1)} m/s',
    'kn' => '${(kmh / 1.852).round()} kn',
    _ => '${kmh.round()} km/h',
  };
}

String formatDistance(double km, String unit) {
  if (unit == 'mi') {
    return '${(km * 0.621371).toStringAsFixed(1)} mi';
  }
  return '${km.toStringAsFixed(km < 10 ? 1 : 0)} km';
}

String windDirectionLabel(int degrees) {
  const labels = ['N', 'NO', 'O', 'SO', 'S', 'SW', 'W', 'NW'];
  final index = ((degrees + 22.5) ~/ 45) % labels.length;
  return labels[index];
}
