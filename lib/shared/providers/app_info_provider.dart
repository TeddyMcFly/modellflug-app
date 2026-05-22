import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

final appInfoProvider = FutureProvider<PackageInfo>((ref) {
  return PackageInfo.fromPlatform();
});

String formatAppVersion(PackageInfo info) {
  final version = info.version.trim();
  final buildNumber = info.buildNumber.trim();

  if (version.isEmpty && buildNumber.isEmpty) {
    return 'nicht verfuegbar';
  }
  if (buildNumber.isEmpty) {
    return version;
  }
  if (version.isEmpty) {
    return 'Build $buildNumber';
  }

  return '$version (Build $buildNumber)';
}

String formatNavigationAppVersion(PackageInfo info) {
  final version = info.version.trim();
  final buildNumber = info.buildNumber.trim();

  if (version.isEmpty && buildNumber.isEmpty) {
    return 'Version nicht verfuegbar';
  }
  if (buildNumber.isEmpty) {
    return 'Version $version';
  }
  if (version.isEmpty) {
    return 'Build $buildNumber';
  }

  return 'Version $version+$buildNumber';
}
