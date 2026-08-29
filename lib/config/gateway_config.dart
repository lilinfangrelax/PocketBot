import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pocket_bot/models/message.dart';

/// Gateway configuration storage - supports multiple gateways
class GatewayConfig {
  static const _storage = FlutterSecureStorage();
  static const String _keyGateways = 'gateways_config';
  static const String _keyLastConnected = 'last_connected_gateway';

  /// Save multiple gateways
  static Future<void> saveGateways(List<GatewayInfo> gateways) async {
    final jsonList = gateways.map((g) => g.toJson()).toList();
    await _storage.write(
      key: _keyGateways,
      value: jsonEncode(jsonList),
    );
  }

  /// Load all saved gateways
  static Future<List<GatewayInfo>> loadGateways() async {
    final json = await _storage.read(key: _keyGateways);
    if (json != null) {
      final List<dynamic> jsonList = jsonDecode(json);
      return jsonList.map((j) => GatewayInfo.fromJson(j)).toList();
    }
    return [];
  }

  /// Add a new gateway
  static Future<List<GatewayInfo>> addGateway(GatewayInfo gateway) async {
    final gateways = await loadGateways();
    final existingIndex = gateways.indexWhere(
      (g) => g.connectionId == gateway.connectionId,
    );
    if (existingIndex >= 0) {
      gateways[existingIndex] = gateway; // Update
    } else {
      gateways.add(gateway);
    }
    await saveGateways(gateways);
    return gateways;
  }

  /// Remove a gateway
  static Future<List<GatewayInfo>> removeGateway(GatewayInfo gateway) async {
    final gateways = await loadGateways();
    gateways.removeWhere((g) => g.connectionId == gateway.connectionId);
    await saveGateways(gateways);
    return gateways;
  }

  /// Save last connected gateway key (host:port)
  static Future<void> saveLastConnected(String key) async {
    await _storage.write(key: _keyLastConnected, value: key);
  }

  /// Get last connected gateway key
  static Future<String?> getLastConnected() async {
    return await _storage.read(key: _keyLastConnected);
  }

  /// Legacy: Save single gateway (for backward compatibility)
  static Future<void> save(GatewayInfo gateway) async {
    await saveGateways([gateway]);
    await saveLastConnected(gateway.connectionId);
  }

  /// Legacy: Load saved gateway (returns first one or null)
  static Future<GatewayInfo?> load() async {
    final gateways = await loadGateways();
    if (gateways.isEmpty) return null;

    // Try to load last connected
    final lastKey = await getLastConnected();
    if (lastKey != null) {
      final last = gateways
          .where((g) =>
              g.connectionId == lastKey || '${g.host}:${g.port}' == lastKey)
          .firstOrNull;
      if (last != null) return last;
    }
    return gateways.first;
  }

  /// Legacy: Clear saved gateway
  static Future<void> clear() async {
    await _storage.delete(key: _keyGateways);
    await _storage.delete(key: _keyLastConnected);
  }

  /// Legacy: Check if gateway is saved
  static Future<bool> hasSaved() async {
    final gateways = await loadGateways();
    return gateways.isNotEmpty;
  }
}

/// App settings storage
class AppSettings {
  static const _storage = FlutterSecureStorage();

  /// Settings keys
  static const String _keyAutoConnect = 'auto_connect';
  static const String _keyThemeMode = 'theme_mode';
  static const String _keyNotifications = 'notifications';

  /// Auto connect
  static Future<bool> getAutoConnect() async {
    final value = await _storage.read(key: _keyAutoConnect);
    return value?.toLowerCase() == 'true';
  }

  static Future<void> setAutoConnect(bool value) async {
    await _storage.write(key: _keyAutoConnect, value: value.toString());
  }

  /// Theme mode
  static Future<String?> getThemeMode() async {
    return await _storage.read(key: _keyThemeMode);
  }

  static Future<void> setThemeMode(String mode) async {
    await _storage.write(key: _keyThemeMode, value: mode);
  }

  /// Notifications
  static Future<bool> getNotifications() async {
    final value = await _storage.read(key: _keyNotifications);
    return value?.toLowerCase() != 'false';
  }

  static Future<void> setNotifications(bool value) async {
    await _storage.write(key: _keyNotifications, value: value.toString());
  }

  /// Clear all settings
  static Future<void> clear() async {
    await _storage.deleteAll();
  }
}
