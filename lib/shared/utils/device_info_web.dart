import 'package:web/web.dart' as web;

import 'device_info_model.dart';

DetectedDeviceInfo detectCurrentDeviceInfo() {
  final navigator = web.window.navigator;
  final userAgent = navigator.userAgent;
  final screen = web.window.screen;
  final browser = _browserFromUserAgent(userAgent);
  final operatingSystem = _operatingSystemFromUserAgent(userAgent);
  final touchPoints = navigator.maxTouchPoints;

  return DetectedDeviceInfo(
    deviceType: _deviceTypeFromUserAgent(userAgent, touchPoints),
    operatingSystem: operatingSystem,
    browserName: browser.name,
    browserVersion: browser.version,
    platform: navigator.platform,
    language: navigator.language,
    userAgent: userAgent,
    screenWidth: screen.width,
    screenHeight: screen.height,
    viewportWidth: web.window.innerWidth,
    viewportHeight: web.window.innerHeight,
    pixelRatio: web.window.devicePixelRatio,
    touchPoints: touchPoints,
    cpuCores: navigator.hardwareConcurrency,
  );
}

({String name, String version}) _browserFromUserAgent(String userAgent) {
  final checks = <({String name, RegExp pattern})>[
    (name: 'Edge', pattern: RegExp(r'Edg/([0-9.]+)')),
    (name: 'Opera', pattern: RegExp(r'OPR/([0-9.]+)')),
    (name: 'Firefox', pattern: RegExp(r'Firefox/([0-9.]+)')),
    (name: 'Chrome', pattern: RegExp(r'(?:Chrome|CriOS)/([0-9.]+)')),
    (name: 'Safari', pattern: RegExp(r'Version/([0-9.]+).*Safari')),
  ];

  for (final check in checks) {
    final match = check.pattern.firstMatch(userAgent);
    if (match != null) {
      return (name: check.name, version: _majorVersion(match.group(1) ?? ''));
    }
  }

  return (name: 'Browser', version: '');
}

String _operatingSystemFromUserAgent(String userAgent) {
  if (userAgent.contains('Windows')) {
    return 'Windows';
  }
  if (userAgent.contains('Android')) {
    return 'Android';
  }
  if (userAgent.contains('iPhone')) {
    return 'iPhone';
  }
  if (userAgent.contains('iPad')) {
    return 'iPad';
  }
  if (userAgent.contains('Mac OS X') || userAgent.contains('Macintosh')) {
    return 'macOS';
  }
  if (userAgent.contains('Linux')) {
    return 'Linux';
  }
  return 'Unbekannt';
}

String _deviceTypeFromUserAgent(String userAgent, int touchPoints) {
  final lower = userAgent.toLowerCase();
  if (lower.contains('ipad') || lower.contains('tablet')) {
    return 'Tablet';
  }
  if (lower.contains('mobi') ||
      lower.contains('iphone') ||
      lower.contains('android') && touchPoints > 0) {
    return 'Smartphone';
  }
  return touchPoints > 0 ? 'Touch-Geraet' : 'Computer';
}

String _majorVersion(String version) {
  if (version.isEmpty) {
    return '';
  }
  return version.split('.').first;
}
