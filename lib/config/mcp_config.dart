import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pocket_bot/models/mcp_server_config.dart';

/// MCP servers are kept in secure storage because env vars and headers
/// often carry API tokens.
class McpConfig {
  static const _storage = FlutterSecureStorage();
  static const _key = 'mcp_servers';

  static Future<List<McpServerConfig>> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((item) => McpServerConfig.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  static Future<void> save(List<McpServerConfig> servers) async {
    await _storage.write(
      key: _key,
      value: jsonEncode(servers.map((server) => server.toJson()).toList()),
    );
  }
}
