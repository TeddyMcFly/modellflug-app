import 'package:flutter_test/flutter_test.dart';
import 'package:modellflug_app/shared/services/open_meteo_service.dart';

void main() {
  group('buildFlyingWeatherAssessment', () {
    test('rates calm, dry and friendly weather as good', () {
      final assessment = buildFlyingWeatherAssessment(
        windKmh: goodFlyingWindMaxKmh,
        gustsKmh: goodFlyingGustsMaxKmh,
        rainProbability: goodFlyingRainProbabilityMax,
        cloudCover: 100,
        weatherCode: 2,
      );

      expect(assessment.level, WeatherAssessmentLevel.good);
    });

    test('rates rain probability above the good limit as caution', () {
      final assessment = buildFlyingWeatherAssessment(
        windKmh: 12,
        gustsKmh: 19,
        rainProbability: cautionRainProbabilityMin,
        cloudCover: 35,
        weatherCode: 2,
      );

      expect(assessment.level, WeatherAssessmentLevel.caution);
    });

    test('rates active rain as caution regardless of low rain probability', () {
      final assessment = buildFlyingWeatherAssessment(
        windKmh: 8,
        gustsKmh: 13,
        rainProbability: 10,
        cloudCover: 70,
        weatherCode: 51,
      );

      expect(assessment.level, WeatherAssessmentLevel.caution);
    });
  });
}
