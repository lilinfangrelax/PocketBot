import 'package:package_info_plus/package_info_plus.dart';

/// App version utility
class AppVersion {
  static PackageInfo? _packageInfo;

  /// Initialize version info (call once at app startup)
  static Future<void> init() async {
    _packageInfo = await PackageInfo.fromPlatform();
  }

  /// Get base version (e.g., "1.0.0")
  static String get baseVersion => _packageInfo?.version ?? '1.0.0';

  /// Get build number (e.g., "dev_20260214_103100")
  /// This comes from --build-name parameter in flutter build
  static String get buildNumber => _packageInfo?.buildNumber ?? '';

  /// Get full version string
  /// Format: "1.0.0+dev_20260214_103100" or just "1.0.0" if no build number
  static String get fullVersion {
    final version = baseVersion;
    final build = buildNumber;
    if (build.isEmpty) return version;
    return '$version+$build';
  }

  /// Get display version (user-friendly format)
  /// Format: "v1.0.0 (dev_20260214_103100)" or "v1.0.0"
  static String get displayVersion {
    final version = baseVersion;
    final build = buildNumber;
    if (build.isEmpty) return 'v$version';
    return 'v$version ($build)';
  }
}
