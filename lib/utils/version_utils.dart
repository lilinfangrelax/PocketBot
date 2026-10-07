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

  /// Android versionCode. This is not part of the user-facing version.
  static String get buildNumber => _packageInfo?.buildNumber ?? '';

  /// Semantic version plus the Android versionCode, when one is present.
  static String get fullVersion {
    final version = baseVersion;
    final build = buildNumber;
    if (build.isEmpty) return version;
    return '$version+$build';
  }

  /// User-facing version. The Android versionCode stays out of this string.
  static String get displayVersion => 'v$baseVersion';
}
