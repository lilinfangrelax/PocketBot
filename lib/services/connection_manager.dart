import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pocket_bot/config/gateway_config.dart';
import 'package:pocket_bot/config/session_storage.dart';
import 'package:pocket_bot/models/message.dart';
import 'package:pocket_bot/services/cursor_agent.dart';
import 'package:pocket_bot/services/ssh_remote_session.dart';
import 'package:pocket_bot/services/websocket_service.dart' as ws;
import 'package:pocket_bot/utils/logger.dart';

/// Saved agent online status
class GatewayStatus {
  final GatewayInfo gateway;
  final bool isOnline;
  final String? version;
  final String? error;

  GatewayStatus({
    required this.gateway,
    required this.isOnline,
    this.version,
    this.error,
  });
}

class ConnectionManager extends ChangeNotifier {
  final ws.WebSocketService _wsService;

  ws.ConnectionState _state = ws.ConnectionState.disconnected;
  GatewayInfo? _gateway;
  String? _errorMessage;
  List<GatewayInfo> _savedGateways = [];
  final Map<String, GatewayStatus> _gatewayStatuses = {};
  bool _isCheckingStatus = false;

  ws.ConnectionState get state => _state;
  GatewayInfo? get gateway => _gateway;
  String? get errorMessage => _errorMessage;
  List<GatewayInfo> get discoveredGateways => const [];
  List<GatewayInfo> get savedGateways => _savedGateways;
  Map<String, GatewayStatus> get gatewayStatuses => _gatewayStatuses;
  bool get isScanning => false;
  bool get isCheckingStatus => _isCheckingStatus;
  ws.WebSocketService get wsService => _wsService;

  ConnectionManager() : _wsService = ws.WebSocketService() {
    _loadSavedGateways().then((_) {
      final last = _gateway;
      if (last == null) return;
      if (last.kind == AgentTransportKind.ssh) {
        final cwd = last.workingDirectory.trim();
        if (cwd.isEmpty || cwd == '.') return;
      }
      Logger.info('Auto-connecting to saved agent...');
      connectTo(last);
    });
  }

  Future<void> _loadSavedGateways() async {
    try {
      _savedGateways = await GatewayConfig.loadGateways();
      Logger.info('Loaded ${_savedGateways.length} saved agent(s)');

      final last = await GatewayConfig.load();
      if (last != null) {
        _gateway = last;
        Logger.info('Last connected: ${last.displayLabel}');
      }
    } catch (e) {
      Logger.warning('No saved agents found: $e');
    }
  }

  Future<void> checkGatewaysStatus() async {
    if (_isCheckingStatus) return;
    if (_savedGateways.isEmpty) return;

    _isCheckingStatus = true;
    notifyListeners();

    Logger.info('Checking agent statuses...');

    try {
      for (final gw in _savedGateways) {
        final key = gw.connectionId;
        try {
          final online = await _isReachable(gw);
          _gatewayStatuses[key] = GatewayStatus(
            gateway: gw,
            isOnline: online,
            version: online ? 'ready' : null,
            error: online ? null : 'unreachable',
          );
        } catch (e) {
          _gatewayStatuses[key] = GatewayStatus(
            gateway: gw,
            isOnline: false,
            error: e.toString(),
          );
        }
      }
    } finally {
      _isCheckingStatus = false;
      notifyListeners();
    }
  }

  Future<bool> _isReachable(GatewayInfo gw) async {
    if (gw.kind == AgentTransportKind.local) {
      try {
        await CursorAgent.resolve(gw.command);
        return true;
      } catch (_) {
        return false;
      }
    }
    try {
      final socket = await Socket.connect(
        gw.host,
        gw.port,
        timeout: const Duration(seconds: 3),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> addSavedGateway(GatewayInfo gateway) async {
    _savedGateways = await GatewayConfig.addGateway(gateway);
    notifyListeners();
    checkGatewaysStatus();
  }

  Future<void> removeSavedGateway(GatewayInfo gateway) async {
    _savedGateways = await GatewayConfig.removeGateway(gateway);
    _gatewayStatuses.remove(gateway.connectionId);
    notifyListeners();
  }

  GatewayStatus? getGatewayStatus(GatewayInfo gateway) {
    return _gatewayStatuses[gateway.connectionId];
  }

  Future<List<ChatSession>> getSavedSessions() async {
    return await SessionStorage.loadAllSessions();
  }

  Future<ChatSession?> loadSavedSession(String sessionKey) async {
    return await SessionStorage.loadSession(sessionKey);
  }

  Future<void> deleteSavedSession(String sessionKey) async {
    await SessionStorage.deleteSession(sessionKey);
  }

  Future<void> restoreSession(ChatSession session) async {
    _wsService.selectSession(session.key, agentId: session.agentId);
    Logger.info('Restored session: ${session.key}');
    notifyListeners();
  }

  Future<void> _saveGateway() async {
    if (_gateway != null) {
      await GatewayConfig.addGateway(_gateway!);
      _savedGateways = await GatewayConfig.loadGateways();
      await GatewayConfig.saveLastConnected(_gateway!.connectionId);
      Logger.info('Saved agent: ${_gateway!.displayLabel}');
    }
  }

  Future<void> scanNetwork() async {
    await checkGatewaysStatus();
  }

  Future<void> connectTo(GatewayInfo gateway) async {
    await _completeConnect(gateway, () => _wsService.connectTarget(gateway));
  }

  Future<void> connectWithSshSession(
    GatewayInfo gateway,
    SshRemoteSession session,
  ) async {
    await _completeConnect(gateway, () async {
      final transport = await session.startAgent(gateway);
      await _wsService.connectWithTransport(
        transport,
        workingDirectory: gateway.workingDirectory,
      );
    });
  }

  Future<void> _completeConnect(
    GatewayInfo gateway,
    Future<void> Function() connect,
  ) async {
    _state = ws.ConnectionState.connecting;
    _gateway = gateway;
    _errorMessage = null;
    notifyListeners();

    try {
      await connect();
      _wsService.setPendingGateway(gateway);

      if (_wsService.state == ws.ConnectionState.connected) {
        _state = ws.ConnectionState.connected;
        await _saveGateway();
        Logger.info('Connected to ${gateway.name}');
      } else {
        throw Exception('Connection failed - not in connected state');
      }
    } catch (e) {
      Logger.error('Connection failed: $e');
      _state = ws.ConnectionState.error;
      _errorMessage = _wsService.errorMessage ?? '连接失败: $e';
    }

    notifyListeners();
  }

  Future<void> connectLocal({String? workingDirectory}) {
    return connectTo(GatewayInfo.local(
      workingDirectory:
          workingDirectory ?? CursorAgent.defaultWorkingDirectory(),
    ));
  }

  Future<void> disconnect() async {
    _wsService.cancelReconnect();
    await _wsService.disconnect();
    _state = ws.ConnectionState.disconnected;
    notifyListeners();
  }

  Future<void> connectManual({
    required String host,
    required int port,
    required String token,
    String username = '',
  }) async {
    await connectTo(GatewayInfo.ssh(
      host: host,
      port: port,
      username: username,
      password: token,
    ));
  }

  Future<void> clearSavedGateway() async {
    await GatewayConfig.clear();
    _gateway = null;
    notifyListeners();
  }
}
