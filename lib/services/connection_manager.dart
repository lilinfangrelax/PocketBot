import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocket_bot/config/gateway_config.dart';
import 'package:pocket_bot/config/mcp_config.dart';
import 'package:pocket_bot/config/session_storage.dart';
import 'package:pocket_bot/models/ai_contact_config.dart';
import 'package:pocket_bot/models/mcp_server_config.dart';
import 'package:pocket_bot/models/message.dart';
import 'package:pocket_bot/services/acp_registry.dart';
import 'package:pocket_bot/services/acp_transport.dart';
import 'package:pocket_bot/services/cursor_agent.dart';
import 'package:pocket_bot/services/remote_helper.dart';
import 'package:pocket_bot/services/ssh_host_pool.dart';
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

  /// SSH logins, one per host. A host is online when its login is up.
  final SshHostPool hosts;

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

  ConnectionManager({SshHostPool? hosts})
      : _wsService = ws.WebSocketService(),
        hosts = hosts ?? SshHostPool() {
    _wsService.transportOpener = _openTransport;
    this.hosts.addListener(notifyListeners);
    _loadPreferences();
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

  /// Identifies one running agent process. Tagged profiles (AI contacts) get
  /// one process per host, agent and contact whatever folder they work in;
  /// untagged ones are keyed by connection, folder and agent.
  static String profileKey(GatewayInfo gateway) => gateway.instanceTag.isEmpty
      ? '${gateway.connectionId}|${gateway.workingDirectory.trim()}|${gateway.agentId}'
      : '${gateway.hostId}|${gateway.agentId}|${gateway.instanceTag}';

  static String contactInstanceTag(String contactId) => 'contact-$contactId';

  /// The saved connection with [id], matched by [GatewayInfo.connectionId]
  /// first and then by [GatewayInfo.hostId].
  GatewayInfo? hostById(String id) {
    if (id.isEmpty) return null;
    for (final gateway in _savedGateways) {
      if (gateway.connectionId == id) return gateway;
    }
    for (final gateway in _savedGateways) {
      if (gateway.hostId == id) return gateway;
    }
    return null;
  }

  /// How [config]'s agent process is launched on [hostId] (the contact's own
  /// host by default). Sessions pick their folder separately, so the launch
  /// folder stays the same and the remote helper can resume the process.
  /// Null when there is no such saved host.
  GatewayInfo? profileForContact(AIContactConfig config, {String? hostId}) {
    final base = hostById(hostId ?? config.gatewayId);
    if (base == null) return null;
    final own = config.workingDirectory.trim();
    final launchDirectory = own.isNotEmpty
        ? own
        : (base.kind == AgentTransportKind.ssh ? '.' : base.workingDirectory);
    return base.copyWith(
      workingDirectory: launchDirectory,
      agentId: config.agentId.isEmpty ? base.agentId : config.agentId,
      agentLabel:
          config.agentLabel.isEmpty ? base.agentLabel : config.agentLabel,
      instanceTag: contactInstanceTag(config.contactId),
    );
  }

  /// A folder browser on [host] that shares its SSH login.
  Future<SshRemoteSession> browseHost(GatewayInfo host) async {
    final client = await hosts.client(host);
    return SshRemoteSession.shared(
      client,
      host,
      reopen: () => hosts.client(host),
    );
  }

  /// ACP wants an absolute `cwd`, so `.` becomes the remote home folder.
  Future<String> _absoluteRemoteDirectory(GatewayInfo host) async {
    final cwd = host.workingDirectory.trim();
    if (cwd.isNotEmpty && cwd != '.') return cwd;
    final session = await browseHost(host);
    try {
      return await session.resolveStartPath('');
    } finally {
      await session.close();
    }
  }

  Future<AcpTransport> _openTransport(GatewayInfo target) async {
    if (target.kind != AgentTransportKind.ssh) {
      return AcpTransportFactory.open(target);
    }
    final client = await hosts.client(target);
    return SshStdioTransport.attach(
      client: client,
      target: target,
      ownsClient: false,
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
    // The callback must not return the removed future: whenComplete would
    // then wait on itself.
    return _opening[key] ??=
        _openPooled(key, profile, existing).whenComplete(() {
      _opening.remove(key);
    });
  }

  Future<ws.WebSocketService> _openPooled(
    String key,
    GatewayInfo profile,
    ws.WebSocketService? existing,
  ) async {
    final service = existing ?? ws.WebSocketService();
    service
      ..transportOpener = _openTransport
      ..autoApprovePermissions = _wsService.autoApprovePermissions
      ..mcpServers = _wsService.mcpServers;
    _pool[key] = service;
    notifyListeners();
    Logger.info('[Pool] Starting ${profile.displayLabel} '
        'agent=${profile.agentId} cwd=${profile.workingDirectory} key=$key');
    try {
      var prepared = profile;
      if (profile.kind == AgentTransportKind.local &&
          profile.agentId.isNotEmpty) {
        prepared = await prepareGatewayLaunch(profile, localRemotePlatform());
      }
      if (profile.kind == AgentTransportKind.ssh) {
        prepared = prepared.copyWith(
          workingDirectory: await _absoluteRemoteDirectory(profile),
        );
      }
      Logger.debug('[Pool] Launch ${prepared.kind.name} '
          'command=${prepared.command} cwd=${prepared.workingDirectory}');
      await service.connectTarget(prepared);
      Logger.info('Pooled connection ready: ${profile.displayLabel}');
      return service;
    } catch (error, stack) {
      Logger.error('[Pool] ${profile.displayLabel} failed', error, stack);
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
  }

  Future<void> checkGatewaysStatus() async {
    if (_isCheckingStatus) return;
    if (_savedGateways.isEmpty) return;

    _isCheckingStatus = true;
    notifyListeners();

    Logger.info('Checking agent statuses...');

    try {
      final sshHosts = <String, GatewayInfo>{};
      for (final gw in _savedGateways) {
        if (gw.kind == AgentTransportKind.ssh) {
          if (!gw.requiresAuth) sshHosts.putIfAbsent(gw.hostId, () => gw);
          continue;
        }
        final online = await _isLocalAgentAvailable(gw);
        _gatewayStatuses[gw.connectionId] = GatewayStatus(
          gateway: gw,
          isOnline: online,
          version: online ? 'ready' : null,
          error: online ? null : '找不到本机 agent',
        );
      }
      await Future.wait(sshHosts.values.map(hosts.check));
    } finally {
      _isCheckingStatus = false;
      notifyListeners();
    }
  }

  Future<bool> _isLocalAgentAvailable(GatewayInfo gw) async {
    try {
      await CursorAgent.resolve(gw.command);
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
    if (gateway.kind == AgentTransportKind.ssh &&
        !_savedGateways.any((g) => g.hostId == gateway.hostId)) {
      hosts.forget(gateway);
    }
    notifyListeners();
  }

  GatewayStatus? getGatewayStatus(GatewayInfo gateway) {
    if (gateway.kind == AgentTransportKind.ssh) {
      final state = hosts.stateOf(gateway);
      if (state.status == HostStatus.unknown) return null;
      return GatewayStatus(
        gateway: gateway,
        isOnline: state.isOnline,
        version: state.isOnline ? 'ready' : null,
        error: state.error,
      );
    }
    return _gatewayStatuses[gateway.connectionId];
  }

  HostState hostState(GatewayInfo gateway) {
    if (gateway.kind == AgentTransportKind.ssh) return hosts.stateOf(gateway);
    final status = _gatewayStatuses[gateway.connectionId];
    if (status == null) return const HostState(HostStatus.unknown);
    return HostState(
      status.isOnline ? HostStatus.online : HostStatus.offline,
      error: status.error,
    );
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

  @override
  void dispose() {
    hosts.removeListener(notifyListeners);
    hosts.dispose();
    super.dispose();
  }
}
