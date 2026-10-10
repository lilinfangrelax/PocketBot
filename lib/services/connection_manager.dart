import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocket_bot/config/gateway_config.dart';
import 'package:pocket_bot/config/mcp_config.dart';
import 'package:pocket_bot/config/session_storage.dart';
import 'package:pocket_bot/models/ai_contact_config.dart';
import 'package:pocket_bot/models/mcp_server_config.dart';
import 'package:pocket_bot/models/message.dart';
import 'package:pocket_bot/services/acp_registry.dart';
import 'package:pocket_bot/services/cursor_agent.dart';
import 'package:pocket_bot/services/remote_helper.dart';
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

  /// Extra agent connections that stay open next to [wsService], keyed by
  /// [profileKey]. Contacts and group members talk to their agent here.
  final Map<String, ws.WebSocketService> _pool = {};
  final Map<String, Future<ws.WebSocketService>> _opening = {};
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

  static const _autoApproveKey = 'acp_auto_approve_permissions';

  ConnectionManager() : _wsService = ws.WebSocketService() {
    _wsService.addListener(_onPrimaryTransportChanged);
    _loadPreferences();
    _loadSavedGateways().then((_) {
      // Probe after the list exists. The discover page used to check on the
      // first frame, often before this load finished, and then never again.
      unawaited(checkGatewaysStatus());
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

  /// Keep the page state on the primary transport. Loading a saved target
  /// sets [_gateway] without opening a session; a later socket drop used to
  /// leave this object on [ws.ConnectionState.connected].
  void _onPrimaryTransportChanged() {
    final reported = _wsService.state;
    // connect() closes a previous transport while we are already connecting.
    if (_state == ws.ConnectionState.connecting &&
        reported == ws.ConnectionState.disconnected) {
      return;
    }
    if (reported == _state &&
        (reported != ws.ConnectionState.error ||
            _errorMessage == _wsService.errorMessage)) {
      return;
    }
    _state = reported;
    if (reported == ws.ConnectionState.error) {
      _errorMessage = _wsService.errorMessage ?? _errorMessage;
    } else {
      _errorMessage = null;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _wsService.removeListener(_onPrimaryTransportChanged);
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _wsService.autoApprovePermissions =
          prefs.getBool(_autoApproveKey) ?? false;
    } catch (error) {
      Logger.warning('Could not load ACP preferences: $error');
    }
    try {
      _wsService.mcpServers = await McpConfig.load();
    } catch (error) {
      Logger.warning('Could not load MCP servers: $error');
    }
  }

  List<McpServerConfig> get mcpServers => _wsService.mcpServers;

  Future<void> saveMcpServers(List<McpServerConfig> servers) async {
    _wsService.mcpServers = servers;
    for (final service in _pool.values) {
      service.mcpServers = servers;
    }
    notifyListeners();
    await McpConfig.save(servers);
  }

  Future<void> setAutoApprovePermissions(bool value) async {
    _wsService.autoApprovePermissions = value;
    for (final service in _pool.values) {
      service.autoApprovePermissions = value;
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoApproveKey, value);
  }

  /// Identifies one running agent: where it runs, in which folder, which agent.
  static String profileKey(GatewayInfo gateway) =>
      '${gateway.connectionId}|${gateway.workingDirectory.trim()}|${gateway.agentId}';

  /// The saved connection a contact is bound to, narrowed to its folder and
  /// agent. Null when the contact has no binding or the connection was deleted.
  GatewayInfo? profileForContact(AIContactConfig config) {
    if (!config.hasAgent) return null;
    GatewayInfo? base;
    for (final gateway in _savedGateways) {
      if (gateway.connectionId == config.gatewayId) base = gateway;
    }
    if (base == null) return null;
    return base.copyWith(
      workingDirectory: config.workingDirectory.trim().isEmpty
          ? base.workingDirectory
          : config.workingDirectory.trim(),
      agentId: config.agentId.isEmpty ? base.agentId : config.agentId,
      agentLabel:
          config.agentLabel.isEmpty ? base.agentLabel : config.agentLabel,
    );
  }

  bool _primaryServes(GatewayInfo profile) {
    final current = _gateway;
    return current != null &&
        _wsService.isConnected &&
        profileKey(current) == profileKey(profile);
  }

  /// The connection already serving [profile], if any.
  ws.WebSocketService? serviceFor(GatewayInfo profile) {
    if (_primaryServes(profile)) return _wsService;
    return _pool[profileKey(profile)];
  }

  List<ws.WebSocketService> get pooledServices => List.unmodifiable(_pool.values);

  /// Returns a connected service for [profile], reusing the primary
  /// connection or an open pooled one, and connecting otherwise.
  Future<ws.WebSocketService> connectProfile(GatewayInfo profile) {
    if (_primaryServes(profile)) return Future.value(_wsService);
    final key = profileKey(profile);
    final existing = _pool[key];
    if (existing != null && existing.isConnected) {
      return Future.value(existing);
    }
    return _opening[key] ??= _openPooled(key, profile, existing)
        .whenComplete(() => _opening.remove(key));
  }

  Future<ws.WebSocketService> _openPooled(
    String key,
    GatewayInfo profile,
    ws.WebSocketService? existing,
  ) async {
    final service = existing ?? ws.WebSocketService();
    service
      ..autoApprovePermissions = _wsService.autoApprovePermissions
      ..mcpServers = _wsService.mcpServers;
    _pool[key] = service;
    notifyListeners();
    try {
      var prepared = profile;
      if (profile.kind == AgentTransportKind.local &&
          profile.agentId.isNotEmpty) {
        prepared = await prepareGatewayLaunch(profile, localRemotePlatform());
      }
      await service.connectTarget(prepared);
      Logger.info('Pooled connection ready: ${profile.displayLabel}');
      return service;
    } catch (error) {
      final message = service.errorMessage ??
          error.toString().replaceFirst('Exception: ', '');
      throw Exception(message);
    } finally {
      notifyListeners();
    }
  }

  Future<void> disconnectProfile(GatewayInfo profile) async {
    final service = _pool.remove(profileKey(profile));
    if (service == null) return;
    service.cancelReconnect();
    await service.disconnect();
    notifyListeners();
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
    notifyListeners();
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
    var prepared = gateway;
    if (gateway.kind == AgentTransportKind.local && gateway.agentId.isNotEmpty) {
      try {
        prepared = await prepareGatewayLaunch(gateway, localRemotePlatform());
      } catch (error) {
        _state = ws.ConnectionState.error;
        _gateway = gateway;
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
        notifyListeners();
        return;
      }
    }
    await _completeConnect(
      prepared,
      () => _wsService.connectTarget(prepared),
      persist: gateway,
    );
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
    Future<void> Function() connect, {
    GatewayInfo? persist,
  }) async {
    _state = ws.ConnectionState.connecting;
    _gateway = gateway;
    _errorMessage = null;
    notifyListeners();

    try {
      await connect();
      _wsService.setPendingGateway(gateway);

      if (_wsService.state == ws.ConnectionState.connected) {
        _state = ws.ConnectionState.connected;
        _gateway = persist ?? gateway;
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
