import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pocket_bot/utils/logger.dart';

class HostKeyCheck {
  final String host;
  final int port;
  final String keyType;
  final String fingerprint;

  /// Fingerprint seen on an earlier connection, when it no longer matches.
  final String? previousFingerprint;

  const HostKeyCheck({
    required this.host,
    required this.port,
    required this.keyType,
    required this.fingerprint,
    this.previousFingerprint,
  });

  bool get changed => previousFingerprint != null;
}

abstract class KnownHostStore {
  Future<String?> read(String hostId);

  Future<void> write(String hostId, String fingerprint);

  Future<void> forget(String hostId);
}

class SecureKnownHostStore implements KnownHostStore {
  const SecureKnownHostStore();

  static const _storage = FlutterSecureStorage();
  static const _key = 'ssh_known_hosts';

  Future<Map<String, String>> _load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map((key, value) => MapEntry('$key', '$value'));
    } catch (error) {
      Logger.warning('[SSH] Could not read known hosts: $error');
      return {};
    }
  }

  @override
  Future<String?> read(String hostId) async => (await _load())[hostId];

  @override
  Future<void> write(String hostId, String fingerprint) async {
    final all = await _load();
    all[hostId] = fingerprint;
    await _storage.write(key: _key, value: jsonEncode(all));
  }

  @override
  Future<void> forget(String hostId) async {
    final all = await _load();
    if (all.remove(hostId) == null) return;
    await _storage.write(key: _key, value: jsonEncode(all));
  }
}

class MemoryKnownHostStore implements KnownHostStore {
  final Map<String, String> entries = {};

  @override
  Future<String?> read(String hostId) async => entries[hostId];

  @override
  Future<void> write(String hostId, String fingerprint) async {
    entries[hostId] = fingerprint;
  }

  @override
  Future<void> forget(String hostId) async {
    entries.remove(hostId);
  }
}

typedef HostKeyPrompt = Future<bool> Function(HostKeyCheck check);

/// Trust-on-first-use host key pinning, like OpenSSH's `known_hosts`.
class SshHostKeys {
  static KnownHostStore store = const SecureKnownHostStore();

  /// Asks the user about unknown or changed keys. Without a prompt, unknown
  /// keys are pinned silently and changed keys are always rejected.
  static HostKeyPrompt? prompt;

  static String hostId(String host, int port) =>
      '${host.trim().toLowerCase()}:$port';

  static Future<bool> verify({
    required String host,
    required int port,
    required String keyType,
    required String fingerprint,
  }) async {
    final id = hostId(host, port);
    final known = await store.read(id);
    if (known == fingerprint) return true;

    final check = HostKeyCheck(
      host: host,
      port: port,
      keyType: keyType,
      fingerprint: fingerprint,
      previousFingerprint: known,
    );
    final ask = prompt;
    final accepted = ask == null ? known == null : await ask(check);
    if (!accepted) {
      Logger.warning('[SSH] Host key for $id rejected ($fingerprint)');
      return false;
    }
    await store.write(id, fingerprint);
    Logger.info('[SSH] Trusting host key for $id ($fingerprint)');
    return true;
  }

  static Future<void> forget(String host, int port) =>
      store.forget(hostId(host, port));
}
