import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pocket_bot/utils/logger.dart';

/// User profile configuration storage
class UserConfigStorage {
  static const _storage = FlutterSecureStorage();
  static const _keyUserConfig = 'user_config';

  /// User configuration model
  static Future<Map<String, dynamic>?> loadUserConfig() async {
    try {
      final json = await _storage.read(key: _keyUserConfig);
      if (json != null) {
        return jsonDecode(json) as Map<String, dynamic>;
      }
    } catch (e) {
      Logger.warning('[UserConfig] Error loading config: $e');
    }
    return null;
  }

  /// Save user configuration
  static Future<void> saveUserConfig(Map<String, dynamic> config) async {
    try {
      await _storage.write(
        key: _keyUserConfig,
        value: jsonEncode(config),
      );
      Logger.info('[UserConfig] Config saved');
    } catch (e) {
      Logger.warning('[UserConfig] Error saving config: $e');
    }
  }

  /// Get user avatar path (base64 encoded)
  static Future<String?> getUserAvatar() async {
    final config = await loadUserConfig();
    return config?['avatar_path'] as String?;
  }

  /// Save user avatar path (base64 encoded image)
  static Future<void> saveUserAvatar(String base64Image) async {
    final config = await loadUserConfig() ?? {};
    config['avatar_path'] = base64Image;
    await saveUserConfig(config);
    Logger.info('[UserConfig] Avatar saved (${base64Image.length} bytes)');
  }

  /// Clear user avatar
  static Future<void> clearUserAvatar() async {
    final config = await loadUserConfig();
    if (config != null && config.containsKey('avatar_path')) {
      config.remove('avatar_path');
      await saveUserConfig(config);
      Logger.info('[UserConfig] Avatar cleared');
    }
  }

  /// Get user display name
  static Future<String?> getUserName() async {
    final config = await loadUserConfig();
    return config?['user_name'] as String?;
  }

  /// Save user display name
  static Future<void> saveUserName(String name) async {
    final config = await loadUserConfig() ?? {};
    config['user_name'] = name;
    await saveUserConfig(config);
    Logger.info('[UserConfig] User name saved: $name');
  }

  /// Clear all user config
  static Future<void> clearAll() async {
    await _storage.delete(key: _keyUserConfig);
    Logger.info('[UserConfig] All config cleared');
  }
}
