import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:pocket_bot/config/session_storage.dart';
import 'package:pocket_bot/models/attachment.dart';
import 'package:pocket_bot/models/message.dart';
import 'package:pocket_bot/models/session_state.dart';
import 'package:pocket_bot/services/acp_transport.dart';
import 'package:pocket_bot/services/cursor_agent.dart';
import 'package:pocket_bot/services/notification_service.dart';
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
  AcpTransport? _transport;
  StreamSubscription? _channelSubscription;
  ConnectionState _state = ConnectionState.disconnected;
  String? _errorMessage;
  String? _currentAgentId;
  String? _activeSessionKey;
  String _workingDirectory = '/';
  Map<String, dynamic> _agentCapabilities = const {};
  Map<String, dynamic>? _agentInfo;
  String? _currentModeId;
  List<AcpSessionMode> _availableModes = const [];
  List<AcpConfigOption> _configOptions = const [];
  List<AcpSlashCommand> _availableCommands = const [];
  List<AcpTodoItem> _todos = const [];
  Map<String, dynamic>? _pendingClientRequest;
  final _clientRequestController =
      StreamController<Map<String, dynamic>>.broadcast();

  final Map<String, SessionState> _sessions = {};
  final Set<String> _attachedSessions = {};
  final Map<String, Completer<Map<String, dynamic>>> _pendingRpc = {};
  final Map<String, String> _pendingPromptSessions = {};
  final Map<String, String> _pendingUserMessages = {};

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

  Future<void> connectTarget(GatewayInfo target) async {
    _pendingGateway = target;
    final cwd = target.kind == AgentTransportKind.local
        ? CursorAgent.resolveWorkingDirectory(target.workingDirectory)
        : (target.workingDirectory.trim().isEmpty
            ? '.'
            : target.workingDirectory);
    await _attachTransport(
      await AcpTransportFactory.open(target),
      workingDirectory: cwd,
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

      final response = await _request(
        'initialize',
        {
          'protocolVersion': 1,
          'clientCapabilities': {
            'fs': {
              'readTextFile': true,
              'writeTextFile': true,
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
        timeout: const Duration(seconds: 60),
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
      if (value.startsWith('AUTH_FAILED:') ||
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
          _upsertSpecialMessage(
            session,
            id: 'todos-${session.sessionKey}',
            kind: MessageKind.system,
            text: _todos.isEmpty
                ? '待办已清空'
                : '待办\n${_todos.map((item) => '- [${item.status == 'completed' ? 'x' : ' '}] ${item.content}').join('\n')}',
          );
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
    final options = params['options'] as List? ?? const [];
    Map<String, dynamic>? allowed;
    for (final option in options) {
      final value = _asMap(option);
      final kind = (value['kind'] as String? ?? '').replaceAll('-', '_');
      final optionId = (value['optionId'] as String? ?? '').replaceAll('-', '_');
      if (kind == 'allow_once' || optionId == 'allow_once') {
        allowed = value;
        break;
      }
      if ((kind.startsWith('allow_') || optionId.startsWith('allow_')) &&
          allowed == null) {
        allowed = value;
      }
    }
    final outcome = allowed == null
        ? {'outcome': 'cancelled'}
        : {'outcome': 'selected', 'optionId': allowed['optionId']};
    Logger.info(
      '[ACP] Auto-allowing permission ${allowed?['optionId'] ?? 'cancelled'}',
    );
    _sendJson({
      'jsonrpc': '2.0',
      'id': id,
      'result': {'outcome': outcome},
    });
  }

  Future<void> _handleReadTextFile(
      dynamic id, Map<String, dynamic> params) async {
    try {
      final file = File(_resolvePath(params['path'] as String? ?? ''));
      if (!await file.exists()) {
        _sendRpcError(id, -32000, 'File not found: ${file.path}');
        return;
      }
      var content = await file.readAsString();
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
    } catch (error) {
      _sendRpcError(id, -32000, 'Failed to read file: $error');
    }
  }

  Future<void> _handleWriteTextFile(
      dynamic id, Map<String, dynamic> params) async {
    try {
      final file = File(_resolvePath(params['path'] as String? ?? ''));
      await file.parent.create(recursive: true);
      await file.writeAsString(params['content'] as String? ?? '');
      _sendJson({
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{},
      });
    } catch (error) {
      _sendRpcError(id, -32000, 'Failed to write file: $error');
    }
  }

  String _resolvePath(String path) {
    if (path.isEmpty) return _workingDirectory;
    if (p.isAbsolute(path)) return p.normalize(path);
    return p.normalize(p.join(_workingDirectory, path));
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

  Future<String> _createRemoteSession() async {
    final result = await _request('session/new', {
      'cwd': _workingDirectory,
      'mcpServers': <dynamic>[],
    });
    final id = result['sessionId'] as String?;
    if (id == null || id.isEmpty) {
      throw Exception('ACP Agent returned no sessionId');
    }
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

  Future<ChatSession> createGatewaySession(String title) async {
    _requireConnected();
    final id = await _createRemoteSession();
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

  Future<String> _ensureRemoteSession(String sessionKey) async {
    if (_attachedSessions.contains(sessionKey)) return sessionKey;

    if (sessionKey.startsWith('local-') ||
        sessionKey.startsWith('pocketbot-')) {
      final remoteId = await _createRemoteSession();
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
        'cwd': _workingDirectory,
        'mcpServers': <dynamic>[],
      });
      _applySessionMeta(result);
    } else if (_agentCapabilities['loadSession'] == true) {
      final result = await _request('session/load', {
        'sessionId': sessionKey,
        'cwd': _workingDirectory,
        'mcpServers': <dynamic>[],
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
    _activeSessionKey = remoteKey;

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
    _sendJson({
      'jsonrpc': '2.0',
      'id': requestId,
      'method': 'session/prompt',
      'params': {'sessionId': remoteKey, 'prompt': prompt},
    });
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
      if (text.isEmpty) return;
      _upsertSpecialMessage(
        session,
        id: 'thought-${session.currentRunId ?? session.sessionKey}',
        kind: MessageKind.thought,
        text: text,
        append: true,
        streaming: true,
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
      final entries = update['entries'] as List? ?? const [];
      final text = entries.map((item) {
        final entry = _asMap(item);
        final status = entry['status'] as String? ?? 'pending';
        final mark = status == 'completed' ? 'x' : ' ';
        return '- [$mark] ${entry['content'] ?? ''}';
      }).join('\n');
      _upsertSpecialMessage(
        session,
        id: 'acp-plan-${session.sessionKey}',
        kind: MessageKind.plan,
        text: text.isEmpty ? '计划已更新' : text,
      );
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
    final status = update['status'] as String? ?? 'in_progress';
    final title = update['title'] as String? ??
        update['kind'] as String? ??
        '工具调用';
    final detail = _contentToText(update['content']);
    final locations = update['locations'] as List? ?? const [];
    final locationText = locations.map((item) {
      final loc = _asMap(item);
      return loc['path'] as String? ?? '';
    }).where((path) => path.isNotEmpty).join(', ');
    final text = [
      title,
      if (locationText.isNotEmpty) locationText,
      if (detail.isNotEmpty) detail,
    ].join('\n');
    _upsertSpecialMessage(
      session,
      id: 'tool-$toolCallId',
      kind: MessageKind.tool,
      text: text,
      toolCallId: toolCallId,
      toolStatus: status,
      streaming: status == 'pending' || status == 'in_progress',
    );
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
      case 'diff':
        return map['path'] as String? ?? '';
      case 'resource_link':
        return map['uri'] as String? ?? map['name'] as String? ?? '';
      default:
        return map['text'] as String? ?? '';
    }
  }

  void _appendAgentChunk(
    SessionState session,
    String messageId,
    String text, {
    Attachment? attachment,
  }) {
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
    if (index >= 0) {
      final old = session.messages[index];
      final updated = old.copyWith(
        text: _appendStreamText(messageId, old.text, text),
        attachments: attachment == null
            ? old.attachments
            : [...old.attachments, attachment],
        isStreaming: true,
      );
      session.patchStreamingMessage(updated);
      _publishLiveText(messageId, updated.text);
    } else {
      final initial = _appendStreamText(messageId, '', text);
      final message = Message(
        id: messageId,
        text: initial,
        isUser: false,
        timestamp: DateTime.now(),
        isStreaming: true,
        attachments: attachment == null ? const [] : [attachment],
      );
      session.addMessage(message);
      _messageController.add(message);
      _publishLiveText(messageId, initial);
    }
  }

  String _appendStreamText(String messageId, String current, String chunk) {
    final buffer = _streamText.putIfAbsent(
      messageId,
      () => StringBuffer(current),
    );
    buffer.write(chunk);
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

  void _finishStreamingMessage(SessionState session) {
    final id = session.currentRunId;
    if (id == null) return;
    final index = session.messages.indexWhere((m) => m.id == id && !m.isUser);
    if (index >= 0) {
      final live = _liveText[id] ?? _streamText[id]?.toString();
      final message = session.messages[index].copyWith(
        text: live ?? session.messages[index].text,
        isStreaming: false,
      );
      _liveText.remove(id);
      _streamText.remove(id);
      session.updateMessage(message);
      streamingTick.value++;
      if (_activeSessionKey != session.sessionKey && message.text.isNotEmpty) {
        NotificationService().showMessageNotification(
          sessionKey: session.sessionKey,
          sessionName: session.displayTitle,
          message: message.text,
        );
      }
    }
    session.currentRunId = null;
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
    notifyListeners();
  }

  void _handleSocketError(Object error) {
    Logger.error('[ACP] Transport error: $error');
    _failPending(error);
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
    for (final completer in _pendingRpc.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pendingRpc.clear();
    _pendingPromptSessions.clear();
    _pendingUserMessages.clear();
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
      await connectTarget(gateway);
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
