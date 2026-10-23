import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:pocket_bot/config/session_storage.dart';
import 'package:pocket_bot/models/acp_tool_call.dart';
import 'package:pocket_bot/models/attachment.dart';
import 'package:pocket_bot/models/mcp_server_config.dart';
import 'package:pocket_bot/models/message.dart';
import 'package:pocket_bot/models/session_state.dart';
import 'package:pocket_bot/services/acp_file_system.dart';
import 'package:pocket_bot/services/acp_terminal.dart';
import 'package:pocket_bot/services/acp_transport.dart';
import 'package:pocket_bot/services/cursor_agent.dart';
import 'package:pocket_bot/services/notification_service.dart';
import 'package:pocket_bot/utils/acp_stream_text.dart';
import 'package:pocket_bot/utils/debug_log.dart';
import 'package:pocket_bot/utils/logger.dart';
import 'package:pocket_bot/utils/version_utils.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum ConnectionState { disconnected, connecting, connected, error }

/// Answers an agent request that arrived before a chat screen is listening.
/// Return null to keep the default cancel result.
typedef ClientRequestPresenter = Future<Map<String, dynamic>>? Function(
  Map<String, dynamic> request,
);

class AcpSessionMode {
  final String id;
  final String name;
  final String? description;

  const AcpSessionMode({
    required this.id,
    required this.name,
    this.description,
  });

  factory AcpSessionMode.fromJson(Map<String, dynamic> json) {
    return AcpSessionMode(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? json['id'] as String? ?? '',
      description: json['description'] as String?,
    );
  }
}

class AcpSlashCommand {
  final String name;
  final String? description;
  final String? hint;

  const AcpSlashCommand({
    required this.name,
    this.description,
    this.hint,
  });

  factory AcpSlashCommand.fromJson(Map<String, dynamic> json) {
    final input = json['input'] is Map
        ? Map<String, dynamic>.from(json['input'] as Map)
        : const <String, dynamic>{};
    return AcpSlashCommand(
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      hint: input['hint'] as String?,
    );
  }
}

class AcpTodoItem {
  final String id;
  final String content;
  final String status;

  const AcpTodoItem({
    required this.id,
    required this.content,
    required this.status,
  });

  factory AcpTodoItem.fromJson(Map<String, dynamic> json) {
    return AcpTodoItem(
      id: json['id'] as String? ?? '',
      content: json['content'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
    );
  }
}

class AcpPlanEntry {
  final String content;
  final String status;
  final String? priority;

  const AcpPlanEntry({
    required this.content,
    required this.status,
    this.priority,
  });

  bool get isDone => status == 'completed';
  bool get isActive => status == 'in_progress';

  factory AcpPlanEntry.fromJson(Map<String, dynamic> json) {
    return AcpPlanEntry(
      content: json['content'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      priority: json['priority'] as String?,
    );
  }
}

class AcpPermissionOption {
  final String optionId;
  final String name;

  /// `allow_once`, `allow_always`, `reject_once` or `reject_always`.
  final String kind;

  const AcpPermissionOption({
    required this.optionId,
    required this.name,
    required this.kind,
  });

  bool get allows => kind.startsWith('allow');
  bool get always => kind.endsWith('always');

  factory AcpPermissionOption.fromJson(Map<String, dynamic> json) {
    final optionId = json['optionId'] as String? ?? '';
    var kind = (json['kind'] as String? ?? '').replaceAll('-', '_');
    if (kind.isEmpty) kind = optionId.replaceAll('-', '_');
    return AcpPermissionOption(
      optionId: optionId,
      name: json['name'] as String? ?? optionId,
      kind: kind,
    );
  }
}

/// A `session/request_permission` call waiting for the user.
class AcpPermissionRequest {
  final dynamic requestId;
  final String sessionId;
  final String? toolCallId;
  final String title;
  final String? detail;
  final List<AcpPermissionOption> options;

  /// ACP tool kind (`execute`, `edit`, ...); the unit remembered by
  /// `allow_always`.
  final String? toolKind;

  const AcpPermissionRequest({
    required this.requestId,
    required this.sessionId,
    required this.title,
    required this.options,
    this.toolCallId,
    this.detail,
    this.toolKind,
  });

  String get key => requestId.toString();
}

class AcpConfigOptionValue {
  final String value;
  final String name;
  final String? description;

  /// Group header the agent put this value under, when options are grouped.
  final String? group;

  const AcpConfigOptionValue({
    required this.value,
    required this.name,
    this.description,
    this.group,
  });

  factory AcpConfigOptionValue.fromJson(Map<String, dynamic> json) {
    final value = json['value'] as String? ?? json['id'] as String? ?? '';
    return AcpConfigOptionValue(
      value: value,
      name: json['name'] as String? ?? value,
      description: json['description'] as String?,
      group: json['group'] as String?,
    );
  }
}

class AcpConfigOption {
  final String id;
  final String name;
  final String? description;
  final String? category;
  final String type;
  final Object? currentValue;
  final List<AcpConfigOptionValue> options;

  const AcpConfigOption({
    required this.id,
    required this.name,
    this.description,
    this.category,
    this.type = 'select',
    this.currentValue,
    this.options = const [],
  });

  bool get isBoolean => type == 'boolean';
  bool get isSelect => type == 'select' || type == 'id';

  String? get currentId {
    if (currentValue == null) return null;
    if (currentValue is bool) return currentValue == true ? 'true' : 'false';
    return currentValue.toString();
  }

  factory AcpConfigOption.fromJson(Map<String, dynamic> json) {
    return AcpConfigOption(
      id: json['configId'] as String? ?? json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      category: json['category'] as String?,
      type: json['type'] as String? ?? 'select',
      currentValue: json['currentValue'],
      options: [
        for (final entry in json['options'] as List? ?? const [])
          ..._valuesFromJson(entry),
      ],
    );
  }

  /// A select entry is either a value or a `{group, name, options: [...]}`
  /// header; groups are flattened so the menu can render both shapes.
  static List<AcpConfigOptionValue> _valuesFromJson(Object? entry) {
    if (entry is! Map) return const [];
    final json = Map<String, dynamic>.from(entry);
    final grouped = json['options'];
    if (grouped is List) {
      final header = (json['name'] as String?)?.trim();
      final label = header == null || header.isEmpty
          ? (json['group'] as String?)?.trim()
          : header;
      return [
        for (final item in grouped)
          if (item is Map)
            ..._valuesFromJson({
              ...Map<String, dynamic>.from(item),
              if (label != null && label.isNotEmpty) 'group': label,
            }),
      ];
    }
    final value = AcpConfigOptionValue.fromJson(json);
    return value.value.isEmpty ? const [] : [value];
  }
}

/// ACP v1 client. JSON-RPC 2.0 over a byte pipe: local stdio, SSH stdio, or
/// WebSocket (tests / legacy).
///
/// The first request is `initialize`; conversations are created with
/// `session/new`, prompted with `session/prompt`, and streamed via
/// `session/update` notifications.
class WebSocketService with ChangeNotifier {
  WebSocketService({WebSocketChannel Function(Uri)? connectionFactory})
      : _connectionFactory = connectionFactory;

  final WebSocketChannel Function(Uri)? _connectionFactory;

  /// Opens the pipe for [connectTarget] and reconnects. Defaults to
  /// [AcpTransportFactory.open], which logs in to SSH on its own.
  Future<AcpTransport> Function(GatewayInfo target)? transportOpener;
  AcpTransport? _transport;
  AcpTerminalHost? _terminalHost;
  final Map<String, _ActiveTerminal> _terminals = {};
  StreamSubscription? _channelSubscription;
  ConnectionState _state = ConnectionState.disconnected;
  String? _errorMessage;
  String? _currentAgentId;
  String? _activeSessionKey;
  String _workingDirectory = '/';

  /// Folder each ACP session was opened in. One agent process can serve
  /// several folders; sessions without an entry use [_workingDirectory].
  final Map<String, String> _sessionCwd = {};

  /// Extra workspace roots reported by the agent for each session.
  final Map<String, List<String>> _sessionAdditionalDirs = {};
  Map<String, dynamic> _agentCapabilities = const {};
  Map<String, dynamic>? _agentInfo;
  String? _currentModeId;
  List<AcpSessionMode> _availableModes = const [];
  List<AcpConfigOption> _configOptions = const [];
  List<AcpSlashCommand> _availableCommands = const [];
  List<AcpTodoItem> _todos = const [];
  Map<String, dynamic>? _pendingClientRequest;
  final Map<String, String> _urlElicitationSessions = {};
  final Map<String, AcpPermissionRequest> _pendingPermissions = {};

  /// Tool kinds the user allowed for the rest of a session, per session key.
  final Map<String, Set<String>> _alwaysAllowedToolKinds = {};
  final Map<String, List<AcpPlanEntry>> _plans = {};
  final Map<String, AcpToolCall> _toolCalls = {};
  List<McpServerConfig> _mcpServers = const [];
  bool _autoApprovePermissions = false;
  final _clientRequestController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Used when [clientRequests] has no listener, so login can finish before
  /// the chat screen exists.
  static ClientRequestPresenter? clientRequestPresenter;

  final Map<String, SessionState> _sessions = {};
  final Set<String> _attachedSessions = {};
  final Map<String, Completer<Map<String, dynamic>>> _pendingRpc = {};
  final Map<String, String> _pendingPromptSessions = {};
  final Map<String, String> _pendingUserMessages = {};
  final Map<String, Completer<void>> _promptWaiters = {};
  final Set<String> _quietSessions = {};

  /// session/update notifications received while session/load replays the
  /// conversation. They are applied only after the load response arrives so a
  /// failed load leaves the locally stored history untouched.
  final Map<String, List<Map<String, dynamic>>> _loadReplays = {};

  /// In-flight attach per session key, so concurrent prompts reuse one
  /// session/new|resume|load instead of racing and dropping history.
  final Map<String, Future<String>> _attachingSessions = {};
  final Map<String, String> _replayRoles = {};
  final Map<String, String> _replayUserMessages = {};

  final _messageController = StreamController<Message>.broadcast();
  final _messageUpdateController = StreamController<Message>.broadcast();
  final _eventController = StreamController<Map<String, dynamic>>.broadcast();
  final streamingTick = ValueNotifier<int>(0);
  final Map<String, String> _liveText = {};
  final Map<String, StringBuffer> _streamText = {};
  late final _frameCoalescer = AcpTextChunkCoalescer(emit: _dispatchMessage);

  Timer? _reconnectTimer;
  int _reconnectCountdown = 0;
  bool _isReconnecting = false;
  GatewayInfo? _pendingGateway;
  bool _isDisposed = false;

  ConnectionState get state => _state;
  String? get errorMessage => _errorMessage;
  String? get currentAgentId => _currentAgentId;
  String? get activeSessionKey => _activeSessionKey;
  String? get currentSessionKey => _activeSessionKey;
  Stream<Message> get messages => _messageController.stream;
  Stream<Message> get messageUpdates => _messageUpdateController.stream;
  Stream<Map<String, dynamic>> get events => _eventController.stream;
  Stream<Map<String, dynamic>> get clientRequests =>
      _clientRequestController.stream;
  String? streamingTextFor(String messageId) => _liveText[messageId];
  bool get isConnected => _state == ConnectionState.connected;
  bool get isReconnecting => _isReconnecting;
  int get reconnectCountdown => _reconnectCountdown;
  List<SessionState> get allSessions => _sessions.values.toList();
  SessionState? get activeSession =>
      _activeSessionKey == null ? null : _sessions[_activeSessionKey];
  SessionState? getSession(String sessionKey) => _sessions[sessionKey];
  Map<String, dynamic> get agentCapabilities =>
      Map.unmodifiable(_agentCapabilities);
  Map<String, dynamic>? get agentInfo =>
      _agentInfo == null ? null : Map.unmodifiable(_agentInfo!);
  String? get currentModeId => _currentModeId;
  List<AcpSessionMode> get availableModes => List.unmodifiable(_availableModes);
  List<AcpConfigOption> get configOptions => List.unmodifiable(_configOptions);
  bool get supportsImagePrompts =>
      _asMap(_agentCapabilities['promptCapabilities'])['image'] == true;
  List<AcpSlashCommand> get availableCommands =>
      List.unmodifiable(_availableCommands);
  List<AcpTodoItem> get todos => List.unmodifiable(_todos);
  Map<String, dynamic>? get pendingClientRequest => _pendingClientRequest;

  /// Skips permission prompts, like Zed's "always allow tool actions".
  bool get autoApprovePermissions => _autoApprovePermissions;

  set autoApprovePermissions(bool value) {
    if (_autoApprovePermissions == value) return;
    _autoApprovePermissions = value;
    if (value) {
      for (final request in _pendingPermissions.values.toList()) {
        final allow = _preferredAllowOption(request.options);
        respondToPermission(request, allow?.optionId);
      }
    }
    notifyListeners();
  }

  List<AcpPermissionRequest> get pendingPermissions =>
      List.unmodifiable(_pendingPermissions.values);

  List<AcpPermissionRequest> permissionsFor(String? sessionKey) =>
      _pendingPermissions.values
          .where((request) => request.sessionId == sessionKey)
          .toList();

  AcpToolCall? toolCallFor(String? sessionKey, String? toolCallId) =>
      toolCallId == null ? null : _toolCalls['$sessionKey/$toolCallId'];

  bool isAwaitingPermission(String? toolCallId) =>
      toolCallId != null &&
      _pendingPermissions.values
          .any((request) => request.toolCallId == toolCallId);

  List<McpServerConfig> get mcpServers => List.unmodifiable(_mcpServers);

  /// Applies to sessions created or loaded after the change.
  set mcpServers(List<McpServerConfig> servers) {
    _mcpServers = List.of(servers);
    notifyListeners();
  }

  List<Map<String, dynamic>> _mcpServersForAgent() {
    final caps = _asMap(_agentCapabilities['mcpCapabilities']);
    return _mcpServers
        .where((server) {
          if (!server.enabled || !server.isValid) return false;
          switch (server.transport) {
            case McpTransport.stdio:
              return true;
            case McpTransport.http:
              return caps['http'] == true;
            case McpTransport.sse:
              return caps['sse'] == true;
          }
        })
        .map((server) => server.toAcp())
        .toList();
  }

  List<AcpPlanEntry> planFor(String? sessionKey) =>
      List.unmodifiable(_plans[sessionKey] ?? const <AcpPlanEntry>[]);

  Future<void> connect({
    required String host,
    required int port,
    required String token,
    String endpointPath = '/acp',
    String workingDirectory = '/',
    bool secure = false,
  }) async {
    await _attachTransport(
      await WebSocketAcpTransport.connect(
        host: host,
        port: port,
        token: token,
        endpointPath: endpointPath,
        secure: secure,
        connectionFactory: _connectionFactory,
      ),
      workingDirectory: workingDirectory,
    );
  }

  Future<void> connectTarget(GatewayInfo target, {bool resume = false}) async {
    _pendingGateway = target.copyWith(resumeAgent: false);
    final cwd = target.kind == AgentTransportKind.local
        ? CursorAgent.resolveWorkingDirectory(target.workingDirectory)
        : (target.workingDirectory.trim().isEmpty
            ? '.'
            : opensshPathToWindows(target.workingDirectory.trim()));
    final open = transportOpener ?? AcpTransportFactory.open;
    await _attachTransport(
      await open(target),
      workingDirectory: cwd,
      resume: resume,
    );
  }

  Future<void> connectWithTransport(
    AcpTransport transport, {
    String workingDirectory = '/',
  }) {
    return _attachTransport(transport, workingDirectory: workingDirectory);
  }

  Future<void> _attachTransport(
    AcpTransport transport, {
    required String workingDirectory,
    bool resume = false,
  }) async {
    if (isConnected || _state == ConnectionState.connecting) {
      await disconnect();
    } else {
      await _closeTransport();
    }

    _state = ConnectionState.connecting;
    _errorMessage = null;
    _workingDirectory =
        workingDirectory.trim().isEmpty ? '/' : workingDirectory;
    notifyListeners();

    try {
      _transport = transport;
      _terminalHost = transport.terminalHost;
      _channelSubscription = transport.incoming.listen(
        _handleFrame,
        onError: _handleSocketError,
        onDone: _handleSocketDone,
      );

      final didResume = await transport.resumed;
      transport.release();
      final startupError = transport.startupError;
      if (startupError != null && startupError.isNotEmpty) {
        throw Exception(startupError);
      }
      if (resume && didResume) {
        _state = ConnectionState.connected;
        _errorMessage = null;
        notifyListeners();
        return;
      }
      if (resume) clearAllSessions();

      final response = await _request(
        'initialize',
        {
          'protocolVersion': 1,
          'clientCapabilities': {
            'fs': {
              'readTextFile': transport.fileSystem != null,
              'writeTextFile': transport.fileSystem != null,
            },
            'terminal': transport.terminalHost != null,
            'elicitation': {
              'form': <String, dynamic>{},
              'url': <String, dynamic>{},
            },
            'session': {
              'configOptions': {
                'boolean': <String, dynamic>{},
              },
              'notices': <String, dynamic>{},
              'compaction': <String, dynamic>{},
            },
            '_meta': {
              'parameterizedModelPicker': true,
            },
          },
          'clientInfo': {
            'name': 'pocketbot',
            'title': 'PocketBot',
            'version': AppVersion.baseVersion,
          },
        },
        timeout: const Duration(minutes: 3),
      );
      final version = response['protocolVersion'];
      if (version != 1) {
        throw Exception('Unsupported ACP protocol version: $version');
      }

      _agentCapabilities = _asMap(response['agentCapabilities']);
      final info = _asMap(response['agentInfo']);
      _agentInfo = info.isEmpty ? null : info;
      _currentAgentId = info['name'] as String?;
      await _authenticateIfNeeded(response);
      _state = ConnectionState.connected;
      Logger.info(
          '[ACP] Initialized${_currentAgentId == null ? '' : ' with $_currentAgentId'}');
      notifyListeners();
    } catch (error) {
      Logger.error('[ACP] Connection failed: $error');
      await _closeTransport();
      final value = error.toString();
      final agentExit = value.indexOf('AGENT_EXIT:');
      if (agentExit >= 0) {
        _setError(value.substring(agentExit));
      } else if (value.startsWith('AUTH_FAILED:') ||
          value.startsWith('CONNECTION_') ||
          value.startsWith('CURSOR_AGENT_') ||
          value.startsWith('AGENT_SPAWN_')) {
        _setError(value);
      } else {
        final lower = value.toLowerCase();
        if (lower.contains('401') ||
            lower.contains('403') ||
            lower.contains('auth')) {
          _setError('AUTH_FAILED:认证失败，请先运行 agent login 或检查 SSH 凭据');
        } else if (lower.contains('timeout')) {
          _setError('CONNECTION_TIMEOUT:连接 ACP Agent 超时');
        } else if (lower.contains('refused')) {
          _setError('CONNECTION_REFUSED:ACP Agent 拒绝连接');
        } else {
          _setError('CONNECTION_FAILED:$error');
        }
      }
      rethrow;
    }
  }

  Future<void> disconnect() async {
    for (final session in _sessions.values) {
      session.deactivate();
    }
    _failPending(Exception('ACP connection closed'));
    _attachedSessions.clear();
    _availableModes = const [];
    _configOptions = const [];
    _availableCommands = const [];
    _todos = const [];
    _currentModeId = null;
    _pendingClientRequest = null;
    _urlElicitationSessions.clear();
    _pendingPermissions.clear();
    _alwaysAllowedToolKinds.clear();
    _frameCoalescer.flush();
    _clearLiveText();
    await _closeTransport();
    _state = ConnectionState.disconnected;
    _errorMessage = null;
    if (!_isDisposed) notifyListeners();
  }

  Future<void> _closeTransport() async {
    await _releaseAllTerminals();
    await _channelSubscription?.cancel();
    _channelSubscription = null;
    await _transport?.close();
    _transport = null;
  }

  Future<void> _releaseAllTerminals() async {
    final terminals = _terminals.values.toList();
    _terminals.clear();
    for (final active in terminals) {
      try {
        await active.terminal.release();
      } catch (_) {}
    }
    final host = _terminalHost;
    _terminalHost = null;
    try {
      await host?.dispose();
    } catch (_) {}
  }

  Future<void> _releaseTerminalsForSession(String sessionId) async {
    final ids = _terminals.entries
        .where((entry) => entry.value.sessionId == sessionId)
        .map((entry) => entry.key)
        .toList();
    for (final id in ids) {
      final active = _terminals.remove(id);
      try {
        await active?.terminal.release();
      } catch (_) {}
    }
  }

  void _handleFrame(dynamic data) {
    try {
      if (data is Map) {
        _dispatchMessage(Map<String, dynamic>.from(data));
        return;
      }
      if (data is! String) return;
      final decoded = jsonDecode(data);
      if (decoded is Map) {
        _frameCoalescer.add(decoded);
      }
    } catch (error) {
      Logger.error('[ACP] Invalid frame: $error');
    }
  }

  void _dispatchMessage(Map<String, dynamic> message) {
    final method = message['method'];
    final highFrequency = method == 'session/update' &&
        _isStreamingUpdate(_asMap(message['params']));
    if (!highFrequency) {
      if (Logger.isVerbose) {
        Logger.debug('[ACP] <<< ${_frameForLog(jsonEncode(message))}');
      }
      _eventController.add(message);
    }

    if (message.containsKey('id') &&
        (message.containsKey('result') || message.containsKey('error'))) {
      _frameCoalescer.flush();
      _handleResponse(message);
    } else if (method == 'session/update') {
      _handleSessionUpdate(_asMap(message['params']));
    } else if (method == 'elicitation/complete') {
      _handleElicitationComplete(_asMap(message['params']));
    } else if (message.containsKey('id') && message.containsKey('method')) {
      _handleAgentRequest(message);
    } else if (message.containsKey('method')) {
      _handleCursorExtension(_asMap(message), asNotification: true);
    }
  }

  bool _isStreamingUpdate(Map<String, dynamic> params) {
    final kind = _asMap(params['update'])['sessionUpdate'] as String?;
    return kind == 'user_message_chunk' ||
        kind == 'agent_message_chunk' ||
        kind == 'agent_thought_chunk' ||
        kind == 'tool_call' ||
        kind == 'tool_call_update' ||
        kind == 'usage_update';
  }

  void _handleResponse(Map<String, dynamic> message) {
    final id = message['id'].toString();
    final result = _asMap(message['result']);
    final completer = _pendingRpc.remove(id);
    if (completer != null && !completer.isCompleted) {
      if (message['error'] != null) {
        final error = _asMap(message['error']);
        completer.completeError(Exception(
          'ACP ${error['code'] ?? 'error'}: ${error['message'] ?? 'Request failed'}',
        ));
      } else {
        completer.complete(result);
      }
    }

    final waiter = _promptWaiters[id];
    if (waiter != null && !waiter.isCompleted) {
      if (message['error'] != null) {
        final error = _asMap(message['error']);
        waiter.completeError(
            Exception('ACP ${error['code']}: ${error['message']}'));
      } else {
        waiter.complete();
      }
    }
    final sessionKey = _pendingPromptSessions.remove(id);
    final userMessageId = _pendingUserMessages.remove(id);
    if (sessionKey != null) {
      final session = _sessions[sessionKey];
      if (session != null) {
        if (userMessageId != null) {
          final index =
              session.messages.indexWhere((m) => m.id == userMessageId);
          if (index >= 0 && message['error'] == null) {
            session.updateMessage(
                session.messages[index].copyWith(confirmed: true));
          }
        }
        _finishStreamingMessage(session);
        if (message['error'] == null) {
          _applyStopReason(session, result['stopReason']);
        }
      }
    }
  }

  void _applyStopReason(SessionState session, dynamic raw) {
    final reason = raw is String ? raw.trim() : '';
    final text = switch (reason) {
      'max_tokens' => '本次回复达到长度上限，内容可能不完整。',
      'max_turn_requests' => '本次任务达到 Agent 的最大请求轮数。',
      'refusal' => 'Agent 拒绝继续处理本次请求。',
      _ => null,
    };
    if (text == null) return;
    _upsertSpecialMessage(
      session,
      id: 'stop-${_generateId()}',
      kind: MessageKind.system,
      text: text,
    );
  }

  /// Asks the connected agent to discard its stored login credentials.
  Future<void> logoutAgent() async {
    _requireConnected();
    await _request(
      'logout',
      const <String, dynamic>{},
      timeout: const Duration(seconds: 30),
    );
  }

  Future<void> _authenticateIfNeeded(Map<String, dynamic> initialize) async {
    final rawMethods = initialize['authMethods'] as List? ?? const [];
    // Terminal auth requires relaunching the agent in an interactive TUI,
    // which PocketBot cannot do. Those methods must not be sent to
    // `authenticate` (ACP treats them as client-side flows).
    final methods = rawMethods
        .map(_asMap)
        .where((method) => method['type'] != 'terminal')
        .toList();
    if (methods.isEmpty) {
      if (rawMethods.isNotEmpty) {
        Logger.info(
            '[ACP] Agent only offers terminal auth; sign in outside PocketBot');
      }
      return;
    }

    if (methods.any((method) => method['id'] == 'cursor_login')) {
      await _authenticateWith('cursor_login');
      return;
    }
    // Codex lists API-key auth first. Calling it with no key fails the whole
    // connection even when the machine already has a ChatGPT login.
    if (methods.any(_isCodexApiKeyMethod) &&
        methods.any(_isCodexLoginMethod)) {
      await _authenticateCodex(methods);
      return;
    }

    String? methodId;
    for (final method in methods) {
      final id = method['id'] as String? ?? '';
      if (id.isEmpty) continue;
      methodId = id;
      break;
    }
    if (methodId == null) return;
    await _authenticateWith(methodId);
  }

  Future<void> _authenticateCodex(List<Map<String, dynamic>> methods) async {
    Object? missingKey;
    for (final method in methods.where(_isCodexApiKeyMethod)) {
      final id = method['id'] as String? ?? '';
      if (id.isEmpty) continue;
      try {
        await _authenticateWith(id);
        return;
      } catch (error) {
        if (!_isMissingCodexApiKey(error)) rethrow;
        missingKey = error;
        Logger.info(
          '[ACP] $id has no API key, trying ChatGPT login',
        );
      }
    }
    final loginId = _preferredCodexLoginId(methods);
    if (loginId == null) {
      if (missingKey != null) throw missingKey;
      return;
    }
    await _authenticateWith(loginId);
  }

  Future<void> _authenticateWith(String methodId) async {
    Logger.info('[ACP] Authenticating with $methodId');
    await _request(
      'authenticate',
      {'methodId': methodId},
      timeout: const Duration(seconds: 90),
    );
  }

  bool _isCodexApiKeyMethod(Map<String, dynamic> method) {
    final id = method['id'] as String? ?? '';
    return id == 'api-key' ||
        id == 'codex-api-key' ||
        id == 'openai-api-key';
  }

  bool _isCodexLoginMethod(Map<String, dynamic> method) {
    final id = method['id'] as String? ?? '';
    return id == 'chat-gpt' ||
        id == 'chat-gpt-device-code' ||
        id == 'chatgpt';
  }

  /// Device code opens on this phone. Browser login runs on the agent host
  /// and is only used when the agent did not offer device code.
  String? _preferredCodexLoginId(List<Map<String, dynamic>> methods) {
    const preferred = ['chat-gpt-device-code', 'chat-gpt', 'chatgpt'];
    for (final id in preferred) {
      if (methods.any((method) => method['id'] == id)) return id;
    }
    return null;
  }

  bool _isMissingCodexApiKey(Object error) {
    final text = error.toString();
    return text.contains('CODEX_API_KEY') && text.contains('OPENAI_API_KEY');
  }

  Future<void> _handleAgentRequest(Map<String, dynamic> request) async {
    final method = request['method'];
    final id = request['id'];
    if (method == 'session/request_permission') {
      _handlePermissionRequest(id, _asMap(request['params']));
      return;
    }
    if (method == 'fs/read_text_file') {
      await _handleReadTextFile(id, _asMap(request['params']));
      return;
    }
    if (method == 'fs/write_text_file') {
      await _handleWriteTextFile(id, _asMap(request['params']));
      return;
    }
    if (method is String && method.startsWith('terminal/')) {
      await _handleTerminalRequest(method, id, _asMap(request['params']));
      return;
    }
    if (method == 'elicitation/create') {
      _handleElicitationRequest(request, _asMap(request['params']));
      return;
    }
    if (method is String && method.startsWith('cursor/')) {
      _handleCursorExtension(request, asNotification: false);
      return;
    }

    _sendJson({
      'jsonrpc': '2.0',
      'id': id,
      'error': {'code': -32601, 'message': 'Method not supported by PocketBot'},
    });
  }

  Future<void> _handleTerminalRequest(
    String method,
    dynamic id,
    Map<String, dynamic> params,
  ) async {
    final host = _terminalHost;
    if (host == null) {
      _sendTerminalError(
        id,
        -32601,
        'Terminal capability is not available for this connection',
      );
      return;
    }
    final sessionId = (params['sessionId'] as String?)?.trim() ?? '';
    if (sessionId.isEmpty) {
      _sendTerminalError(id, -32602, '$method requires sessionId');
      return;
    }
    if (method == 'terminal/create') {
      await _createTerminal(host, id, sessionId, params);
      return;
    }

    final terminalId = (params['terminalId'] as String?)?.trim() ?? '';
    final active = terminalId.isEmpty ? null : _terminals[terminalId];
    if (active == null || active.sessionId != sessionId) {
      _sendTerminalError(id, -32602, 'Unknown terminal: $terminalId');
      return;
    }

    switch (method) {
      case 'terminal/output':
        final result = <String, dynamic>{
          'output': active.terminal.output,
          'truncated': active.terminal.truncated,
        };
        if (active.terminal.hasExited) {
          result['exitStatus'] = _terminalExitStatus(active.terminal);
        }
        _sendJson({'jsonrpc': '2.0', 'id': id, 'result': result});
        return;
      case 'terminal/wait_for_exit':
        await active.terminal.exited;
        _sendJson({
          'jsonrpc': '2.0',
          'id': id,
          'result': _terminalExitStatus(active.terminal),
        });
        return;
      case 'terminal/kill':
        await active.terminal.kill();
        _sendJson({
          'jsonrpc': '2.0',
          'id': id,
          'result': <String, dynamic>{},
        });
        return;
      case 'terminal/release':
        _terminals.remove(terminalId);
        await active.terminal.release();
        _sendJson({
          'jsonrpc': '2.0',
          'id': id,
          'result': <String, dynamic>{},
        });
        return;
      default:
        _sendTerminalError(id, -32601, 'Method not supported by PocketBot');
    }
  }

  Future<void> _createTerminal(
    AcpTerminalHost host,
    dynamic id,
    String sessionId,
    Map<String, dynamic> params,
  ) async {
    final command = (params['command'] as String?)?.trim() ?? '';
    if (command.isEmpty) {
      _sendTerminalError(id, -32602, 'terminal/create requires command');
      return;
    }
    final args = [
      for (final arg in params['args'] as List? ?? const [])
        if (arg != null) '$arg',
    ];
    final environment = <String, String>{};
    for (final entry in params['env'] as List? ?? const []) {
      final variable = _asMap(entry);
      final name = (variable['name'] as String?)?.trim() ?? '';
      if (name.isEmpty) continue;
      environment[name] = '${variable['value'] ?? ''}';
    }
    final rawCwd = params['cwd'];
    final cwd = rawCwd is String && rawCwd.trim().isNotEmpty
        ? rawCwd.trim()
        : workingDirectoryFor(sessionId);
    final rawLimit = params['outputByteLimit'];
    final outputByteLimit =
        rawLimit is int ? rawLimit : int.tryParse('${rawLimit ?? ''}');
    try {
      final terminal = await host.create(
        command: command,
        args: args,
        environment: environment,
        cwd: cwd,
        outputByteLimit: outputByteLimit,
      );
      final terminalId = 'term-${_generateId()}';
      _terminals[terminalId] = _ActiveTerminal(sessionId, terminal);
      _sendJson({
        'jsonrpc': '2.0',
        'id': id,
        'result': {'terminalId': terminalId},
      });
    } catch (error) {
      Logger.warning('[ACP] terminal/create failed: $error');
      _sendTerminalError(
        id,
        -32603,
        'Failed to start terminal: $error',
      );
    }
  }

  Map<String, dynamic> _terminalExitStatus(AcpTerminal terminal) => {
        'exitCode': terminal.exitCode,
        'signal': terminal.signal,
      };

  void _sendTerminalError(dynamic id, int code, String message) {
    _sendJson({
      'jsonrpc': '2.0',
      'id': id,
      'error': {'code': code, 'message': message},
    });
  }

  void _handleElicitationRequest(
    Map<String, dynamic> request,
    Map<String, dynamic> params,
  ) {
    final mode = params['mode'];
    if (mode != 'form' && mode != 'url') {
      _sendJson({
        'jsonrpc': '2.0',
        'id': request['id'],
        'error': {
          'code': -32602,
          'message': 'Unsupported elicitation mode: $mode',
        },
      });
      return;
    }
    if (mode == 'form' && params['requestedSchema'] is! Map) {
      _sendJson({
        'jsonrpc': '2.0',
        'id': request['id'],
        'error': {
          'code': -32602,
          'message': 'Form elicitation requires requestedSchema',
        },
      });
      return;
    }
    final elicitationId = params['elicitationId']?.toString();
    if (mode == 'url' && elicitationId != null && elicitationId.isNotEmpty) {
      final sessionKey = params['sessionId'] as String? ?? _activeSessionKey;
      if (sessionKey != null && sessionKey.isNotEmpty) {
        _urlElicitationSessions[elicitationId] = sessionKey;
      }
    }
    _presentClientRequest(request, autoResult: {'action': 'cancel'});
  }

  void _handleElicitationComplete(Map<String, dynamic> params) {
    final elicitationId = params['elicitationId']?.toString();
    Logger.info('[ACP] Elicitation complete: ${elicitationId ?? ''}');
    if (elicitationId == null || elicitationId.isEmpty) return;
    final sessionKey = _urlElicitationSessions.remove(elicitationId);
    final session = sessionKey == null ? null : _sessions[sessionKey];
    if (session == null) return;
    _upsertSpecialMessage(
      session,
      id: 'elicitation-${_generateId()}',
      kind: MessageKind.system,
      text: '外部授权流程已完成。',
    );
    notifyListeners();
  }

  void _handleCursorExtension(
    Map<String, dynamic> message, {
    required bool asNotification,
  }) {
    final method = message['method'] as String? ?? '';
    final id = message['id'];
    final params = _asMap(message['params']);
    final session = _sessionForParams(params);

    switch (method) {
      case 'cursor/ask_question':
        _presentClientRequest(message, autoResult: {
          'outcome': {'outcome': 'skipped', 'reason': 'No chat UI attached'},
        });
        return;
      case 'cursor/create_plan':
        if (session != null) {
          final plan =
              params['plan'] as String? ?? params['overview'] as String? ?? '';
          final name = params['name'] as String? ?? 'Plan';
          _upsertSpecialMessage(
            session,
            id: 'plan-${params['toolCallId'] ?? session.sessionKey}',
            kind: MessageKind.plan,
            text: plan.isEmpty ? name : '**$name**\n\n$plan',
          );
        }
        _presentClientRequest(message, autoResult: {
          'outcome': {'outcome': 'accepted'},
        });
        return;
      case 'cursor/update_todos':
        _applyTodos(params);
        if (session != null) {
          _plans[session.sessionKey] = _todos
              .map((item) => AcpPlanEntry(
                    content: item.content,
                    status: item.status,
                  ))
              .toList();
          notifyListeners();
        }
        if (!asNotification && id != null) {
          _sendJson({
            'jsonrpc': '2.0',
            'id': id,
            'result': {
              'outcome': {
                'outcome': 'accepted',
                'todos': _todos
                    .map((item) => {
                          'id': item.id,
                          'content': item.content,
                          'status': item.status,
                        })
                    .toList(),
              },
            },
          });
        }
        return;
      case 'cursor/task':
        final description = params['description'] as String? ?? '子任务';
        if (session != null) {
          _upsertSpecialMessage(
            session,
            id: 'task-${params['toolCallId'] ?? _generateId()}',
            kind: MessageKind.system,
            text: '子任务：$description',
          );
        }
        if (!asNotification && id != null) {
          _sendJson({
            'jsonrpc': '2.0',
            'id': id,
            'result': {
              'outcome': {'outcome': 'completed'}
            },
          });
        }
        return;
      case 'cursor/generate_image':
        if (session != null) {
          final path = params['filePath'] as String? ?? '';
          _upsertSpecialMessage(
            session,
            id: 'image-${params['toolCallId'] ?? _generateId()}',
            kind: MessageKind.system,
            text: path.isEmpty ? '已生成图片' : '已生成图片：$path',
          );
        }
        if (!asNotification && id != null) {
          _sendJson({
            'jsonrpc': '2.0',
            'id': id,
            'result': {
              'outcome': {
                'outcome': 'generated',
                'filePath': params['filePath'] ?? '',
              },
            },
          });
        }
        return;
      default:
        if (!asNotification && id != null) {
          _sendJson({
            'jsonrpc': '2.0',
            'id': id,
            'error': {
              'code': -32601,
              'message': 'Method not supported by PocketBot',
            },
          });
        }
    }
  }

  void _presentClientRequest(
    Map<String, dynamic> request, {
    required Map<String, dynamic> autoResult,
  }) {
    _pendingClientRequest = request;
    notifyListeners();
    if (_clientRequestController.hasListener) {
      _clientRequestController.add(request);
      return;
    }
    final id = request['id'];
    final presenter = clientRequestPresenter;
    if (presenter != null && id != null) {
      final pending = presenter(request);
      if (pending != null) {
        unawaited(() async {
          try {
            final result = await pending;
            if (_isDisposed) return;
            if (_pendingClientRequest?['id']?.toString() != id.toString()) {
              return;
            }
            respondToAgentRequest(id, result);
          } catch (error) {
            Logger.warning('[ACP] Client request presenter failed: $error');
            if (_isDisposed) return;
            if (_pendingClientRequest?['id']?.toString() != id.toString()) {
              return;
            }
            respondToAgentRequest(id, autoResult);
          }
        }());
        return;
      }
    }
    // No chat UI and no presenter means nobody can answer, so cancel.
    if (id != null) {
      respondToAgentRequest(id, autoResult);
    }
  }

  void respondToAgentRequest(dynamic id, Map<String, dynamic> result) {
    _sendJson({'jsonrpc': '2.0', 'id': id, 'result': result});
    if (_pendingClientRequest != null &&
        _pendingClientRequest!['id']?.toString() == id.toString()) {
      _pendingClientRequest = null;
      notifyListeners();
    }
  }

  SessionState? _sessionForParams(Map<String, dynamic> params) {
    final sessionId = params['sessionId'] as String? ?? _activeSessionKey;
    if (sessionId == null) return activeSession;
    return _sessions.putIfAbsent(sessionId, () => _newSessionState(sessionId));
  }

  void _applyTodos(Map<String, dynamic> params) {
    final incoming = (params['todos'] as List? ?? const [])
        .map((item) => AcpTodoItem.fromJson(_asMap(item)))
        .toList();
    if (params['merge'] == true) {
      final merged = <String, AcpTodoItem>{
        for (final item in _todos) item.id: item,
      };
      for (final item in incoming) {
        merged[item.id] = item;
      }
      _todos = merged.values.toList();
    } else {
      _todos = incoming;
    }
    notifyListeners();
  }

  void _handlePermissionRequest(dynamic id, Map<String, dynamic> params) {
    final options = (params['options'] as List? ?? const [])
        .map((item) => AcpPermissionOption.fromJson(_asMap(item)))
        .where((option) => option.optionId.isNotEmpty)
        .toList();
    final sessionId = params['sessionId'] as String? ?? _activeSessionKey ?? '';
    final toolCall = _asMap(params['toolCall']);
    final toolKind = _nonEmpty(toolCall['kind']);
    final remembered = toolKind != null &&
        (_alwaysAllowedToolKinds[sessionId]?.contains(toolKind) ?? false);

    if (_autoApprovePermissions || remembered || options.isEmpty) {
      final allowed = _preferredAllowOption(options, preferAlways: remembered);
      Logger.info(
        '[ACP] Auto-allowing permission ${allowed?.optionId ?? 'cancelled'}'
        '${remembered ? ' (remembered $toolKind)' : ''}',
      );
      _sendPermissionOutcome(id, allowed?.optionId);
      return;
    }

    final session = sessionId.isEmpty
        ? null
        : _sessions.putIfAbsent(sessionId, () => _newSessionState(sessionId));
    if (session != null && toolCall.isNotEmpty) {
      _upsertToolCall(session, {
        ...toolCall,
        'status': toolCall['status'] ?? 'pending',
      });
    }
    final request = AcpPermissionRequest(
      requestId: id,
      sessionId: sessionId,
      toolCallId: toolCall['toolCallId'] as String?,
      title: _nonEmpty(toolCall['title']) ??
          _toolTitleFromRawInput(toolCall['rawInput']) ??
          '代理请求执行操作',
      detail: _permissionDetail(toolCall),
      options: options,
      toolKind: toolKind,
    );
    _pendingPermissions[request.key] = request;
    notifyListeners();
    if (_activeSessionKey != sessionId ||
        !_clientRequestController.hasListener) {
      NotificationService().showMessageNotification(
        sessionKey: sessionId,
        sessionName: session?.displayTitle ?? 'PocketBot',
        message: '需要你的确认：${request.title}',
      );
    }
  }

  String? _permissionDetail(Map<String, dynamic> toolCall) {
    final raw = _asMap(toolCall['rawInput']);
    final command = _nonEmpty(raw['command']);
    if (command != null) return command;
    final content = toolCall['content'];
    final text = _contentToText(content);
    if (text.isNotEmpty) return text;
    final locations = (toolCall['locations'] as List? ?? const [])
        .map((item) => _asMap(item)['path'] as String? ?? '')
        .where((path) => path.isNotEmpty)
        .join('\n');
    return locations.isEmpty ? null : locations;
  }

  AcpPermissionOption? _preferredAllowOption(
    List<AcpPermissionOption> options, {
    bool preferAlways = false,
  }) {
    if (preferAlways) {
      for (final option in options) {
        if (option.kind == 'allow_always') return option;
      }
    }
    AcpPermissionOption? fallback;
    for (final option in options) {
      if (option.kind == 'allow_once') return option;
      if (option.allows) fallback ??= option;
    }
    return fallback;
  }

  /// Answers a pending permission request. A null [optionId] cancels it.
  void respondToPermission(AcpPermissionRequest request, String? optionId) {
    if (_pendingPermissions.remove(request.key) == null) return;
    _sendPermissionOutcome(request.requestId, optionId);
    if (optionId != null) {
      final option = request.options.where((item) => item.optionId == optionId);
      final selected = option.isEmpty ? null : option.first;
      if (selected != null && selected.allows && selected.always) {
        final kind = request.toolKind;
        if (kind != null) {
          _alwaysAllowedToolKinds
              .putIfAbsent(request.sessionId, () => <String>{})
              .add(kind);
        }
      }
      final rejected = selected != null && !selected.allows;
      final session = _sessions[request.sessionId];
      if (rejected && session != null && request.toolCallId != null) {
        _upsertToolCall(session, {
          'toolCallId': request.toolCallId,
          'status': 'failed',
        });
      }
    }
    notifyListeners();
  }

  void _sendPermissionOutcome(dynamic id, String? optionId) {
    _sendJson({
      'jsonrpc': '2.0',
      'id': id,
      'result': {
        'outcome': optionId == null
            ? {'outcome': 'cancelled'}
            : {'outcome': 'selected', 'optionId': optionId},
      },
    });
  }

  void _cancelPermissions({String? sessionKey}) {
    final matching = _pendingPermissions.values
        .where(
            (request) => sessionKey == null || request.sessionId == sessionKey)
        .toList();
    for (final request in matching) {
      respondToPermission(request, null);
    }
  }

  Future<void> _handleReadTextFile(
      dynamic id, Map<String, dynamic> params) async {
    final fs = _transport?.fileSystem;
    if (fs == null) {
      _sendRpcError(id, -32601, 'File access is not available');
      return;
    }
    try {
      final path = fs.resolve(
        params['path'] as String? ?? '',
        workingDirectoryFor(params['sessionId'] as String?),
      );
      var content = await fs.readText(path);
      final line = params['line'];
      final limit = params['limit'];
      if (line is int && line > 0) {
        final lines = const LineSplitter().convert(content);
        final start = (line - 1).clamp(0, lines.length);
        final end = limit is int
            ? (start + limit).clamp(0, lines.length)
            : lines.length;
        content = lines.sublist(start, end).join('\n');
      }
      _sendJson({
        'jsonrpc': '2.0',
        'id': id,
        'result': {'content': content},
      });
    } on AcpFileNotFound catch (error) {
      _sendRpcError(id, -32002, error.toString());
    } catch (error) {
      _sendRpcError(id, -32603, 'Failed to read file: $error');
    }
  }

  Future<void> _handleWriteTextFile(
      dynamic id, Map<String, dynamic> params) async {
    final fs = _transport?.fileSystem;
    if (fs == null) {
      _sendRpcError(id, -32601, 'File access is not available');
      return;
    }
    try {
      final path = fs.resolve(
        params['path'] as String? ?? '',
        workingDirectoryFor(params['sessionId'] as String?),
      );
      await fs.writeText(path, params['content'] as String? ?? '');
      _sendJson({
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{},
      });
    } on AcpFileNotFound catch (error) {
      _sendRpcError(id, -32002, error.toString());
    } catch (error) {
      _sendRpcError(id, -32603, 'Failed to write file: $error');
    }
  }

  void _sendRpcError(dynamic id, int code, String message) {
    _sendJson({
      'jsonrpc': '2.0',
      'id': id,
      'error': {'code': code, 'message': message},
    });
  }

  Future<Map<String, dynamic>> _request(
    String method,
    Map<String, dynamic> params, {
    Duration timeout = const Duration(seconds: 15),
  }) {
    if (_transport == null) throw Exception('Not connected to ACP Agent');
    final id = _generateId();
    final completer = Completer<Map<String, dynamic>>();
    _pendingRpc[id] = completer;
    _sendJson({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params});
    return completer.future.timeout(timeout, onTimeout: () {
      _pendingRpc.remove(id);
      throw TimeoutException('ACP request timed out: $method');
    });
  }

  void _sendJson(Map<String, dynamic> value) {
    final frame = jsonEncode(value);
    if (Logger.isVerbose) Logger.debug('[ACP] >>> ${_frameForLog(frame)}');
    _transport?.send(frame);
  }

  static String _frameForLog(String frame) => DebugLog.truncate(frame, 1500);

  void selectSession(String sessionKey, {String? agentId}) {
    activeSession?.deactivate();
    _sessions.putIfAbsent(
      sessionKey,
      () => _newSessionState(sessionKey, agentId: agentId),
    );
    _activeSessionKey = sessionKey;
    _currentAgentId = agentId ?? _currentAgentId;
    _sessions[sessionKey]!.activate();
    notifyListeners();
  }

  void deactivateCurrentSession() {
    activeSession?.deactivate();
    notifyListeners();
  }

  void createNewSession({String? agentId}) {
    final key = 'local-${DateTime.now().microsecondsSinceEpoch}';
    final session = _newSessionState(key, agentId: agentId);
    _sessions[key] = session;
    _activeSessionKey = key;
    session.activate();
    SessionStorage.saveSession(session.toChatSession());
    notifyListeners();
  }

  SessionState _newSessionState(String key, {String? agentId}) {
    final session = SessionState(sessionKey: key, agentId: agentId);
    session.messageUpdateStream.listen(_messageUpdateController.add);
    return session;
  }

  /// Folder [sessionKey] runs in: its own when it has one, otherwise the
  /// folder the agent was started in.
  String workingDirectoryFor(String? sessionKey) {
    final cwd = sessionKey == null ? null : _sessionCwd[sessionKey];
    return cwd == null || cwd.trim().isEmpty ? _workingDirectory : cwd;
  }

  List<String> _additionalDirectoriesFor(String sessionKey) {
    final dirs = _sessionAdditionalDirs[sessionKey];
    return dirs == null || dirs.isEmpty ? const [] : List.unmodifiable(dirs);
  }

  List<String> _parseAdditionalDirectories(dynamic raw) {
    return (raw as List? ?? const [])
        .whereType<String>()
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .map(opensshPathToWindows)
        .toList();
  }

  Future<String> _createRemoteSession({String? cwd}) async {
    final folder = cwd == null || cwd.trim().isEmpty
        ? _workingDirectory
        : opensshPathToWindows(cwd.trim());
    final result = await _request('session/new', {
      'cwd': folder,
      'mcpServers': _mcpServersForAgent(),
    });
    final id = result['sessionId'] as String?;
    if (id == null || id.isEmpty) {
      throw Exception('ACP Agent returned no sessionId');
    }
    _sessionCwd[id] = folder;
    _attachedSessions.add(id);
    _sessions[id]?.workingDirectory = folder;
    _applySessionMeta(result);
    return id;
  }

  void _applySessionMeta(Map<String, dynamic> result) {
    _applyConfigOptions(result['configOptions']);
    _applyModelsFallback(result['models']);

    final modes = _asMap(result['modes']);
    final available = (modes['availableModes'] as List? ?? const [])
        .map((item) => AcpSessionMode.fromJson(_asMap(item)))
        .where((mode) => mode.id.isNotEmpty)
        .toList();
    if (available.isNotEmpty && _modeOption == null) {
      _availableModes = available;
      _currentModeId = modes['currentModeId'] as String? ?? available.first.id;
    } else if (_isCursorAgent && _availableModes.isEmpty) {
      _availableModes = const [
        AcpSessionMode(id: 'agent', name: 'Agent', description: '完整工具权限'),
        AcpSessionMode(id: 'plan', name: 'Plan', description: '只规划，不改文件'),
        AcpSessionMode(id: 'ask', name: 'Ask', description: '只问答'),
      ];
      _currentModeId ??= 'agent';
    } else if (modes['currentModeId'] is String && _currentModeId == null) {
      _currentModeId = modes['currentModeId'] as String;
    }
    notifyListeners();
  }

  void _applyConfigOptions(dynamic raw) {
    final parsed = (raw as List? ?? const [])
        .map((item) => AcpConfigOption.fromJson(_asMap(item)))
        .where((option) => option.id.isNotEmpty)
        .toList();
    if (raw == null) return;
    _configOptions = parsed;
    _syncModesFromConfig();
  }

  void _applyModelsFallback(dynamic raw) {
    if (_configOptions
        .any((option) => option.category == 'model' || option.id == 'model')) {
      return;
    }
    final models = _asMap(raw);
    final available = (models['availableModels'] as List? ?? const [])
        .map((item) {
          final value = _asMap(item);
          final id =
              value['modelId'] as String? ?? value['id'] as String? ?? '';
          return AcpConfigOptionValue(
            value: id,
            name: value['name'] as String? ?? id,
          );
        })
        .where((item) => item.value.isNotEmpty)
        .toList();
    if (available.isEmpty) return;
    _configOptions = [
      ..._configOptions,
      AcpConfigOption(
        id: 'model',
        name: 'Model',
        category: 'model',
        type: 'select',
        currentValue: models['currentModelId'],
        options: available,
      ),
    ];
  }

  AcpConfigOption? get _modeOption {
    for (final option in _configOptions) {
      if (option.category == 'mode' || option.id == 'mode') return option;
    }
    return null;
  }

  void _syncModesFromConfig() {
    final mode = _modeOption;
    if (mode == null || mode.options.isEmpty) return;
    _availableModes = mode.options
        .map((item) => AcpSessionMode(
              id: item.value,
              name: item.name,
              description: item.description,
            ))
        .toList();
    _currentModeId = mode.currentId ?? _currentModeId;
  }

  bool get _isCursorAgent {
    final name = (_currentAgentId ?? _agentInfo?['name'] ?? '').toString();
    return name.toLowerCase().contains('cursor');
  }

  Future<void> setSessionMode(String modeId) async {
    final mode = _modeOption;
    if (mode != null) {
      await setConfigOption(mode.id, modeId);
      return;
    }
    _requireConnected();
    final sessionKey = _activeSessionKey;
    if (sessionKey == null) throw Exception('No session selected');
    final remoteKey = await _ensureRemoteSession(sessionKey);
    await _request('session/set_mode', {
      'sessionId': remoteKey,
      'modeId': modeId,
    });
    _currentModeId = modeId;
    notifyListeners();
  }

  Future<void> setConfigOption(String configId, Object value) async {
    _requireConnected();
    final sessionKey = _activeSessionKey;
    if (sessionKey == null) throw Exception('No session selected');
    final remoteKey = await _ensureRemoteSession(sessionKey);
    AcpConfigOption? option;
    for (final item in _configOptions) {
      if (item.id == configId) {
        option = item;
        break;
      }
    }
    final params = <String, dynamic>{
      'sessionId': remoteKey,
      'configId': configId,
      'value': value,
    };
    if (option?.isBoolean == true) params['type'] = 'boolean';
    final result = await _request('session/set_config_option', params);
    if (result.containsKey('configOptions')) {
      _applySessionMeta(result);
    } else {
      _setConfigOptionValueLocally(configId, value);
      _syncModesFromConfig();
      notifyListeners();
    }
  }

  void _setConfigOptionValueLocally(String configId, Object? value) {
    _configOptions = _configOptions
        .map((item) => item.id == configId
            ? AcpConfigOption(
                id: item.id,
                name: item.name,
                description: item.description,
                category: item.category,
                type: item.type,
                currentValue: value,
                options: item.options,
              )
            : item)
        .toList();
  }

  void cancelPrompt({String? sessionKey}) {
    final selected = sessionKey ?? _activeSessionKey;
    if (selected == null || _transport == null) return;
    _cancelPermissions(sessionKey: selected);
    _sendJson({
      'jsonrpc': '2.0',
      'method': 'session/cancel',
      'params': {'sessionId': selected},
    });
  }

  Future<void> ensureActiveRemoteSession() async {
    if (!isConnected) return;
    if (_activeSessionKey == null) createNewSession();
    final selected = _activeSessionKey;
    if (selected == null) return;
    await _ensureRemoteSession(selected);
  }

  /// Starts a background ACP session. [cwd] defaults to the agent's folder.
  Future<ChatSession> createGatewaySession(String title, {String? cwd}) async {
    _requireConnected();
    final id = await _createRemoteSession(cwd: cwd);
    final now = DateTime.now();
    final session = ChatSession(
      id: id,
      key: id,
      title: title,
      createdAt: now,
      lastUpdated: now,
      messages: [],
      isGatewaySession: true,
      customTitle: title,
    );
    _sessions[id] = SessionState.fromChatSession(session);
    _sessions[id]!.workingDirectory = _sessionCwd[id];
    _sessions[id]!.messageUpdateStream.listen(_messageUpdateController.add);
    return session;
  }

  Future<String> _ensureRemoteSession(String sessionKey, {String? cwd}) {
    final inFlight = _attachingSessions[sessionKey];
    if (inFlight != null) return inFlight;
    final future = _attachSession(sessionKey, cwd: cwd);
    _attachingSessions[sessionKey] = future;
    return future.whenComplete(() {
      if (identical(_attachingSessions[sessionKey], future)) {
        _attachingSessions.remove(sessionKey);
      }
    });
  }

  Future<String> _attachSession(String sessionKey, {String? cwd}) async {
    if (cwd != null && cwd.trim().isNotEmpty) {
      final folder = opensshPathToWindows(cwd.trim());
      _sessionCwd[sessionKey] = folder;
      _sessions[sessionKey]?.workingDirectory = folder;
    }
    if (_attachedSessions.contains(sessionKey)) return sessionKey;

    if (sessionKey.startsWith('local-') ||
        sessionKey.startsWith('pocketbot-')) {
      final remoteId =
          await _createRemoteSession(cwd: _sessionCwd.remove(sessionKey));
      final old = _sessions.remove(sessionKey);
      final replacement = SessionState(
        sessionKey: remoteId,
        agentId: old?.agentId,
        messages: old == null ? null : List.from(old.messages),
        lastUpdated: old?.lastUpdated,
        isActive: old?.isActive ?? false,
        unreadCount: old?.unreadCount ?? 0,
        isGatewaySession: true,
        workingDirectory: _sessionCwd[remoteId],
        additionalDirectories: old?.additionalDirectories ?? const [],
        customTitle: old?.customTitle,
      );
      replacement.messageUpdateStream.listen(_messageUpdateController.add);
      old?.disposeStreams();
      _sessions[remoteId] = replacement;
      if (_activeSessionKey == sessionKey) _activeSessionKey = remoteId;
      await SessionStorage.deleteSession(sessionKey);
      notifyListeners();
      return remoteId;
    }

    final sessionCaps = _asMap(_agentCapabilities['sessionCapabilities']);
    final additionalDirectories = _additionalDirectoriesFor(sessionKey);
    if (sessionCaps.containsKey('resume')) {
      final result = await _request('session/resume', {
        'sessionId': sessionKey,
        'cwd': workingDirectoryFor(sessionKey),
        if (additionalDirectories.isNotEmpty)
          'additionalDirectories': additionalDirectories,
        'mcpServers': _mcpServersForAgent(),
      });
      _applySessionMeta(result);
    } else if (_agentCapabilities['loadSession'] == true) {
      await _loadRemoteSession(sessionKey);
    } else {
      throw Exception('ACP Agent cannot resume session $sessionKey');
    }
    _attachedSessions.add(sessionKey);
    final attached = _sessions[sessionKey];
    if (attached != null) {
      attached.workingDirectory = workingDirectoryFor(sessionKey);
      attached.additionalDirectories = additionalDirectories;
    }
    return sessionKey;
  }

  Future<void> deleteSession(String sessionKey) async {
    final sessionCaps = _asMap(_agentCapabilities['sessionCapabilities']);
    if (isConnected && !sessionKey.startsWith('local-')) {
      if (sessionCaps.containsKey('delete')) {
        await _request('session/delete', {'sessionId': sessionKey});
      } else if (sessionCaps.containsKey('close')) {
        try {
          await _request('session/close', {'sessionId': sessionKey});
        } catch (error) {
          Logger.info('[ACP] Could not close $sessionKey: $error');
        }
      }
    }
    _sessions.remove(sessionKey)?.disposeStreams();
    _attachedSessions.remove(sessionKey);
    _sessionCwd.remove(sessionKey);
    _sessionAdditionalDirs.remove(sessionKey);
    _alwaysAllowedToolKinds.remove(sessionKey);
    if (_activeSessionKey == sessionKey) _activeSessionKey = null;
    await _releaseTerminalsForSession(sessionKey);
    await SessionStorage.deleteSession(sessionKey);
    notifyListeners();
  }

  Future<void> renameSessionByKey(String sessionKey, String newTitle,
          {bool isLocal = true}) =>
      renameSession(sessionKey, newTitle);

  Future<void> renameSession(String sessionKey, String newTitle) async {
    _sessions[sessionKey]?.setCustomTitle(newTitle);
    await SessionStorage.updateSessionTitle(sessionKey, newTitle);
    notifyListeners();
  }

  Future<void> saveCurrentSession() async {
    if (activeSession != null) {
      await SessionStorage.saveSession(activeSession!.toChatSession());
    }
  }

  Future<List<ChatSession>> getGatewaySessions() async {
    _requireConnected();
    final sessionCaps = _asMap(_agentCapabilities['sessionCapabilities']);
    if (!sessionCaps.containsKey('list')) return const [];

    final sessions = <ChatSession>[];
    final seenCursors = <String>{};
    String? cursor;
    for (var page = 0; page < 100; page++) {
      final result = await _request('session/list', {
        if (cursor != null) 'cursor': cursor,
      });
      final values = result['sessions'] as List? ?? const [];
      for (final value in values) {
        final item = _asMap(value);
        final id = item['sessionId'] as String? ?? '';
        if (id.isEmpty) continue;
        final updated = DateTime.tryParse(item['updatedAt'] as String? ?? '') ??
            DateTime.now();
        final cwd = item['cwd'] as String? ?? '';
        if (cwd.trim().isNotEmpty) {
          _sessionCwd[id] = opensshPathToWindows(cwd.trim());
        }
        final additionalDirectories =
            _parseAdditionalDirectories(item['additionalDirectories']);
        if (additionalDirectories.isEmpty) {
          _sessionAdditionalDirs.remove(id);
        } else {
          _sessionAdditionalDirs[id] = additionalDirectories;
        }
        final title = item['title'] as String? ?? '新对话';
        sessions.add(ChatSession(
          id: id,
          key: id,
          title: title,
          createdAt: updated,
          lastUpdated: updated,
          messages: const [],
          isGatewaySession: true,
          sourceGatewayHost: _pendingGateway?.host,
          workingDirectory:
              cwd.trim().isEmpty ? null : opensshPathToWindows(cwd.trim()),
          additionalDirectories: additionalDirectories,
          agentTitle: title,
        ));
      }
      final next = (result['nextCursor'] as String?)?.trim();
      if (next == null || next.isEmpty || !seenCursors.add(next)) break;
      cursor = next;
    }
    return sessions;
  }

  Future<void> sendMessage(String text, {String? sessionKey}) =>
      sendMessageWithAttachments(text, const [], sessionKey: sessionKey);

  Future<void> sendMessageWithAttachments(
    String text,
    List<Attachment> attachments, {
    String? sessionKey,
  }) async {
    await _sendPrompt(text, attachments, sessionKey: sessionKey);
  }

  /// Attaches [sessionKey] to the agent (creating, resuming or loading it)
  /// and returns the ACP session id it now lives under.
  /// [cwd] pins the folder used when the session has to be created, resumed
  /// or loaded.
  Future<String> ensureRemoteSession(String sessionKey, {String? cwd}) {
    _requireConnected();
    return _ensureRemoteSession(sessionKey, cwd: cwd);
  }

  /// Sends a prompt without touching the active session and resolves with
  /// the agent's reply text once the turn ends.
  Future<String> sendMessageAndWait(
    String text, {
    required String sessionKey,
    Duration timeout = const Duration(minutes: 10),
  }) async {
    final remoteKey = await ensureRemoteSession(sessionKey);
    _quietSessions.add(remoteKey);
    _sessions
        .putIfAbsent(remoteKey, () => _newSessionState(remoteKey))
        .persist = false;
    final done = Completer<void>();
    final sent = await _sendPrompt(
      text,
      const [],
      sessionKey: remoteKey,
      activate: false,
      waiter: done,
    );
    try {
      await done.future.timeout(timeout);
    } on TimeoutException {
      cancelPrompt(sessionKey: sent.sessionKey);
      rethrow;
    } finally {
      _promptWaiters.remove(sent.requestId);
    }
    final session = _sessions[sent.sessionKey];
    if (session == null) return '';
    final start = session.messages
        .indexWhere((message) => message.id == sent.userMessageId);
    return session.messages
        .skip(start + 1)
        .where((message) =>
            !message.isUser &&
            message.kind == MessageKind.chat &&
            message.text.trim().isNotEmpty)
        .map((message) => message.text.trim())
        .join('\n\n');
  }

  Future<_SentPrompt> _sendPrompt(
    String text,
    List<Attachment> attachments, {
    String? sessionKey,
    bool activate = true,
    Completer<void>? waiter,
  }) async {
    _requireConnected();
    var selected = sessionKey ?? _activeSessionKey;
    if (selected == null) {
      createNewSession();
      selected = _activeSessionKey;
    }
    if (selected == null) throw Exception('No session selected');
    final remoteKey = await _ensureRemoteSession(selected);
    final session =
        _sessions.putIfAbsent(remoteKey, () => _newSessionState(remoteKey));
    if (activate || _activeSessionKey == selected) {
      _activeSessionKey = remoteKey;
    }

    final userMessage = Message(
      id: _generateId(),
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
      attachments: attachments,
    );
    session.addMessage(userMessage);
    _messageController.add(userMessage);

    final prompt = <Map<String, dynamic>>[];
    final promptCapabilities = _asMap(_agentCapabilities['promptCapabilities']);
    if (text.isNotEmpty) prompt.add({'type': 'text', 'text': text});
    for (final attachment in attachments) {
      if (attachment.isImage && attachment.data != null) {
        if (promptCapabilities['image'] != true) {
          throw Exception('This ACP Agent does not accept image prompts');
        }
        prompt.add({
          'type': 'image',
          'mimeType': attachment.mimeType,
          'data': attachment.data,
        });
      } else if (attachment.data != null) {
        if (promptCapabilities['embeddedContext'] != true) {
          throw Exception(
              'This ACP Agent does not accept embedded attachments');
        }
        prompt.add({
          'type': 'resource',
          'resource': {
            'uri': 'attachment://${Uri.encodeComponent(attachment.filename)}',
            'mimeType': attachment.mimeType,
            'blob': attachment.data,
          },
        });
      } else {
        prompt.add({
          'type': 'resource_link',
          'uri': attachment.url ??
              'file://${attachment.filePath ?? attachment.filename}',
          'name': attachment.filename,
          'mimeType': attachment.mimeType,
          'size': attachment.size,
        });
      }
    }
    if (prompt.isEmpty) throw Exception('ACP prompt cannot be empty');

    final requestId = _generateId();
    _pendingPromptSessions[requestId] = remoteKey;
    _pendingUserMessages[requestId] = userMessage.id;
    if (waiter != null) _promptWaiters[requestId] = waiter;
    _sendJson({
      'jsonrpc': '2.0',
      'id': requestId,
      'method': 'session/prompt',
      'params': {'sessionId': remoteKey, 'prompt': prompt},
    });
    return _SentPrompt(requestId, remoteKey, userMessage.id);
  }

  void _handleSessionUpdate(Map<String, dynamic> params) {
    final sessionKey = params['sessionId'] as String?;
    if (sessionKey == null) return;
    final replay = _loadReplays[sessionKey];
    if (replay != null) {
      replay.add(params);
      return;
    }
    _applySessionUpdate(sessionKey, _asMap(params['update']));
  }

  void _applySessionUpdate(
    String sessionKey,
    Map<String, dynamic> update, {
    bool replay = false,
  }) {
    final kind = update['sessionUpdate'] as String?;
    final session =
        _sessions.putIfAbsent(sessionKey, () => _newSessionState(sessionKey));

    if (kind == 'user_message_chunk') {
      if (replay) _appendReplayUserChunk(session, update);
    } else if (kind == 'agent_message_chunk') {
      if (replay) {
        if (_replayRoles[sessionKey] == 'user') session.currentRunId = null;
        _replayRoles[sessionKey] = 'agent';
      }
      final content = _asMap(update['content']);
      final messageId = update['messageId'] as String? ??
          session.currentRunId ??
          _generateId();
      if (content['type'] == 'text') {
        _appendAgentChunk(session, messageId, content['text'] as String? ?? '',
            replay: replay);
      } else if (content['type'] == 'image') {
        final attachment = Attachment(
          id: messageId,
          filename: 'image',
          mimeType: content['mimeType'] as String? ?? 'image/png',
          size: 0,
          data: content['data'] as String?,
        );
        _appendAgentChunk(session, messageId, '',
            attachment: attachment, replay: replay);
      }
    } else if (kind == 'agent_thought_chunk') {
      if (replay) _replayRoles[sessionKey] = 'thought';
      final text = _contentToText(update['content']);
      if (text.isEmpty || isLeakedAgentErrorOnly(text)) return;
      _upsertSpecialMessage(
        session,
        id: 'thought-${session.currentRunId ?? session.sessionKey}',
        kind: MessageKind.thought,
        text: stripLeakedAgentError(text),
        append: true,
        streaming: _promptInFlight,
        replay: replay,
      );
    } else if (kind == 'tool_call' || kind == 'tool_call_update') {
      if (replay) {
        _replayRoles[sessionKey] = 'tool';
        session.currentRunId = null;
      }
      _upsertToolCall(session, update, replay: replay);
    } else if (kind == 'available_commands_update') {
      _availableCommands = (update['availableCommands'] as List? ?? const [])
          .map((item) => AcpSlashCommand.fromJson(_asMap(item)))
          .where((command) => command.name.isNotEmpty)
          .toList();
      notifyListeners();
    } else if (kind == 'config_option_update') {
      _applySessionMeta(update);
    } else if (kind == 'current_mode_update') {
      _currentModeId = update['currentModeId'] as String? ?? _currentModeId;
      final modeOption = _modeOption;
      if (modeOption != null && _currentModeId != null) {
        _setConfigOptionValueLocally(modeOption.id, _currentModeId);
      }
      notifyListeners();
    } else if (kind == 'plan') {
      if (replay) {
        _replayRoles[sessionKey] = 'plan';
        session.currentRunId = null;
      }
      _plans[sessionKey] = (update['entries'] as List? ?? const [])
          .map((item) => AcpPlanEntry.fromJson(_asMap(item)))
          .where((entry) => entry.content.isNotEmpty)
          .toList();
      notifyListeners();
    } else if (kind == 'usage_update') {
      _applyUsageUpdate(session, update);
    } else if (kind == 'notice') {
      _applyNotice(session, update);
    } else if (kind == 'compaction_update') {
      _applyCompactionUpdate(session, update);
    } else if (kind == 'compaction_summary_chunk') {
      _applyCompactionChunk(session, update);
    } else if (kind == 'session_info_update') {
      if (update.containsKey('title')) {
        final title = update['title'];
        session.agentTitle =
            title is String && title.trim().isNotEmpty ? title.trim() : null;
        notifyListeners();
        if (session.persist) {
          unawaited(SessionStorage.saveSession(session.toChatSession()));
        }
      }
    }
  }

  void _applyUsageUpdate(
    SessionState session,
    Map<String, dynamic> update,
  ) {
    final used = update['used'];
    final size = update['size'];
    if (used is num && used >= 0) session.totalTokens = used.toInt();
    if (size is num && size >= 0) session.contextTokens = size.toInt();
    if (update.containsKey('cost')) {
      final cost = _asMap(update['cost']);
      final amount = cost['amount'];
      final currency = _nonEmpty(cost['currency']);
      if (amount is num && currency != null) {
        session.costAmount = amount.toDouble();
        session.costCurrency = currency;
      } else {
        session.costAmount = null;
        session.costCurrency = null;
      }
    }
    notifyListeners();
    if (session.persist) {
      unawaited(SessionStorage.saveSession(session.toChatSession()));
    }
  }

  void _applyNotice(SessionState session, Map<String, dynamic> update) {
    final title = _nonEmpty(update['title']);
    final description = _nonEmpty(update['description']);
    if (title == null && description == null) return;
    final severity = _nonEmpty(update['severity']) ?? 'info';
    final prefix = switch (severity) {
      'warning' => '注意：',
      'error' => '错误：',
      _ => '',
    };
    final body = description == null
        ? '$prefix${title ?? ''}'
        : '$prefix${title ?? ''}\n$description';
    _upsertSpecialMessage(
      session,
      id: 'notice-${_generateId()}',
      kind: MessageKind.system,
      text: body.trim(),
    );
  }

  void _applyCompactionChunk(
    SessionState session,
    Map<String, dynamic> update,
  ) {
    final compactionId = _nonEmpty(update['compactionId']);
    if (compactionId == null) return;
    final text = _contentToText(update['content']).trim();
    if (text.isEmpty) return;
    _upsertSpecialMessage(
      session,
      id: 'compaction-$compactionId',
      kind: MessageKind.system,
      text: text,
      append: true,
    );
  }

  void _applyCompactionUpdate(
    SessionState session,
    Map<String, dynamic> update,
  ) {
    final compactionId = _nonEmpty(update['compactionId']);
    if (compactionId == null) return;
    final id = 'compaction-$compactionId';
    final status = _nonEmpty(update['status']) ?? 'in_progress';
    final error = _nonEmpty(update['error']);
    final index = session.messages.indexWhere((message) => message.id == id);
    String? text;
    if (update.containsKey('summary')) {
      text = _contentToText(update['summary']).trim();
    } else if (index >= 0) {
      text = session.messages[index].text;
    }
    if (error != null) {
      text = error;
    } else if (text == null || text.isEmpty) {
      text = switch (status) {
        'in_progress' => '正在压缩上下文…',
        'cancelled' => '上下文压缩已取消',
        'failed' => '上下文压缩失败',
        _ => null,
      };
    }
    if (text == null || text.isEmpty) return;
    _upsertSpecialMessage(session,
        id: id, kind: MessageKind.system, text: text);
  }

  void _appendReplayUserChunk(
    SessionState session,
    Map<String, dynamic> update,
  ) {
    final content = _asMap(update['content']);
    final explicitId = update['messageId'] as String?;
    final roleChanged = _replayRoles[session.sessionKey] != 'user';
    _replayRoles[session.sessionKey] = 'user';
    if (roleChanged) {
      _replayUserMessages.remove(session.sessionKey);
      session.currentRunId = null;
    }
    if (explicitId != null) {
      _replayUserMessages[session.sessionKey] = explicitId;
    }
    final messageId = explicitId ??
        _replayUserMessages.putIfAbsent(session.sessionKey, _generateId);

    var text = '';
    Attachment? attachment;
    final type = content['type'];
    if (type == 'text') {
      text = content['text'] as String? ?? '';
    } else if (type == 'image') {
      attachment = Attachment(
        id: messageId,
        filename: 'image',
        mimeType: content['mimeType'] as String? ?? 'image/png',
        size: 0,
        data: content['data'] as String?,
      );
    } else if (type == 'resource_link') {
      final size = content['size'];
      attachment = Attachment(
        id: messageId,
        filename: content['name'] as String? ?? 'attachment',
        mimeType: content['mimeType'] as String? ?? 'application/octet-stream',
        size: size is int ? size : 0,
        url: content['uri'] as String?,
      );
    }
    if (text.isEmpty && attachment == null) return;

    final index = session.messages.indexWhere(
      (message) => message.isUser && message.id == messageId,
    );
    if (index < 0) {
      session.addMessage(Message(
        id: messageId,
        text: text,
        isUser: true,
        timestamp: DateTime.now(),
        attachments: attachment == null ? const [] : [attachment],
      ));
      return;
    }
    final old = session.messages[index];
    session.updateMessage(old.copyWith(
      text: old.text + text,
      attachments: attachment == null
          ? old.attachments
          : [...old.attachments, attachment],
    ));
  }

  void _prepareSessionForReplay(SessionState session) {
    final oldIds = session.messages.map((message) => message.id).toList();
    session.messages.clear();
    session.currentRunId = null;
    for (final id in oldIds) {
      _streamText.remove(id);
      _liveText.remove(id);
    }
    _toolCalls.removeWhere(
      (key, _) => key.startsWith('${session.sessionKey}/'),
    );
    _plans.remove(session.sessionKey);
  }

  Future<void> _loadRemoteSession(String sessionKey) async {
    final replay = <Map<String, dynamic>>[];
    _loadReplays[sessionKey] = replay;
    final additionalDirectories = _additionalDirectoriesFor(sessionKey);
    Map<String, dynamic> result;
    try {
      result = await _request('session/load', {
        'sessionId': sessionKey,
        'cwd': workingDirectoryFor(sessionKey),
        if (additionalDirectories.isNotEmpty)
          'additionalDirectories': additionalDirectories,
        'mcpServers': _mcpServersForAgent(),
      });
    } finally {
      _loadReplays.remove(sessionKey);
    }

    final session =
        _sessions.putIfAbsent(sessionKey, () => _newSessionState(sessionKey));
    session.workingDirectory = workingDirectoryFor(sessionKey);
    session.additionalDirectories = additionalDirectories;
    final hasHistory = replay.any((params) {
      final kind = _asMap(params['update'])['sessionUpdate'];
      return kind == 'user_message_chunk' ||
          kind == 'agent_message_chunk' ||
          kind == 'agent_thought_chunk' ||
          kind == 'tool_call' ||
          kind == 'tool_call_update' ||
          kind == 'plan';
    });
    if (hasHistory) {
      final persist = session.persist;
      final unread = session.unreadCount;
      final updated = session.lastUpdated;
      session.persist = false;
      _prepareSessionForReplay(session);
      _replayRoles.remove(sessionKey);
      _replayUserMessages.remove(sessionKey);
      try {
        for (final params in replay) {
          _applySessionUpdate(
            sessionKey,
            _asMap(params['update']),
            replay: true,
          );
        }
      } finally {
        _replayRoles.remove(sessionKey);
        _replayUserMessages.remove(sessionKey);
        session.persist = persist;
        session.unreadCount = unread;
        session.lastUpdated = updated;
        for (final message in session.messages) {
          _streamText.remove(message.id);
          _liveText.remove(message.id);
        }
        session.currentRunId = null;
      }
      if (persist) await SessionStorage.saveSession(session.toChatSession());
      notifyListeners();
    }
    _applySessionMeta(result);
  }

  void _upsertToolCall(
    SessionState session,
    Map<String, dynamic> update, {
    bool replay = false,
  }) {
    final toolCallId = update['toolCallId'] as String? ?? _generateId();
    _toolCalls
        .putIfAbsent('${session.sessionKey}/$toolCallId',
            () => AcpToolCall(id: toolCallId))
        .merge(update);
    final id = 'tool-$toolCallId';
    final index = session.messages.indexWhere((message) => message.id == id);
    final previous = index >= 0 ? session.messages[index] : null;
    final previousLines = (previous?.text ?? '')
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
    final previousTitle =
        previousLines.isEmpty ? null : previousLines.first.trim();
    final previousDetail =
        previousLines.length > 1 ? previousLines.sublist(1).join('\n') : '';
    final status =
        _nonEmpty(update['status']) ?? previous?.toolStatus ?? 'in_progress';
    final title = _nonEmpty(update['title']) ??
        _nonEmpty(update['toolName']) ??
        _nonEmpty(update['name']) ??
        previousTitle ??
        _nonEmpty(update['kind']) ??
        _toolTitleFromRawInput(update['rawInput']) ??
        '工具调用';
    final detail = _contentToText(update['content']);
    final locations = update['locations'] as List? ?? const [];
    final locationText = locations
        .map((item) {
          final loc = _asMap(item);
          return loc['path'] as String? ?? '';
        })
        .where((path) => path.isNotEmpty)
        .join(', ');
    final body = [
      if (locationText.isNotEmpty) locationText,
      if (detail.isNotEmpty)
        detail
      else if (previousDetail.isNotEmpty)
        previousDetail,
    ].join('\n');
    final text = body.isEmpty ? title : '$title\n$body';
    _upsertSpecialMessage(
      session,
      id: id,
      kind: MessageKind.tool,
      text: text,
      toolCallId: toolCallId,
      toolStatus: status,
      streaming:
          _promptInFlight && (status == 'pending' || status == 'in_progress'),
      replay: replay,
    );
  }

  String? _toolTitleFromRawInput(dynamic raw) {
    final map = _asMap(raw);
    return _nonEmpty(map['command']) ??
        _nonEmpty(map['path']) ??
        _nonEmpty(map['file_path']) ??
        _nonEmpty(map['query']);
  }

  String? _nonEmpty(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  void _upsertSpecialMessage(
    SessionState session, {
    required String id,
    required MessageKind kind,
    required String text,
    String? toolCallId,
    String? toolStatus,
    bool append = false,
    bool streaming = false,
    bool replay = false,
  }) {
    if (replay) streaming = false;
    final index = session.messages.indexWhere((m) => m.id == id);
    if (index >= 0) {
      final old = session.messages[index];
      final next = old.copyWith(
        text: append ? _appendStreamText(id, old.text, text) : text,
        kind: kind,
        toolCallId: toolCallId ?? old.toolCallId,
        toolStatus: toolStatus ?? old.toolStatus,
        isStreaming: streaming,
      );
      if (streaming) {
        session.patchStreamingMessage(next);
        _publishLiveText(id, next.text);
      } else {
        _liveText.remove(id);
        _streamText.remove(id);
        session.updateMessage(next);
      }
    } else {
      final initial = append ? _appendStreamText(id, '', text) : text;
      final message = Message(
        id: id,
        text: initial,
        isUser: false,
        timestamp: DateTime.now(),
        isStreaming: streaming,
        kind: kind,
        toolCallId: toolCallId,
        toolStatus: toolStatus,
      );
      session.addMessage(message);
      if (!replay) _messageController.add(message);
      if (streaming) _publishLiveText(id, initial);
    }
  }

  String _contentToText(dynamic content) {
    if (content is List) {
      return content
          .map(_contentToText)
          .where((value) => value.isNotEmpty)
          .join('\n');
    }
    final map = _asMap(content);
    switch (map['type']) {
      case 'text':
        return map['text'] as String? ?? '';
      case 'content':
        return _contentToText(map['content']);
      case 'diff':
        return map['path'] as String? ?? '';
      case 'resource_link':
        return map['uri'] as String? ?? map['name'] as String? ?? '';
      default:
        if (map['content'] != null) return _contentToText(map['content']);
        return map['text'] as String? ?? '';
    }
  }

  bool get _promptInFlight => _pendingPromptSessions.isNotEmpty;

  void _appendAgentChunk(
    SessionState session,
    String messageId,
    String text, {
    Attachment? attachment,
    bool replay = false,
  }) {
    if (attachment == null && isLeakedAgentErrorOnly(text)) {
      _sawLeakedStreamError = true;
      return;
    }
    final previousId = session.currentRunId;
    if (previousId != null && previousId != messageId) {
      final previousIndex =
          session.messages.indexWhere((m) => !m.isUser && m.id == previousId);
      if (previousIndex >= 0 && session.messages[previousIndex].isStreaming) {
        final settled =
            session.messages[previousIndex].copyWith(isStreaming: false);
        _liveText.remove(previousId);
        _streamText.remove(previousId);
        session.updateMessage(settled);
      }
    }
    session.currentRunId = messageId;
    final index =
        session.messages.indexWhere((m) => !m.isUser && m.id == messageId);
    // Keep streaming while chunks are still arriving. After the prompt has
    // settled, a late chunk must not turn the bubble back into "正在回复".
    // Replayed history is never live, otherwise it would persist as streaming.
    final streaming = !replay &&
        (_promptInFlight || index < 0 || session.messages[index].isStreaming);
    if (index >= 0) {
      final old = session.messages[index];
      final updated = old.copyWith(
        text: _appendStreamText(messageId, old.text, text),
        attachments: attachment == null
            ? old.attachments
            : [...old.attachments, attachment],
        isStreaming: streaming,
      );
      if (streaming) {
        session.patchStreamingMessage(updated);
        _publishLiveText(messageId, updated.text);
      } else {
        _liveText.remove(messageId);
        _streamText.remove(messageId);
        session.updateMessage(updated);
      }
    } else {
      final initial = _appendStreamText(messageId, '', text);
      final message = Message(
        id: messageId,
        text: initial,
        isUser: false,
        timestamp: DateTime.now(),
        isStreaming: streaming,
        attachments: attachment == null ? const [] : [attachment],
      );
      session.addMessage(message);
      if (!replay) _messageController.add(message);
      if (streaming) _publishLiveText(messageId, initial);
    }
  }

  String _appendStreamText(String messageId, String current, String chunk) {
    final buffer = _streamText.putIfAbsent(
      messageId,
      () => StringBuffer(current),
    );
    buffer.write(chunk);
    final cleaned = stripLeakedAgentError(buffer.toString());
    if (cleaned != buffer.toString()) {
      buffer
        ..clear()
        ..write(cleaned);
    }
    return buffer.toString();
  }

  void _publishLiveText(String messageId, String text) {
    if (_liveText[messageId] == text) return;
    _liveText[messageId] = text;
    streamingTick.value++;
  }

  void _clearLiveText() {
    if (_liveText.isEmpty && _streamText.isEmpty) return;
    _liveText.clear();
    _streamText.clear();
    streamingTick.value++;
  }

  bool _sawLeakedStreamError = false;
  static const _interruptedReplyText = '这次回复中断了，请再发送一次。';

  void _finishStreamingMessage(SessionState session) {
    final id = session.currentRunId;
    if (id != null) {
      final index = session.messages.indexWhere((m) => m.id == id && !m.isUser);
      if (index >= 0) {
        final live = stripLeakedAgentError(
          _liveText[id] ??
              _streamText[id]?.toString() ??
              session.messages[index].text,
        );
        final text = live.trim().isEmpty ? _interruptedReplyText : live;
        final message = session.messages[index].copyWith(
          text: text,
          isStreaming: false,
        );
        _liveText.remove(id);
        _streamText.remove(id);
        session.updateMessage(message);
        streamingTick.value++;
        if (_activeSessionKey != session.sessionKey &&
            !_quietSessions.contains(session.sessionKey) &&
            message.text.isNotEmpty) {
          NotificationService().showMessageNotification(
            sessionKey: session.sessionKey,
            sessionName: session.displayTitle,
            message: message.text,
          );
        }
      }
    } else if (_sawLeakedStreamError) {
      final notice = Message(
        id: _generateId(),
        text: _interruptedReplyText,
        isUser: false,
        timestamp: DateTime.now(),
      );
      session.addMessage(notice);
      _messageController.add(notice);
    }
    _sawLeakedStreamError = false;
    session.currentRunId = null;
    for (final message in List<Message>.of(session.messages)) {
      if (message.isUser || !message.isStreaming) continue;
      _liveText.remove(message.id);
      _streamText.remove(message.id);
      session.updateMessage(message.copyWith(isStreaming: false));
    }
    streamingTick.value++;
    SessionStorage.saveSession(session.toChatSession());
  }

  Future<void> loadSessionFromStorage(String sessionKey) async {
    final saved = await SessionStorage.loadSession(sessionKey);
    if (saved != null && !_sessions.containsKey(sessionKey)) {
      final state = SessionState.fromChatSession(saved);
      _restoreSessionFolder(state);
      state.messageUpdateStream.listen(_messageUpdateController.add);
      _sessions[sessionKey] = state;
    }
  }

  Future<void> loadAllSessionsFromStorage() async {
    for (final saved in await SessionStorage.loadAllSessions()) {
      if (!_sessions.containsKey(saved.key)) {
        final state = SessionState.fromChatSession(saved);
        _restoreSessionFolder(state);
        state.messageUpdateStream.listen(_messageUpdateController.add);
        _sessions[saved.key] = state;
      }
    }
  }

  void _restoreSessionFolder(SessionState session) {
    final cwd = session.workingDirectory?.trim() ?? '';
    if (cwd.isNotEmpty) _sessionCwd[session.sessionKey] = cwd;
    if (session.additionalDirectories.isNotEmpty) {
      _sessionAdditionalDirs[session.sessionKey] =
          List.of(session.additionalDirectories);
    }
  }

  void clearAllSessions() {
    for (final session in _sessions.values) {
      session.disposeStreams();
    }
    _sessions.clear();
    _attachedSessions.clear();
    _activeSessionKey = null;
    _availableModes = const [];
    _configOptions = const [];
    _availableCommands = const [];
    _todos = const [];
    _currentModeId = null;
    _pendingClientRequest = null;
    _urlElicitationSessions.clear();
    for (final active in _terminals.values) {
      unawaited(active.terminal.release());
    }
    _terminals.clear();
    _pendingPermissions.clear();
    _alwaysAllowedToolKinds.clear();
    _plans.clear();
    _toolCalls.clear();
    notifyListeners();
  }

  void _handleSocketError(Object error) {
    Logger.error('[ACP] Transport error: $error');
    _failPending(error);
    final value = error.toString();
    final agentExit = value.indexOf('AGENT_EXIT:');
    if (agentExit >= 0) {
      _setError(value.substring(agentExit));
      return;
    }
    _setError('CONNECTION_ERROR:ACP 连接失败');
  }

  void _handleSocketDone() {
    _failPending(Exception('ACP connection closed'));
    if (_state == ConnectionState.connected) {
      _setError('CONNECTION_CLOSED:ACP 连接意外断开');
      _startAutoReconnect();
    }
  }

  void _failPending(Object error) {
    final promptSessions = _pendingPromptSessions.values.toSet();
    for (final completer in _pendingRpc.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pendingRpc.clear();
    for (final waiter in _promptWaiters.values) {
      if (!waiter.isCompleted) waiter.completeError(error);
    }
    _pendingPermissions.clear();
    _pendingPromptSessions.clear();
    _pendingUserMessages.clear();
    for (final key in promptSessions) {
      final session = _sessions[key];
      if (session != null) _finishStreamingMessage(session);
    }
  }

  void _setError(String error) {
    _state = ConnectionState.error;
    _errorMessage = error;
    if (!_isDisposed) notifyListeners();
  }

  void _startAutoReconnect() {
    if (_isReconnecting || _pendingGateway == null) return;
    _isReconnecting = true;
    _reconnectCountdown = 3;
    notifyListeners();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _reconnectCountdown--;
      if (_reconnectCountdown <= 0) {
        timer.cancel();
        _isReconnecting = false;
        _performReconnect();
      } else {
        notifyListeners();
      }
    });
  }

  Future<void> _performReconnect() async {
    final gateway = _pendingGateway;
    if (gateway == null) return;
    try {
      final resume = gateway.kind == AgentTransportKind.ssh;
      await connectTarget(
        resume ? gateway.copyWith(resumeAgent: true) : gateway,
        resume: resume,
      );
    } catch (_) {
      _startAutoReconnect();
    }
  }

  void setPendingGateway(GatewayInfo gateway) => _pendingGateway = gateway;

  void cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _isReconnecting = false;
    _reconnectCountdown = 0;
    _pendingGateway = null;
    notifyListeners();
  }

  void _requireConnected() {
    if (!isConnected) throw Exception('Not connected to ACP Agent');
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  String _generateId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final random = Random().nextInt(100000).toString().padLeft(5, '0');
    return '$timestamp-$random';
  }

  @override
  void dispose() {
    _isDisposed = true;
    _reconnectTimer?.cancel();
    _failPending(Exception('ACP service disposed'));
    _channelSubscription?.cancel();
    _transport?.close();
    for (final session in _sessions.values) {
      session.disposeStreams();
    }
    _messageController.close();
    _messageUpdateController.close();
    _eventController.close();
    _clientRequestController.close();
    streamingTick.dispose();
    super.dispose();
  }
}

class _SentPrompt {
  final String requestId;
  final String sessionKey;
  final String userMessageId;

  const _SentPrompt(this.requestId, this.sessionKey, this.userMessageId);
}

class _ActiveTerminal {
  const _ActiveTerminal(this.sessionId, this.terminal);

  final String sessionId;
  final AcpTerminal terminal;
}
