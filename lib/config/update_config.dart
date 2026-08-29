import 'package:pocket_bot/config/update_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';

export 'package:pocket_bot/config/update_channel.dart';

/// Persisted update channel selection.
class UpdateConfig {
  static const _channelKey = 'update_channel';

  static UpdateChannel _channel = UpdateChannel.stable;

  static UpdateChannel get channel => _channel;

  static String get githubOwner => UpdateConstants.githubOwner;
  static String get githubRepo => UpdateConstants.githubRepo;
  static String get repoUrl => UpdateConstants.repoUrl;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _channel = UpdateChannel.fromId(prefs.getString(_channelKey));
  }

  static Future<void> setChannel(UpdateChannel channel) async {
    _channel = channel;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_channelKey, channel.id);
  }
}
