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
import 'package:pocket_bot/services/acp_transport.dart';
import 'package:pocket_bot/services/cursor_agent.dart';
import 'package:pocket_bot/services/notification_service.dart';
import 'package:pocket_bot/utils/acp_stream_text.dart';
import 'package:pocket_bot/utils/logger.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum ConnectionState { disconnected, connecting, connected, error }

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

  const AcpPermissionRequest({
    required this.requestId,
    required this.sessionId,
    required this.title,
    required this.options,
    this.toolCallId,
    this.detail,
  });

  String get key => requestId.toString();
}

class AcpConfigOptionValue {
  final String value;
  final String name;
  final String? description;

  const AcpConfigOptionValue({
    required this.value,
    required this.name,
    this.description,
  });

  factory AcpConfigOptionValue.fromJson(Map<String, dynamic> json) {
    final value = json['value'] as String? ?? json['id'] as String? ?? '';
    return AcpConfigOptionValue(
      value: value,
      name: json['name'] as String? ?? value,
      description: json['description'] as String?,
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
      options: (json['options'] as List? ?? const [])
          .map((item) => AcpConfigOptionValue.fromJson(
                item is Map<String, dynamic>
                    ? item
                    : Map<String, dynamic>.from(item as Map),
              ))
          .where((item) => item.value.isNotEmpty)
          .toList(),
    );
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
  StreamSubscription? _channelSubscription;
  ConnectionState _state = ConnectionState.disconnected;
  String? _errorMessage;
  String? _currentAgentId;
  String? _activeSessionKey;
  String _workingDirectory = '/';

  /// Folder each ACP session was opened in. One agent process can serve
  /// several folders; sessions without an entry use [_workingDirectory].
  final Map<String, String> _sessionCwd = {};
  Map<String, dynamic> _agentCapabilities = const {};
  Map<String, dynamic>? _agentInfo;
  String? _currentModeId;
  List<AcpSessionMode> _availableModes = const [];
  List<AcpConfigOption> _configOptions = const [];
  List<AcpSlashCommand> _availableCommands = const [];
  List<AcpTodoItem> _todos = const [];
  Map<String, dynamic>? _pendingClientRequest;
  final Map<String, AcpPermissionRequest> _pendingPermissions = {};
  final Map<String, List<AcpPlanEntry>> _plans = {};
  final Map<String, AcpToolCall> _toolCalls = {};
  List<McpServerConfig> _mcpServers = const [];
  bool _autoApprovePermissions = false;
  final _clientRequestController =
      StreamController<Map<String, dynamic>>.broadcast();

  final Map<String, SessionState> _sessions = {};
  final Set<String> _attachedSessions = {};
  final Map<String, Completer<Map<String, dynamic>>> _pendingRpc = {};
  final Map<String, String> _pendingPromptSessions = {};
  final Map<String, String> _pendingUserMessages = {};
  final Map<String, Completer<void>> _promptWaiters = {};
  final Set<String> _quietSessions = {};

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
  List<AcpSessionMode> get availableModes =>
      List.unmodifiable(_availableModes);
  List<AcpConfigOption> get configOptions =>
      List.unmodifiable(_configOptions);
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
    return _mcpServers.where((server) {
      if (!server.enabled || !server.isValid) return false;
      switch (server.transport) {
        case McpTransport.stdio:
          return true;
        case McpTransport.http:
          return caps['http'] == true;
        case McpTransport.sse:
          return caps['sse'] == true;
      }
    }).map((server) => server.toAcp()).toList();
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
            : target.workingDirectory);
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
            'terminal': false,
            '_meta': {
              'parameterizedModelPicker': true,
            },
          },
          'clientInfo': {
            'name': 'pocketbot',
            'title': 'PocketBot',
            'version': '1.1.0',
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
    _pendingPermissions.clear();
    _frameCoalescer.flush();
    _clearLiveText();
    await _closeTransport();
    _state = ConnectionState.disconnected;
    _errorMessage = null;
    if (!_isDisposed) notifyListeners();
  }

  Future<void> _closeTransport() async {
    await _channelSubscription?.cancel();
    _channelSubscription = null;
    await _transport?.close();
    _transport = null;
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
      Logger.debug(
          '[ACP] Received method=$method id=${message['id']}');
      _eventController.add(message);
    }

    if (message.containsKey('id') &&
        (message.containsKey('result') || message.containsKey('error'))) {
      _frameCoalescer.flush();
      _handleResponse(message);
    } else if (method == 'session/update') {
      _handleSessionUpdate(_asMap(message['params']));
    } else if (message.containsKey('id') && message.containsKey('method')) {
      _handleAgentRequest(message);
    } else if (message.containsKey('method')) {
      _handleCursorExtension(_asMap(message), asNotification: true);
    }
  }

  bool _isStreamingUpdate(Map<String, dynamic> params) {
    final kind = _asMap(params['update'])['sessionUpdate'] as String?;
    return kind == 'agent_message_chunk' ||
        kind == 'agent_thought_chunk' ||
        kind == 'tool_call' ||
        kind == 'tool_call_update' ||
        kind == 'usage_update';
  }

  void _handleResponse(Map<String, dynamic> message) {
    final id = message['id'].toString();
    final completer = _pendingRpc.remove(id);
    if (completer != null && !completer.isCompleted) {
      if (message['error'] != null) {
        final error = _asMap(message['error']);
        completer.completeError(Exception(
          'ACP ${error['code'] ?? 'error'}: ${error['message'] ?? 'Request failed'}',
        ));
      } else {
        completer.complete(_asMap(message['result']));
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
      }
    }
  }

  Future<void> _authenticateIfNeeded(Map<String, dynamic> initialize) async {
    final methods = initialize['authMethods'] as List? ?? const [];
    if (methods.isEmpty) return;

    String methodId = 'cursor_login';
    for (final method in methods) {
      final value = _asMap(method);
      final id = value['id'] as String? ?? '';
      if (id == 'cursor_login') {
        methodId = id;
        break;
      }
      if (id.isNotEmpty) methodId = id;
    }
    Logger.info('[ACP] Authenticating with $methodId');
    await _request(
      'authenticate',
      {'methodId': methodId},
      timeout: const Duration(seconds: 90),
    );
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
          final plan = params['plan'] as String? ?? params['overview'] as String? ?? '';
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
            'result': {'outcome': {'outcome': 'completed'}},
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
    if (request['id'] != null) {
      respondToAgentRequest(request['id'], autoResult);
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
    final sessionId =
        params['sessionId'] as String? ?? _activeSessionKey ?? '';
    final toolCall = _asMap(params['toolCall']);

    if (_autoApprovePermissions || options.isEmpty) {
      final allowed = _preferredAllowOption(options);
      Logger.info(
        '[ACP] Auto-allowing permission ${allowed?.optionId ?? 'cancelled'}',
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
    );
    _pendingPermissions[request.key] = request;
    notifyListeners();
    if (_activeSessionKey != sessionId || !_clientRequestController.hasListener) {
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
      List<AcpPermissionOption> options) {
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
      final option =
          request.options.where((item) => item.optionId == optionId);
      final rejected = option.isNotEmpty && !option.first.allows;
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
        .where((request) =>
            sessionKey == null || request.sessionId == sessionKey)
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
      _sendRpcError(id, -32000, 'Failed to read file: $error');
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
    } catch (error) {
      _sendRpcError(id, -32000, 'Failed to write file: $error');
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
    _transport?.send(jsonEncode(value));
  }

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

  Future<String> _createRemoteSession({String? cwd}) async {
    final folder =
        cwd == null || cwd.trim().isEmpty ? _workingDirectory : cwd.trim();
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
    if (_configOptions.any((option) =>
        option.category == 'model' || option.id == 'model')) {
      return;
    }
    final models = _asMap(raw);
    final available = (models['availableModels'] as List? ?? const [])
        .map((item) {
          final value = _asMap(item);
          final id = value['modelId'] as String? ?? value['id'] as String? ?? '';
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
    final result = await _request('session/set_config_option', {
      'sessionId': remoteKey,
      'configId': configId,
      'type': option?.isBoolean == true ? 'boolean' : 'id',
      'value': value,
    });
    if (result.containsKey('configOptions')) {
      _applySessionMeta(result);
    } else {
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
      _syncModesFromConfig();
      notifyListeners();
    }
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
    _sessions[id]!.messageUpdateStream.listen(_messageUpdateController.add);
    return session;
  }

  Future<String> _ensureRemoteSession(String sessionKey, {String? cwd}) async {
    if (cwd != null && cwd.trim().isNotEmpty) {
      _sessionCwd[sessionKey] = cwd.trim();
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
    if (sessionCaps.containsKey('resume')) {
      final result = await _request('session/resume', {
        'sessionId': sessionKey,
        'cwd': workingDirectoryFor(sessionKey),
        'mcpServers': _mcpServersForAgent(),
      });
      _applySessionMeta(result);
    } else if (_agentCapabilities['loadSession'] == true) {
      final result = await _request('session/load', {
        'sessionId': sessionKey,
        'cwd': workingDirectoryFor(sessionKey),
        'mcpServers': _mcpServersForAgent(),
      });
      _applySessionMeta(result);
    } else {
      throw Exception('ACP Agent cannot resume session $sessionKey');
    }
    _attachedSessions.add(sessionKey);
    return sessionKey;
  }

  Future<void> deleteSession(String sessionKey) async {
    final sessionCaps = _asMap(_agentCapabilities['sessionCapabilities']);
    if (isConnected &&
        sessionCaps.containsKey('delete') &&
        !sessionKey.startsWith('local-')) {
      await _request('session/delete', {'sessionId': sessionKey});
    }
    _sessions.remove(sessionKey)?.disposeStreams();
    _attachedSessions.remove(sessionKey);
    _sessionCwd.remove(sessionKey);
    if (_activeSessionKey == sessionKey) _activeSessionKey = null;
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

    final result = await _request('session/list', {});
    final values = result['sessions'] as List? ?? const [];
    return values
        .map((value) {
          final item = _asMap(value);
          final id = item['sessionId'] as String? ?? '';
          final updated =
              DateTime.tryParse(item['updatedAt'] as String? ?? '') ??
                  DateTime.now();
          return ChatSession(
            id: id,
            key: id,
            title: item['title'] as String? ?? '新对话',
            createdAt: updated,
            lastUpdated: updated,
            messages: const [],
            isGatewaySession: true,
            sourceGatewayHost: _pendingGateway?.host,
          );
        })
        .where((session) => session.key.isNotEmpty)
        .toList();
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
    _sessions.putIfAbsent(remoteKey, () => _newSessionState(remoteKey))
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
    final start =
        session.messages.indexWhere((message) => message.id == sent.userMessageId);
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
    final update = _asMap(params['update']);
    final kind = update['sessionUpdate'] as String?;
    final session =
        _sessions.putIfAbsent(sessionKey, () => _newSessionState(sessionKey));

    if (kind == 'agent_message_chunk') {
      final content = _asMap(update['content']);
      final messageId = update['messageId'] as String? ??
          session.currentRunId ??
          _generateId();
      if (content['type'] == 'text') {
        _appendAgentChunk(session, messageId, content['text'] as String? ?? '');
      } else if (content['type'] == 'image') {
        final attachment = Attachment(
          id: messageId,
          filename: 'image',
          mimeType: content['mimeType'] as String? ?? 'image/png',
          size: 0,
          data: content['data'] as String?,
        );
        _appendAgentChunk(session, messageId, '', attachment: attachment);
      }
    } else if (kind == 'agent_thought_chunk') {
      final text = _contentToText(update['content']);
      if (text.isEmpty || isLeakedAgentErrorOnly(text)) return;
      _upsertSpecialMessage(
        session,
        id: 'thought-${session.currentRunId ?? session.sessionKey}',
        kind: MessageKind.thought,
        text: stripLeakedAgentError(text),
        append: true,
        streaming: _promptInFlight,
      );
    } else if (kind == 'tool_call' || kind == 'tool_call_update') {
      _upsertToolCall(session, update);
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
      notifyListeners();
    } else if (kind == 'plan') {
      _plans[sessionKey] = (update['entries'] as List? ?? const [])
          .map((item) => AcpPlanEntry.fromJson(_asMap(item)))
          .where((entry) => entry.content.isNotEmpty)
          .toList();
      notifyListeners();
    } else if (kind == 'usage_update') {
      session.model = update['model'] as String? ?? session.model;
    } else if (kind == 'session_info_update') {
      final title = update['title'] as String?;
      if (title != null && title.isNotEmpty && session.customTitle == null) {
        session.setCustomTitle(title);
      }
    }
  }

  void _upsertToolCall(SessionState session, Map<String, dynamic> update) {
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
    final status = _nonEmpty(update['status']) ??
        previous?.toolStatus ??
        'in_progress';
    final title = _nonEmpty(update['title']) ??
        _nonEmpty(update['toolName']) ??
        _nonEmpty(update['name']) ??
        previousTitle ??
        _nonEmpty(update['kind']) ??
        _toolTitleFromRawInput(update['rawInput']) ??
        '工具调用';
    final detail = _contentToText(update['content']);
    final locations = update['locations'] as List? ?? const [];
    final locationText = locations.map((item) {
      final loc = _asMap(item);
      return loc['path'] as String? ?? '';
    }).where((path) => path.isNotEmpty).join(', ');
    final body = [
      if (locationText.isNotEmpty) locationText,
      if (detail.isNotEmpty) detail else if (previousDetail.isNotEmpty) previousDetail,
    ].join('\n');
    final text = body.isEmpty ? title : '$title\n$body';
    _upsertSpecialMessage(
      session,
      id: id,
      kind: MessageKind.tool,
      text: text,
      toolCallId: toolCallId,
      toolStatus: status,
      streaming: _promptInFlight &&
          (status == 'pending' || status == 'in_progress'),
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
  }) {
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
      _messageController.add(message);
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
        final settled = session.messages[previousIndex]
            .copyWith(isStreaming: false);
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
    final streaming = _promptInFlight ||
        index < 0 ||
        session.messages[index].isStreaming;
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
      _messageController.add(message);
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
      state.messageUpdateStream.listen(_messageUpdateController.add);
      _sessions[sessionKey] = state;
    }
  }

  Future<void> loadAllSessionsFromStorage() async {
    for (final saved in await SessionStorage.loadAllSessions()) {
      if (!_sessions.containsKey(saved.key)) {
        final state = SessionState.fromChatSession(saved);
        state.messageUpdateStream.listen(_messageUpdateController.add);
        _sessions[saved.key] = state;
      }
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
    _pendingPermissions.clear();
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
