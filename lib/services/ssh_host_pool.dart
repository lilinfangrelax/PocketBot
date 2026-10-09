import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:pocket_bot/models/message.dart';
import 'package:pocket_bot/services/acp_transport.dart';
import 'package:pocket_bot/utils/logger.dart';

enum HostStatus { unknown, checking, online, offline }

class HostState {
  final HostStatus status;
  final String? error;
  final DateTime? checkedAt;

  const HostState(this.status, {this.error, this.checkedAt});

  bool get isOnline => status == HostStatus.online;
}

typedef SshClientOpener = Future<SSHClient> Function(GatewayInfo host);

/// Strips the `CODE:` prefix the transport puts on SSH errors.
String hostErrorText(Object error) {
  var text = error.toString().replaceFirst(RegExp(r'^(Exception: )+'), '');
  final match = RegExp(r'^[A-Z_]+:').firstMatch(text);
  if (match != null) text = text.substring(match.end);
  return text.trim().isEmpty ? 'SSH 连接失败' : text.trim();
}

/// One SSH login per saved host. Folder browsing and every agent on the host
/// share that client, so "online" means the login is up, not just that the
/// port answers.
class SshHostPool extends ChangeNotifier {
  SshHostPool({SshClientOpener? open}) : _open = open ?? openSshClient;

  final SshClientOpener _open;
  final Map<String, SSHClient> _clients = {};
  final Map<String, Future<SSHClient>> _opening = {};
  final Map<String, HostState> _states = {};
  bool _disposed = false;

  HostState stateOf(GatewayInfo host) =>
      _states[host.hostId] ?? const HostState(HostStatus.unknown);

  bool isConnected(GatewayInfo host) {
    final client = _clients[host.hostId];
    return client != null && !client.isClosed;
  }

  /// The shared, authenticated client for [host], logging in when needed.
  Future<SSHClient> client(GatewayInfo host) {
    if (host.kind != AgentTransportKind.ssh) {
      throw ArgumentError('Only SSH hosts have a shared client');
    }
    final id = host.hostId;
    final existing = _clients[id];
    if (existing != null && !existing.isClosed) return Future.value(existing);
    // The callback must not return the removed future: whenComplete would
    // then wait on itself.
    return _opening[id] ??= _connect(id, host).whenComplete(() {
      _opening.remove(id);
    });
  }

  Future<SSHClient> _connect(String id, GatewayInfo host) async {
    _set(id, const HostState(HostStatus.checking));
    final started = DateTime.now();
    Logger.debug('[SSH] Logging in to ${host.hostLabel}');
    try {
      final client = await _open(host);
      if (_disposed) {
        client.close();
        throw StateError('SSH host pool closed');
      }
      _clients[id] = client;
      Logger.info('[SSH] ${host.hostLabel} online '
          '(${DateTime.now().difference(started).inMilliseconds} ms)');
      _set(id, HostState(HostStatus.online, checkedAt: DateTime.now()));
      client.done.then(
        (_) => _dropped(id, client),
        onError: (Object error) => _dropped(id, client, error),
      );
      return client;
    } catch (error) {
      Logger.warning('[SSH] ${host.hostLabel} login failed', error);
      _set(
        id,
        HostState(
          HostStatus.offline,
          error: hostErrorText(error),
          checkedAt: DateTime.now(),
        ),
      );
      rethrow;
    }
  }

  void _dropped(String id, SSHClient client, [Object? error]) {
    if (!identical(_clients[id], client)) return;
    _clients.remove(id);
    Logger.info(
        '[SSH] Host $id disconnected${error == null ? '' : ': $error'}');
    _set(
      id,
      HostState(
        HostStatus.offline,
        error: error == null ? 'SSH 连接已断开' : hostErrorText(error),
        checkedAt: DateTime.now(),
      ),
    );
  }

  /// Logs in to [host] (or reuses the login) and reports whether it worked.
  Future<bool> check(GatewayInfo host) async {
    try {
      await client(host);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Drops the login for [host], e.g. after its credentials changed.
  void forget(GatewayInfo host) {
    final id = host.hostId;
    final client = _clients.remove(id);
    try {
      client?.close();
    } catch (_) {}
    _states.remove(id);
    _notify();
  }

  void _set(String id, HostState state) {
    _states[id] = state;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final client in _clients.values) {
      try {
        client.close();
      } catch (_) {}
    }
    _clients.clear();
    super.dispose();
  }
}
