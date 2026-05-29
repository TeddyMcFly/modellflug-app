import 'package:flutter/foundation.dart';

import 'device_info_model.dart';

DetectedDeviceInfo detectCurrentDeviceInfo() {
  final platformName = defaultTargetPlatform.name;
  return DetectedDeviceInfo(
    deviceType: 'App',
    operatingSystem: _titleCase(platformName),
    browserName: 'Flutter',
    browserVersion: '',
    platform: platformName,
    language: '',
    userAgent: '',
  );
}

String _titleCase(String value) {
  if (value.isEmpty) {
    return value;
  }
  return value.substring(0, 1).toUpperCase() + value.substring(1);
}
