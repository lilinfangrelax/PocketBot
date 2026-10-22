import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Deterministic ACP agent used by PocketBot E2E tests.
///
/// Speaks newline-delimited JSON-RPC 2.0 over stdin/stdout. Ordinary prompts
/// stream `MOCK_AGENT_OK: <prompt text>`; special prompts exercise slow
/// streaming, cancellation, markdown and permission-gated tool calls.
Future<void> main(List<String> args) async {
  var sessionCounter = 0;
  var messageCounter = 0;
  var requestCounter = 0;
  final pendingClientResponses = <String, Completer<Map<String, dynamic>>>{};
  final activePrompts = <String, _ActivePrompt>{};
  final sessionConfigs = <String, Map<String, String>>{};

  void send(Map<String, Object?> payload) {
    stdout.writeln(jsonEncode(payload));
  }

  void respond(Object? id, Map<String, Object?> result) {
    send({'jsonrpc': '2.0', 'id': id, 'result': result});
  }

  void respondError(Object? id, int code, String message) {
    send({
      'jsonrpc': '2.0',
      'id': id,
      'error': {'code': code, 'message': message},
    });
  }

  Map<String, String> configFor(String sessionId) => sessionConfigs.putIfAbsent(
        sessionId,
        () => {'model': 'mock-fast', 'mode': 'agent'},
      );

  List<Map<String, Object?>> configOptionsFor(String sessionId) {
    final config = configFor(sessionId);
    return [
      {
        'id': 'model',
        'name': 'Model',
        'category': 'model',
        'type': 'select',
        'currentValue': config['model'],
        'options': [
          {'value': 'mock-fast', 'name': 'Mock Fast'},
          {'value': 'mock-smart', 'name': 'Mock Smart'},
        ],
      },
      {
        'id': 'mode',
        'name': 'Mode',
        'category': 'mode',
        'type': 'select',
        'currentValue': config['mode'],
        'options': [
          {'value': 'agent', 'name': 'Agent'},
          {'value': 'plan', 'name': 'Plan'},
        ],
      },
    ];
  }

  Map<String, Object?> sessionInfo(String sessionId) => {
        'sessionId': sessionId,
        'modes': {
          'availableModes': [
            {'id': 'agent', 'name': 'Agent'},
            {'id': 'plan', 'name': 'Plan'},
          ],
          'currentModeId': configFor(sessionId)['mode'],
        },
        'configOptions': configOptionsFor(sessionId),
      };

  Future<void> sendUpdate(
    String sessionId,
    Map<String, Object?> update,
  ) async {
    send({
      'jsonrpc': '2.0',
      'method': 'session/update',
      'params': {'sessionId': sessionId, 'update': update},
    });
    await stdout.flush();
  }

  Future<void> sendChunk(
    String sessionId,
    String messageId,
    String text,
  ) async {
    await sendUpdate(sessionId, {
      'sessionUpdate': 'agent_message_chunk',
      'messageId': messageId,
      'content': {'type': 'text', 'text': text},
    });
  }

  Future<Map<String, dynamic>> askPermission(
    String sessionId,
    String toolCallId,
  ) async {
    requestCounter += 1;
    final id = 'mock-permission-$requestCounter';
    final completer = Completer<Map<String, dynamic>>();
    pendingClientResponses[id] = completer;
    send({
      'jsonrpc': '2.0',
      'id': id,
      'method': 'session/request_permission',
      'params': {
        'sessionId': sessionId,
        'toolCall': {
          'toolCallId': toolCallId,
          'title': '运行 E2E 命令',
          'kind': 'execute',
          'status': 'pending',
          'rawInput': {'command': 'echo e2e'},
        },
        'options': [
          {
            'optionId': 'allow_once',
            'name': '允许一次',
            'kind': 'allow_once',
          },
          {
            'optionId': 'reject_once',
            'name': '拒绝',
            'kind': 'reject_once',
          },
        ],
      },
    });
    await stdout.flush();
    final response = await completer.future;
    return (response['result'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> callClient(
    String method,
    Map<String, Object?> params,
  ) async {
    requestCounter += 1;
    final id = 'mock-client-$requestCounter';
    final completer = Completer<Map<String, dynamic>>();
    pendingClientResponses[id] = completer;
    send({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params});
    await stdout.flush();
    return completer.future.timeout(const Duration(seconds: 10));
  }

  Future<void> handlePrompt(
    Object? id,
    String sessionId,
    String promptText,
    _ActivePrompt active,
  ) async {
    messageCounter += 1;
    final messageId = 'mock-message-$messageCounter';
    try {
      switch (promptText) {
        case 'e2e-stream':
          await sendChunk(sessionId, messageId, 'MOCK_STREAM:1 ');
          await Future<void>.delayed(const Duration(milliseconds: 900));
          await sendChunk(sessionId, messageId, 'MOCK_STREAM:2 ');
          await Future<void>.delayed(const Duration(milliseconds: 900));
          await sendChunk(sessionId, messageId, 'MOCK_STREAM:3');
          respond(id, {'stopReason': 'end_turn'});
          return;
        case 'e2e-slow':
          await sendChunk(sessionId, messageId, 'MOCK_SLOW:1 ');
          final cancelled = await active.cancelled.future.timeout(
            const Duration(seconds: 30),
            onTimeout: () => false,
          );
          if (cancelled) {
            respond(id, {'stopReason': 'cancelled'});
            return;
          }
          await sendChunk(sessionId, messageId, 'MOCK_SLOW:2');
          respond(id, {'stopReason': 'end_turn'});
          return;
        case 'e2e-elicit-form':
          final form = await callClient('elicitation/create', {
            'sessionId': sessionId,
            'mode': 'form',
            'message': '请填写 E2E 表单',
            'requestedSchema': {
              'type': 'object',
              'properties': {
                'name': {
                  'type': 'string',
                  'title': '名称',
                  'minLength': 1,
                },
                'port': {
                  'type': 'integer',
                  'title': '端口',
                  'minimum': 1024,
                  'maximum': 65535,
                  'default': 3000,
                },
                'enabled': {
                  'type': 'boolean',
                  'title': '启用',
                  'default': true,
                },
                'strategy': {
                  'type': 'string',
                  'title': '策略',
                  'oneOf': [
                    {'const': 'conservative', 'title': 'Conservative'},
                    {'const': 'balanced', 'title': 'Balanced'},
                  ],
                  'default': 'balanced',
                },
              },
              'required': ['name'],
            },
          });
          final formResult =
              (form['result'] as Map?)?.cast<String, dynamic>() ??
                  const <String, dynamic>{};
          final content =
              (formResult['content'] as Map?) ?? const <String, dynamic>{};
          await sendChunk(
            sessionId,
            messageId,
            'MOCK_ELICIT: ${formResult['action']} '
            '${content['name']}|${content['port']}|'
            '${content['enabled']}|${content['strategy']}',
          );
          respond(id, {'stopReason': 'end_turn'});
          return;
        case 'e2e-elicit-url':
          final urlReply = await callClient('elicitation/create', {
            'mode': 'url',
            'elicitationId': 'mock-url-1',
            'url': 'https://example.com/authorize',
            'message': '请授权示例服务',
          });
          final urlResult =
              (urlReply['result'] as Map?)?.cast<String, dynamic>() ??
                  const <String, dynamic>{};
          if (urlResult['action'] == 'accept') {
            send({
              'jsonrpc': '2.0',
              'method': 'elicitation/complete',
              'params': {'elicitationId': 'mock-url-1'},
            });
            await stdout.flush();
          }
          await sendChunk(
            sessionId,
            messageId,
            'MOCK_ELICIT_URL: ${urlResult['action']}',
          );
          respond(id, {'stopReason': 'end_turn'});
          return;
        case 'e2e-markdown':
          await sendChunk(
            sessionId,
            messageId,
            '**E2E Markdown**\n\n```dart\nprint(\'hello\');\n```',
          );
          respond(id, {'stopReason': 'end_turn'});
          return;
        case 'e2e-plan':
          await sendUpdate(sessionId, {
            'sessionUpdate': 'plan',
            'entries': [
              {
                'content': '检查现有配置',
                'status': 'completed',
                'priority': 'high',
              },
              {
                'content': '连接 Mock 代理',
                'status': 'in_progress',
                'priority': 'high',
              },
              {
                'content': '发送验收消息',
                'status': 'pending',
                'priority': 'medium',
              },
            ],
          });
          await sendChunk(sessionId, messageId, 'MOCK_PLAN_OK');
          respond(id, {'stopReason': 'end_turn'});
          return;
        case 'e2e-todos':
          send({
            'jsonrpc': '2.0',
            'method': 'cursor/update_todos',
            'params': {
              'sessionId': sessionId,
              'todos': [
                {
                  'id': 'todo-read',
                  'content': '阅读 ACP 代码',
                  'status': 'completed',
                },
                {
                  'id': 'todo-test',
                  'content': '补充 E2E 测试',
                  'status': 'in_progress',
                },
              ],
            },
          });
          await stdout.flush();
          await sendChunk(sessionId, messageId, 'MOCK_TODOS_OK');
          respond(id, {'stopReason': 'end_turn'});
          return;
        case 'e2e-fs':
          const path = 'pocketbot-e2e-fs.txt';
          final write = await callClient('fs/write_text_file', {
            'sessionId': sessionId,
            'path': path,
            'content': 'E2E_FS_OK',
          });
          if (write['error'] != null) {
            await sendChunk(
              sessionId,
              messageId,
              'MOCK_FS_WRITE_ERROR: ${write['error']}',
            );
            respond(id, {'stopReason': 'end_turn'});
            return;
          }
          final read = await callClient('fs/read_text_file', {
            'sessionId': sessionId,
            'path': path,
          });
          try {
            File(path).deleteSync();
          } catch (_) {}
          final content = (read['result'] as Map?)?['content'];
          await sendChunk(
            sessionId,
            messageId,
            content == null
                ? 'MOCK_FS_READ_ERROR: ${read['error']}'
                : 'MOCK_FS: $content',
          );
          respond(id, {'stopReason': 'end_turn'});
          return;
        case 'e2e-terminal':
          final created = await callClient('terminal/create', {
            'sessionId': sessionId,
            'command': Platform.isWindows ? 'cmd' : 'sh',
            'args': Platform.isWindows
                ? ['/d', '/c', 'echo terminal-e2e']
                : ['-c', 'echo terminal-e2e'],
            'outputByteLimit': 1024,
          });
          final terminalId =
              ((created['result'] as Map?)?['terminalId'])?.toString();
          if (terminalId == null) {
            await sendChunk(
              sessionId,
              messageId,
              'MOCK_TERMINAL_ERROR: ${created['error']}',
            );
            respond(id, {'stopReason': 'end_turn'});
            return;
          }
          final exit = await callClient('terminal/wait_for_exit', {
            'sessionId': sessionId,
            'terminalId': terminalId,
          });
          final output = await callClient('terminal/output', {
            'sessionId': sessionId,
            'terminalId': terminalId,
          });
          final released = await callClient('terminal/release', {
            'sessionId': sessionId,
            'terminalId': terminalId,
          });
          final exitStatus = (exit['result'] as Map?) ?? const {};
          final outputResult = (output['result'] as Map?) ?? const {};
          await sendChunk(
            sessionId,
            messageId,
            'MOCK_TERMINAL: exit=${exitStatus['exitCode']} '
            'output=${'${outputResult['output']}'.trim()} '
            'released=${released['error'] == null}',
          );
          respond(id, {'stopReason': 'end_turn'});
          return;
        case 'e2e-tool':
          final toolCallId = 'mock-tool-$messageCounter';
          await sendUpdate(sessionId, {
            'sessionUpdate': 'tool_call',
            'toolCallId': toolCallId,
            'title': '运行 E2E 命令',
            'kind': 'execute',
            'status': 'pending',
            'rawInput': {'command': 'echo e2e'},
          });
          final result = await askPermission(sessionId, toolCallId);
          if (active.cancelled.isCompleted) {
            respond(id, {'stopReason': 'cancelled'});
            return;
          }
          final outcome =
              (result['outcome'] as Map?)?.cast<String, dynamic>() ??
                  const <String, dynamic>{};
          final optionId = outcome['optionId'] as String?;
          final allowed = optionId == 'allow_once';
          await sendUpdate(sessionId, {
            'sessionUpdate': 'tool_call_update',
            'toolCallId': toolCallId,
            'status': allowed ? 'completed' : 'failed',
            'content': [
              {
                'type': 'content',
                'content': {
                  'type': 'text',
                  'text': allowed ? 'E2E_TOOL_OK' : 'E2E_TOOL_REJECTED',
                },
              },
            ],
          });
          await sendChunk(
            sessionId,
            messageId,
            allowed
                ? 'MOCK_TOOL_ALLOWED: $promptText'
                : 'MOCK_TOOL_DENIED: $promptText',
          );
          respond(id, {'stopReason': 'end_turn'});
          return;
        default:
          final reply = 'MOCK_AGENT_OK: $promptText';
          final third = (reply.length / 3).ceil();
          final chunks = <String>[
            if (reply.isNotEmpty)
              reply.substring(0, third.clamp(0, reply.length)),
            if (reply.length > third)
              reply.substring(third, (third * 2).clamp(0, reply.length)),
            if (reply.length > third * 2) reply.substring(third * 2),
          ];
          for (final chunk in chunks) {
            await sendChunk(sessionId, messageId, chunk);
          }
          respond(id, {'stopReason': 'end_turn'});
      }
    } finally {
      activePrompts.remove(sessionId);
    }
  }

  final lines = stdin.transform(utf8.decoder).transform(const LineSplitter());

  await for (final line in lines) {
    if (line.trim().isEmpty) continue;
    Map<String, dynamic> message;
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map) continue;
      message = decoded.cast<String, dynamic>();
    } catch (_) {
      continue;
    }

    final method = message['method'] as String?;
    if (method == null) {
      final id = message['id']?.toString();
      final completer = id == null ? null : pendingClientResponses.remove(id);
      if (completer != null && !completer.isCompleted) {
        completer.complete(message);
      }
      continue;
    }
    final id = message['id'];
    final params = (message['params'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};

    switch (method) {
      case 'initialize':
        respond(id, {
          'protocolVersion': 1,
          'agentCapabilities': {
            'loadSession': false,
            'sessionCapabilities': {'resume': <String, Object?>{}},
            'promptCapabilities': {
              'image': true,
              'audio': false,
              'embeddedContext': false,
            },
          },
          'authMethods': <Object?>[],
          'agentInfo': {
            'name': 'PocketBot Mock Agent',
            'title': 'PocketBot Mock Agent',
            'version': '1.0.0',
          },
        });
        break;
      case 'session/new':
        sessionCounter += 1;
        final newSessionId = 'mock-session-$sessionCounter';
        respond(id, sessionInfo(newSessionId));
        await sendUpdate(newSessionId, {
          'sessionUpdate': 'available_commands_update',
          'availableCommands': [
            {'name': 'reset', 'description': '清空上下文（模拟）'},
            {'name': 'plan', 'description': '请求代理制定计划'},
          ],
        });
        break;
      case 'session/resume':
      case 'session/load':
        respond(id, sessionInfo(params['sessionId'] as String? ?? ''));
        break;
      case 'session/set_config_option':
        final configSession = params['sessionId'] as String? ?? '';
        final configId = params['configId'] as String? ?? '';
        if (configId.isNotEmpty) {
          configFor(configSession)[configId] = '${params['value']}';
        }
        respond(id, {'configOptions': configOptionsFor(configSession)});
        break;
      case 'session/set_mode':
        final modeSession = params['sessionId'] as String? ?? '';
        final modeId = params['modeId'] as String? ?? '';
        if (modeId.isNotEmpty) configFor(modeSession)['mode'] = modeId;
        respond(id, <String, Object?>{});
        break;
      case 'session/prompt':
        final sessionId = params['sessionId'] as String? ?? '';
        final blocks = params['prompt'] as List? ?? const [];
        final imageCount = blocks.whereType<Map>().where((block) {
          return block['type'] == 'image' &&
              block['mimeType'] is String &&
              (block['data'] as String?)?.isNotEmpty == true;
        }).length;
        final promptText = [
          ...blocks
              .whereType<Map>()
              .where((block) => block['type'] == 'text')
              .map((block) => '${block['text'] ?? ''}'),
          if (imageCount > 0) 'MOCK_IMAGES: $imageCount',
        ].join('\n');
        final active = _ActivePrompt(sessionId);
        activePrompts[sessionId] = active;
        unawaited(handlePrompt(id, sessionId, promptText, active));
        break;
      case 'session/cancel':
        final sessionId = params['sessionId'] as String?;
        if (sessionId != null) activePrompts[sessionId]?.cancel();
        break;
      case 'logout':
        respond(id, <String, Object?>{});
        break;
      default:
        if (id != null) {
          respondError(id, -32601, 'Method not found: $method');
        }
    }
  }
  await stdout.flush();
  exit(0);
}

class _ActivePrompt {
  _ActivePrompt(this.sessionId);

  final String sessionId;
  final Completer<bool> cancelled = Completer<bool>();

  void cancel() {
    if (!cancelled.isCompleted) cancelled.complete(true);
  }
}
