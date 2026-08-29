/// OTA Hot Update Configuration
/// Supports specifying server IP address for hot update checks

/// OTA Channel enum
enum OtaChannel {
  stable,
  dev,
  auto;

  String get displayName {
    switch (this) {
      case stable:
        return '稳定版';
      case dev:
        return '开发版（最新构建）';
      case auto:
        return '自动';
    }
  }
}

/// OTA Hot Update Configuration
class OtaConfig {
  /// OTA server URL
  /// Can be IP address or domain name
  /// Example: 'http://192.168.1.100:3000' or 'http://localhost:3000'
  static String serverUrl = 'http://localhost:3000';

  /// Whether to enable OTA update checks
  static bool enabled = true;

  /// OTA Channel (stable/dev/auto)
  static OtaChannel channel = OtaChannel.stable;

  /// Check update interval (hours)
  static int checkIntervalHours = 6;

  /// Auto-download updates on WiFi
  static bool autoDownloadOnWifi = true;

  /// Auto-download updates on mobile network
  static bool autoDownloadOnMobile = false;

  /// Mandatory update version (user must update)
  static String? mandatoryVersion;

  /// Configure server address
  /// [url] OTA server URL, supports IP or domain name
  static void configure(String url) {
    // Remove trailing slash
    serverUrl = url.replaceAll(RegExp(r'/$'), '');
    
    // Validate URL format
    if (!serverUrl.startsWith('http://') && !serverUrl.startsWith('https://')) {
      serverUrl = 'http://$serverUrl';
    }
  }

  /// Set OTA channel
  static void setChannel(OtaChannel newChannel) {
    channel = newChannel;
  }

  /// Get check update API URL with channel parameter
  static String get checkUpdateUrl {
    final channelParam = channel == OtaChannel.auto ? 'dev' : channel.name;
    return '$serverUrl/api/check-update?channel=$channelParam';
  }

  /// Get effective channel for update check
  /// If auto, returns 'dev' to get latest
  static String get effectiveChannel {
    return channel == OtaChannel.auto ? 'dev' : channel.name;
  }

  /// Get version suffix for current channel
  /// Dev channel returns '-dev.1', stable returns ''
  static String get versionSuffix {
    if (channel == OtaChannel.dev || channel == OtaChannel.auto) {
      return '-dev.1';
    }
    return '';
  }

  /// Build full version string with channel suffix
  /// [baseVersion] Base version number (e.g., '1.0.0')
  static String buildVersion(String baseVersion) {
    final suffix = versionSuffix;
    if (suffix.isEmpty) return baseVersion;
    return '$baseVersion$suffix';
  }

  /// Parse version and strip channel suffix
  /// e.g., '1.0.0-dev.1' -> '1.0.0'
  static String parseVersion(String version) {
    return version.replaceAll(RegExp(r'-dev\.\d+$'), '');
  }

  /// Get update package download URL
  /// [version] Version number
  static String getDownloadUrl(String version) {
    return '$serverUrl/updates/update-$version.zip';
  }

  /// Reset to default values
  static void reset() {
    serverUrl = 'http://localhost:3000';
    enabled = true;
    channel = OtaChannel.stable;
    checkIntervalHours = 6;
    autoDownloadOnWifi = true;
    autoDownloadOnMobile = false;
    mandatoryVersion = null;
  }
}
