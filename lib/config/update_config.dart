import 'package:pocket_bot/config/update_channel.dart';
import 'package:pocket_bot/utils/version_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

export 'package:pocket_bot/config/update_channel.dart';

/// Persisted update channel selection.
class UpdateConfig {
  static const _channelKey = 'update_channel';
  static const _devShaKey = 'dev_update_sha256';

  static UpdateChannel _channel = UpdateChannel.stable;
  static String? _devSha256;

  static UpdateChannel get channel => _channel;

  /// SHA-256 of the dev-channel APK last handed to the installer.
  static String? get installedDevSha256 => _devSha256;

  static String get githubOwner => UpdateConstants.githubOwner;
  static String get githubRepo => UpdateConstants.githubRepo;
  static String get repoUrl => UpdateConstants.repoUrl;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _channel = resolveUpdateChannel(
      savedId: prefs.getString(_channelKey),
      currentVersion: AppVersion.baseVersion,
    );
    _devSha256 = _normalizeSha(prefs.getString(_devShaKey));
  }

  static Future<void> setChannel(UpdateChannel channel) async {
    _channel = channel;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_channelKey, channel.id);
  }

  static Future<void> setInstalledDevSha256(String sha256) async {
    final normalized = _normalizeSha(sha256);
    _devSha256 = normalized;
    final prefs = await SharedPreferences.getInstance();
    if (normalized == null) {
      await prefs.remove(_devShaKey);
      return;
    }
    await prefs.setString(_devShaKey, normalized);
  }

  static String? _normalizeSha(String? sha256) {
    final value = sha256?.trim().toLowerCase();
    if (value == null || value.isEmpty) return null;
    return value;
  }
}
