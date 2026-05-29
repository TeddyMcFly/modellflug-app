class DetectedDeviceInfo {
  final String deviceType;
  final String operatingSystem;
  final String browserName;
  final String browserVersion;
  final String platform;
  final String language;
  final String userAgent;
  final int? screenWidth;
  final int? screenHeight;
  final int? viewportWidth;
  final int? viewportHeight;
  final double? pixelRatio;
  final int? touchPoints;
  final int? cpuCores;

  const DetectedDeviceInfo({
    required this.deviceType,
    required this.operatingSystem,
    required this.browserName,
    required this.browserVersion,
    required this.platform,
    required this.language,
    required this.userAgent,
    this.screenWidth,
    this.screenHeight,
    this.viewportWidth,
    this.viewportHeight,
    this.pixelRatio,
    this.touchPoints,
    this.cpuCores,
  });

  String get browserLabel {
    if (browserVersion.isEmpty) {
      return browserName;
    }
    return '$browserName $browserVersion';
  }

  String get deviceLabel {
    final parts = [
      if (operatingSystem.isNotEmpty) operatingSystem,
      if (deviceType.isNotEmpty) deviceType,
    ];
    return parts.isEmpty ? 'Unbekanntes Geraet' : parts.join(' ');
  }

  String get screenLabel {
    if (screenWidth == null || screenHeight == null) {
      return '-';
    }
    return '${screenWidth}x$screenHeight';
  }

  String get viewportLabel {
    if (viewportWidth == null || viewportHeight == null) {
      return '-';
    }
    return '${viewportWidth}x$viewportHeight';
  }

  Map<String, Object?> toJson() {
    return {
      'deviceType': deviceType,
      'deviceLabel': deviceLabel,
      'operatingSystem': operatingSystem,
      'browserName': browserName,
      'browserVersion': browserVersion,
      'browserLabel': browserLabel,
      'platform': platform,
      'language': language,
      'screenWidth': screenWidth,
      'screenHeight': screenHeight,
      'screenLabel': screenLabel,
      'viewportWidth': viewportWidth,
      'viewportHeight': viewportHeight,
      'viewportLabel': viewportLabel,
      'pixelRatio': pixelRatio,
      'touchPoints': touchPoints,
      'cpuCores': cpuCores,
      'userAgent': userAgent,
    };
  }
}
