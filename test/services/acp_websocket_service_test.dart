import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_bot/models/message.dart';
import 'package:pocket_bot/services/acp_transport.dart';
import 'package:pocket_bot/services/websocket_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('uses the ACP v1 WebSocket lifecycle and streams message chunks',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <Map<String, dynamic>>[];
    final authorization = Completer<String?>();

    server.listen((request) async {
      expect(request.uri.path, '/acp');
      if (!authorization.isCompleted) {
        authorization
            .complete(request.headers.value(HttpHeaders.authorizationHeader));
      }
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((data) {
        final message = Map<String, dynamic>.from(jsonDecode(data as String));
        requests.add(message);
        final id = message['id'];
        switch (message['method']) {
          case 'initialize':
            socket.add(jsonEncode({
              'jsonrpc': '2.0',
              'id': id,
              'result': {
                'protocolVersion': 1,
                'agentCapabilities': {
                  'sessionCapabilities': {'list': {}, 'resume': {}}
                },
                'agentInfo': {
                  'name': 'test-agent',
                  'title': 'Test Agent',
                  'version': '1.0.0',
                },
                'authMethods': <dynamic>[],
              },
            }));
          case 'session/new':
            socket.add(jsonEncode({
              'jsonrpc': '2.0',
              'id': id,
              'result': {'sessionId': 'session-1'},
            }));
          case 'session/prompt':
            socket.add(jsonEncode({
              'jsonrpc': '2.0',
              'method': 'session/update',
              'params': {
                'sessionId': 'session-1',
                'update': {
                  'sessionUpdate': 'agent_message_chunk',
                  'messageId': 'agent-message-1',
                  'content': {'type': 'text', 'text': 'Hello from ACP'},
                },
              },
            }));
            socket.add(jsonEncode({
              'jsonrpc': '2.0',
              'id': id,
              'result': {'stopReason': 'end_turn'},
            }));
        }
      });
    });

    final service = WebSocketService();
    addTearDown(() async {
      await service.disconnect();
      await server.close(force: true);
    });

    await service.connect(
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      token: 'secret',
      workingDirectory: '/workspace',
    );
    expect(service.isConnected, isTrue);
    expect(service.currentAgentId, 'test-agent');
    expect(await authorization.future, 'Bearer secret');
    expect(
      requests.first['params']['clientCapabilities']['_meta']
          ['parameterizedModelPicker'],
      isTrue,
    );

    service.createNewSession();
    final response = service.messages.firstWhere((message) => !message.isUser);
    await service.sendMessage('Hello');
    final agentMessage = await response.timeout(const Duration(seconds: 2));

    expect(agentMessage.text, 'Hello from ACP');
    expect(service.currentSessionKey, 'session-1');
    expect(
      requests.map((request) => request['method']),
      containsAllInOrder(['initialize', 'session/new', 'session/prompt']),
    );
    final prompt = requests.last['params']['prompt'] as List;
    expect(prompt.single, {'type': 'text', 'text': 'Hello'});
  });

  test('auto-allows session/request_permission with allow_once', () async {
    final transport = _FakeAcpTransport();
    final service = WebSocketService();
    addTearDown(() async {
      await service.disconnect();
      await transport.close();
    });

    final initialized = service.connectWithTransport(transport);
    await transport.waitForMethod('initialize');
    transport.respondToLast({
      'protocolVersion': 1,
      'agentCapabilities': <String, dynamic>{},
      'agentInfo': {'name': 'cursor-agent'},
      'authMethods': <dynamic>[],
    });
    await initialized;
    expect(service.isConnected, isTrue);

    transport.push({
      'jsonrpc': '2.0',
      'id': 'perm-1',
      'method': 'session/request_permission',
      'params': {
        'sessionId': 'session-1',
        'toolCall': {'toolCallId': 'call-1'},
        'options': [
          {'optionId': 'allow-once', 'name': 'Allow once', 'kind': 'allow_once'},
          {
            'optionId': 'reject-once',
            'name': 'Reject once',
            'kind': 'reject_once'
          },
        ],
      },
    });

    final reply = await transport.waitForResponse('perm-1');
    expect(reply['result']['outcome']['outcome'], 'selected');
    expect(reply['result']['outcome']['optionId'], 'allow-once');
  });

  test('authenticates with cursor_login when the agent advertises it', () async {
    final transport = _FakeAcpTransport();
    final service = WebSocketService();
    addTearDown(() async {
      await service.disconnect();
      await transport.close();
    });

    await _connectFake(
      service,
      transport,
      authMethods: [
        {'id': 'cursor_login', 'name': 'Cursor Login'},
      ],
    );

    expect(
      transport.sent.map((request) => request['method']),
      containsAllInOrder(['initialize', 'authenticate']),
    );
    expect(transport.sent[1]['params']['methodId'], 'cursor_login');
  });

  test('creates a remote session automatically when none is selected', () async {
    final transport = _FakeAcpTransport();
    final service = WebSocketService();
    addTearDown(() async {
      await service.disconnect();
      await transport.close();
    });

    await _connectFake(service, transport);
    final sending = service.sendMessage('Hello');
    await transport.waitForMethod('session/new');
    transport.respondToLast({
      'sessionId': 'session-1',
      'modes': {
        'currentModeId': 'agent',
        'availableModes': [
          {'id': 'agent', 'name': 'Agent'},
          {'id': 'plan', 'name': 'Plan'},
          {'id': 'ask', 'name': 'Ask'},
        ],
      },
    });
    await sending;

    expect(service.currentSessionKey, 'session-1');
    expect(service.currentModeId, 'agent');
    expect(service.availableModes.map((mode) => mode.id), ['agent', 'plan', 'ask']);
    expect(
      transport.sent.map((request) => request['method']),
      contains('session/prompt'),
    );
  });

  test('renders tool calls and slash commands from session/update', () async {
    final transport = _FakeAcpTransport();
    final service = WebSocketService();
    addTearDown(() async {
      await service.disconnect();
      await transport.close();
    });

    await _connectFake(service, transport);
    transport.push({
      'jsonrpc': '2.0',
      'method': 'session/update',
      'params': {
        'sessionId': 'session-1',
        'update': {
          'sessionUpdate': 'tool_call',
          'toolCallId': 'call-1',
          'title': 'Read lib/main.dart',
          'kind': 'read',
          'status': 'in_progress',
        },
      },
    });
    transport.push({
      'jsonrpc': '2.0',
      'method': 'session/update',
      'params': {
        'sessionId': 'session-1',
        'update': {
          'sessionUpdate': 'available_commands_update',
          'availableCommands': [
            {'name': 'reset', 'description': 'Reset the conversation'},
          ],
        },
      },
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final session = service.getSession('session-1');
    expect(session, isNotNull);
    expect(session!.messages.single.kind, MessageKind.tool);
    expect(session.messages.single.text, contains('Read lib/main.dart'));
    expect(service.availableCommands.single.name, 'reset');
  });

  test('auto-skips cursor/ask_question when no chat UI is attached', () async {
    final transport = _FakeAcpTransport();
    final service = WebSocketService();
    addTearDown(() async {
      await service.disconnect();
      await transport.close();
    });

    await _connectFake(service, transport);
    transport.push({
      'jsonrpc': '2.0',
      'id': 'q-1',
      'method': 'cursor/ask_question',
      'params': {
        'title': 'Need input',
        'questions': [
          {
            'id': 'q1',
            'prompt': 'Which mode?',
            'options': [
              {'id': 'agent', 'label': 'Agent'},
            ],
          },
        ],
      },
    });

    final reply = await transport.waitForResponse('q-1');
    expect(reply['result']['outcome']['outcome'], 'skipped');
  });

  test('forwards cursor/ask_question to a listening chat UI', () async {
    final transport = _FakeAcpTransport();
    final service = WebSocketService();
    addTearDown(() async {
      await service.disconnect();
      await transport.close();
    });

    await _connectFake(service, transport);
    final seen = <Map<String, dynamic>>[];
    final sub = service.clientRequests.listen(seen.add);
    addTearDown(sub.cancel);

    transport.push({
      'jsonrpc': '2.0',
      'id': 'q-2',
      'method': 'cursor/ask_question',
      'params': {
        'questions': [
          {'id': 'q1', 'prompt': 'Pick one', 'options': []},
        ],
      },
    });
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(seen, isNotEmpty);
    expect(
      transport.sent.where((item) => item['id'] == 'q-2'),
      isEmpty,
    );

    service.respondToAgentRequest('q-2', {
      'outcome': {
        'outcome': 'answered',
        'answers': [
          {
            'questionId': 'q1',
            'selectedOptionIds': ['agent'],
          },
        ],
      },
    });
    final reply = await transport.waitForResponse('q-2');
    expect(reply['result']['outcome']['outcome'], 'answered');
  });

  test('allows permission when only optionId uses hyphens', () async {
    final transport = _FakeAcpTransport();
    final service = WebSocketService();
    addTearDown(() async {
      await service.disconnect();
      await transport.close();
    });

    await _connectFake(service, transport);
    transport.push({
      'jsonrpc': '2.0',
      'id': 'perm-2',
      'method': 'session/request_permission',
      'params': {
        'sessionId': 'session-1',
        'options': [
          {'optionId': 'allow-always', 'name': 'Always'},
          {'optionId': 'reject-once', 'name': 'Reject'},
        ],
      },
    });

    final reply = await transport.waitForResponse('perm-2');
    expect(reply['result']['outcome']['optionId'], 'allow-always');
  });

  test('parses session config options and sets them over ACP', () async {
    final transport = _FakeAcpTransport();
    final service = WebSocketService();
    addTearDown(() async {
      await service.disconnect();
      await transport.close();
    });

    await _connectFake(service, transport);
    final sending = service.sendMessage('Hello');
    await transport.waitForMethod('session/new');
    transport.respondToLast({
      'sessionId': 'session-1',
      'configOptions': [
        {
          'id': 'mode',
          'name': 'Mode',
          'category': 'mode',
          'type': 'select',
          'currentValue': 'agent',
          'options': [
            {'value': 'agent', 'name': 'Agent'},
            {'value': 'plan', 'name': 'Plan'},
          ],
        },
        {
          'id': 'model',
          'name': 'Model',
          'category': 'model',
          'type': 'select',
          'currentValue': 'grok-4.6',
          'options': [
            {'value': 'grok-4.6', 'name': 'Cursor Grok 4.6'},
            {'value': 'composer-2.5', 'name': 'Composer 2.5'},
          ],
        },
        {
          'id': 'effort',
          'name': 'Effort',
          'category': 'thought_level',
          'type': 'select',
          'currentValue': 'high',
          'options': [
            {'value': 'low', 'name': 'Low'},
            {'value': 'high', 'name': 'High'},
          ],
        },
        {
          'id': 'fast',
          'name': 'Fast',
          'category': 'model_config',
          'type': 'select',
          'currentValue': 'true',
          'options': [
            {'value': 'false', 'name': 'Off'},
            {'value': 'true', 'name': 'Fast'},
          ],
        },
      ],
    });
    await sending;

    expect(service.configOptions.map((option) => option.id),
        ['mode', 'model', 'effort', 'fast']);
    expect(service.currentModeId, 'agent');

    final setting = service.setConfigOption('model', 'composer-2.5');
    await transport.waitForMethod('session/set_config_option');
    expect(transport.sent.last['params']['configId'], 'model');
    expect(transport.sent.last['params']['value'], 'composer-2.5');
    transport.respondToLast({
      'configOptions': [
        {
          'id': 'model',
          'name': 'Model',
          'category': 'model',
          'type': 'select',
          'currentValue': 'composer-2.5',
          'options': [
            {'value': 'grok-4.6', 'name': 'Cursor Grok 4.6'},
            {'value': 'composer-2.5', 'name': 'Composer 2.5'},
          ],
        },
      ],
    });
    await setting;
    expect(service.configOptions.single.currentId, 'composer-2.5');
  });

  test('refreshes config options from session/update', () async {
    final transport = _FakeAcpTransport();
    final service = WebSocketService();
    addTearDown(() async {
      await service.disconnect();
      await transport.close();
    });

    await _connectFake(service, transport);
    transport.push({
      'jsonrpc': '2.0',
      'method': 'session/update',
      'params': {
        'sessionId': 'session-1',
        'update': {
          'sessionUpdate': 'config_option_update',
          'configOptions': [
            {
              'configId': 'fast',
              'name': 'Fast',
              'category': 'model_config',
              'type': 'select',
              'currentValue': 'false',
              'options': [
                {'value': 'false', 'name': 'Off'},
                {'value': 'true', 'name': 'Fast'},
              ],
            },
          ],
        },
      },
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(service.configOptions.single.id, 'fast');
    expect(service.configOptions.single.currentId, 'false');
  });

  test('concatenates streamed agent text from pre-decoded maps', () async {
    final transport = _FakeAcpTransport();
    final service = WebSocketService();
    addTearDown(() async {
      await service.disconnect();
      await transport.close();
    });

    await _connectFake(service, transport);
    transport.pushMap({
      'jsonrpc': '2.0',
      'method': 'session/update',
      'params': {
        'sessionId': 'session-1',
        'update': {
          'sessionUpdate': 'agent_message_chunk',
          'messageId': 'agent-1',
          'content': {'type': 'text', 'text': 'Hel'},
        },
      },
    });
    transport.pushMap({
      'jsonrpc': '2.0',
      'method': 'session/update',
      'params': {
        'sessionId': 'session-1',
        'update': {
          'sessionUpdate': 'agent_message_chunk',
          'messageId': 'agent-1',
          'content': {'type': 'text', 'text': 'lo'},
        },
      },
    });
    await Future<void>.delayed(Duration.zero);

    expect(service.streamingTextFor('agent-1'), 'Hello');
    expect(service.getSession('session-1')!.messages.single.text, 'Hello');
  });

  test('flushes coalesced string chunks before a prompt result', () async {
    final transport = _FakeAcpTransport();
    final service = WebSocketService();
    addTearDown(() async {
      await service.disconnect();
      await transport.close();
    });

    await _connectFake(service, transport);
    transport.push({
      'jsonrpc': '2.0',
      'method': 'session/update',
      'params': {
        'sessionId': 'session-1',
        'update': {
          'sessionUpdate': 'agent_message_chunk',
          'messageId': 'agent-1',
          'content': {'type': 'text', 'text': 'Hel'},
        },
      },
    });
    transport.push({
      'jsonrpc': '2.0',
      'method': 'session/update',
      'params': {
        'sessionId': 'session-1',
        'update': {
          'sessionUpdate': 'agent_message_chunk',
          'messageId': 'agent-1',
          'content': {'type': 'text', 'text': 'lo'},
        },
      },
    });
    transport.push({
      'jsonrpc': '2.0',
      'id': 'unused',
      'result': {'stopReason': 'end_turn'},
    });
    await Future<void>.delayed(Duration.zero);

    expect(service.getSession('session-1')!.messages.single.text, 'Hello');
  });
}

Future<void> _connectFake(
  WebSocketService service,
  _FakeAcpTransport transport, {
  List<dynamic> authMethods = const [],
}) async {
  final initialized = service.connectWithTransport(transport);
  await transport.waitForMethod('initialize');
  transport.respondToLast({
    'protocolVersion': 1,
    'agentCapabilities': <String, dynamic>{},
    'agentInfo': {'name': 'cursor-agent'},
    'authMethods': authMethods,
  });
  if (authMethods.isNotEmpty) {
    await transport.waitForMethod('authenticate');
    transport.respondToLast(<String, dynamic>{});
  }
  await initialized;
}

class _FakeAcpTransport implements AcpTransport {
  final _incoming = StreamController<dynamic>.broadcast();
  final sent = <Map<String, dynamic>>[];

  @override
  Stream<dynamic> get incoming => _incoming.stream;

  @override
  void send(String jsonFrame) {
    sent.add(Map<String, dynamic>.from(jsonDecode(jsonFrame)));
  }

  @override
  Future<void> close() async {
    if (!_incoming.isClosed) await _incoming.close();
  }

  void push(Map<String, dynamic> message) {
    _incoming.add(jsonEncode(message));
  }

  void pushMap(Map<String, dynamic> message) {
    _incoming.add(message);
  }

  void respondToLast(Map<String, dynamic> result) {
    final request = sent.last;
    push({
      'jsonrpc': '2.0',
      'id': request['id'],
      'result': result,
    });
  }

  Future<Map<String, dynamic>> waitForMethod(String method) async {
    for (var i = 0; i < 50; i++) {
      final match = sent.cast<Map<String, dynamic>?>().lastWhere(
            (item) => item?['method'] == method,
            orElse: () => null,
          );
      if (match != null) return match;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw TimeoutException('Did not send ACP method $method');
  }

  Future<Map<String, dynamic>> waitForResponse(Object id) async {
    for (var i = 0; i < 50; i++) {
      final match = sent.cast<Map<String, dynamic>?>().lastWhere(
            (item) =>
                item != null &&
                item['id'] == id &&
                (item.containsKey('result') || item.containsKey('error')),
            orElse: () => null,
          );
      if (match != null) return match;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw TimeoutException('Did not send ACP response $id');
  }
}
