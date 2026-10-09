import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_bot/models/mcp_server_config.dart';
import 'package:pocket_bot/models/message.dart';
import 'package:pocket_bot/services/acp_file_system.dart';
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
    expect(
      requests.first['params']['clientCapabilities']['fs'],
      {'readTextFile': false, 'writeTextFile': false},
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
    final service = WebSocketService()..autoApprovePermissions = true;
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

  test('keeps the tool title when a later update only changes status', () async {
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
          'content': [
            {
              'type': 'content',
              'content': {'type': 'text', 'text': 'first 40 lines'},
            },
          ],
        },
      },
    });
    transport.push({
      'jsonrpc': '2.0',
      'method': 'session/update',
      'params': {
        'sessionId': 'session-1',
        'update': {
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 'call-1',
          'status': 'completed',
        },
      },
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final session = service.getSession('session-1');
    expect(session, isNotNull);
    expect(session!.messages, hasLength(1));
    expect(session.messages.single.toolStatus, 'completed');
    expect(session.messages.single.text, contains('Read lib/main.dart'));
    expect(session.messages.single.text, contains('first 40 lines'));
    expect(session.messages.single.text, isNot(contains('工具调用')));
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
    final service = WebSocketService()..autoApprovePermissions = true;
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

  test('drops leaked stream errors and settles without stopReason', () async {
    final transport = _FakeAcpTransport();
    final service = WebSocketService();
    addTearDown(() async {
      await service.disconnect();
      await transport.close();
    });

    await _connectFake(service, transport);
    final sending = service.sendMessage('Hi');
    await transport.waitForMethod('session/new');
    transport.respondToLast({'sessionId': 'session-1'});
    await sending;
    final prompt = transport.sent.lastWhere(
      (message) => message['method'] == 'session/prompt',
    );

    transport.push({
      'jsonrpc': '2.0',
      'method': 'session/update',
      'params': {
        'sessionId': 'session-1',
        'update': {
          'sessionUpdate': 'agent_message_chunk',
          'messageId': 'agent-1',
          'content': {'type': 'text', 'text': '嗯，我在。'},
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
          'content': {
            'type': 'text',
            'text': '\n\nError: RetriableError: WritableIterable is closed',
          },
        },
      },
    });
    transport.push({
      'jsonrpc': '2.0',
      'id': prompt['id'],
      'result': <String, dynamic>{},
    });
    await Future<void>.delayed(const Duration(milliseconds: 40));

    final agent = service
        .getSession('session-1')!
        .messages
        .lastWhere((message) => !message.isUser);
    expect(agent.text, '嗯，我在。');
    expect(agent.isStreaming, isFalse);
  });
  test('routes fs requests to the transport file system', () async {
    final files = _MemoryFileSystem({'/remote/repo/a.txt': 'one\ntwo\nthree'});
    final transport = _FakeAcpTransport(fileSystem: files);
    final service = WebSocketService();
    addTearDown(() async {
      await service.disconnect();
      await transport.close();
    });

    final initialized =
        service.connectWithTransport(transport, workingDirectory: '/remote/repo');
    final init = await transport.waitForMethod('initialize');
    expect(
      init['params']['clientCapabilities']['fs'],
      {'readTextFile': true, 'writeTextFile': true},
    );
    transport.respondToLast({
      'protocolVersion': 1,
      'agentCapabilities': <String, dynamic>{},
      'authMethods': <dynamic>[],
    });
    await initialized;

    transport.push({
      'jsonrpc': '2.0',
      'id': 'read-1',
      'method': 'fs/read_text_file',
      'params': {'sessionId': 's', 'path': 'a.txt', 'line': 2, 'limit': 1},
    });
    final read = await transport.waitForResponse('read-1');
    expect(read['result']['content'], 'two');

    transport.push({
      'jsonrpc': '2.0',
      'id': 'write-1',
      'method': 'fs/write_text_file',
      'params': {'sessionId': 's', 'path': '/remote/repo/b.txt', 'content': 'x'},
    });
    await transport.waitForResponse('write-1');
    expect(files.files['/remote/repo/b.txt'], 'x');

    transport.push({
      'jsonrpc': '2.0',
      'id': 'read-2',
      'method': 'fs/read_text_file',
      'params': {'sessionId': 's', 'path': '/missing'},
    });
    final missing = await transport.waitForResponse('read-2');
    expect(missing['error']['code'], -32002);
  });

  test('rejects fs requests when the transport cannot reach files', () async {
    final transport = _FakeAcpTransport();
    final service = WebSocketService();
    addTearDown(() async {
      await service.disconnect();
      await transport.close();
    });

    await _connectFake(service, transport);
    transport.push({
      'jsonrpc': '2.0',
      'id': 'write-1',
      'method': 'fs/write_text_file',
      'params': {'sessionId': 's', 'path': '/tmp/x', 'content': 'x'},
    });
    final reply = await transport.waitForResponse('write-1');
    expect(reply['error'], isNotNull);
  });

  group('permission prompts', () {
    Map<String, dynamic> permissionRequest(String id) => {
          'jsonrpc': '2.0',
          'id': id,
          'method': 'session/request_permission',
          'params': {
            'sessionId': 'session-1',
            'toolCall': {
              'toolCallId': 'call-1',
              'title': 'Run tests',
              'kind': 'execute',
              'rawInput': {'command': 'flutter test'},
            },
            'options': [
              {'optionId': 'allow', 'name': 'Allow', 'kind': 'allow_once'},
              {
                'optionId': 'always',
                'name': 'Always allow',
                'kind': 'allow_always'
              },
              {'optionId': 'reject', 'name': 'Reject', 'kind': 'reject_once'},
            ],
          },
        };

    test('waits for the user instead of auto-allowing', () async {
      final transport = _FakeAcpTransport();
      final service = WebSocketService();
      addTearDown(() async {
        await service.disconnect();
        await transport.close();
      });

      await _connectFake(service, transport);
      transport.push(permissionRequest('perm-1'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(transport.sent.where((item) => item['id'] == 'perm-1'), isEmpty);
      final pending = service.permissionsFor('session-1').single;
      expect(pending.title, 'Run tests');
      expect(pending.detail, 'flutter test');
      expect(pending.options.map((o) => o.kind),
          ['allow_once', 'allow_always', 'reject_once']);
      expect(service.isAwaitingPermission('call-1'), isTrue);
      final tool = service.getSession('session-1')!.messages.single;
      expect(tool.kind, MessageKind.tool);

      service.respondToPermission(pending, 'reject');
      final reply = await transport.waitForResponse('perm-1');
      expect(reply['result']['outcome'],
          {'outcome': 'selected', 'optionId': 'reject'});
      expect(service.permissionsFor('session-1'), isEmpty);
      expect(
        service.getSession('session-1')!.messages.single.toolStatus,
        'failed',
      );
    });

    test('cancelling the turn cancels pending permissions', () async {
      final transport = _FakeAcpTransport();
      final service = WebSocketService();
      addTearDown(() async {
        await service.disconnect();
        await transport.close();
      });

      await _connectFake(service, transport);
      service.selectSession('session-1');
      transport.push(permissionRequest('perm-2'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      service.cancelPrompt();
      final reply = await transport.waitForResponse('perm-2');
      expect(reply['result']['outcome'], {'outcome': 'cancelled'});
      expect(
        transport.sent.map((item) => item['method']),
        contains('session/cancel'),
      );
    });

    test('turning on auto-approve answers what is already pending', () async {
      final transport = _FakeAcpTransport();
      final service = WebSocketService();
      addTearDown(() async {
        await service.disconnect();
        await transport.close();
      });

      await _connectFake(service, transport);
      transport.push(permissionRequest('perm-3'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      service.autoApprovePermissions = true;

      final reply = await transport.waitForResponse('perm-3');
      expect(reply['result']['outcome']['optionId'], 'allow');
    });
  });

  test('keeps the plan per session instead of adding chat messages', () async {
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
          'sessionUpdate': 'plan',
          'entries': [
            {'content': 'Read code', 'status': 'completed', 'priority': 'high'},
            {'content': 'Fix bug', 'status': 'in_progress', 'priority': 'high'},
          ],
        },
      },
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final plan = service.planFor('session-1');
    expect(plan.map((entry) => entry.content), ['Read code', 'Fix bug']);
    expect(plan.first.isDone, isTrue);
    expect(plan.last.isActive, isTrue);
    expect(service.planFor('other'), isEmpty);
    expect(service.getSession('session-1')!.messages, isEmpty);
  });

  test('tracks tool call diffs, commands and output', () async {
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
          'toolCallId': 'edit-1',
          'title': 'Edit main.dart',
          'kind': 'edit',
          'status': 'in_progress',
          'rawInput': {'command': 'patch'},
          'locations': [
            {'path': '/repo/lib/main.dart', 'line': 3},
          ],
          'content': [
            {
              'type': 'diff',
              'path': '/repo/lib/main.dart',
              'oldText': 'a\nb\n',
              'newText': 'a\nc\n',
            },
          ],
        },
      },
    });
    transport.push({
      'jsonrpc': '2.0',
      'method': 'session/update',
      'params': {
        'sessionId': 'session-1',
        'update': {
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 'edit-1',
          'status': 'completed',
        },
      },
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final call = service.toolCallFor('session-1', 'edit-1')!;
    expect(call.status, 'completed');
    expect(call.kind, 'edit');
    expect(call.command, 'patch');
    expect(call.locations, ['/repo/lib/main.dart:3']);
    expect(call.diffs.single.newText, 'a\nc\n');
  });

  test('passes enabled MCP servers the agent can use to session/new',
      () async {
    final transport = _FakeAcpTransport();
    final service = WebSocketService()
      ..mcpServers = const [
        McpServerConfig(
          id: '1',
          name: 'files',
          command: 'npx',
          args: ['-y', 'server-filesystem'],
          env: [McpKeyValue('TOKEN', 'x')],
        ),
        McpServerConfig(
          id: '2',
          name: 'web',
          transport: McpTransport.http,
          url: 'https://mcp.example.com',
          headers: [McpKeyValue('Authorization', 'Bearer t')],
        ),
        McpServerConfig(
          id: '3',
          name: 'events',
          transport: McpTransport.sse,
          url: 'https://sse.example.com',
        ),
        McpServerConfig(id: '4', name: 'off', command: 'x', enabled: false),
      ];
    addTearDown(() async {
      await service.disconnect();
      await transport.close();
    });

    final initialized = service.connectWithTransport(transport);
    await transport.waitForMethod('initialize');
    transport.respondToLast({
      'protocolVersion': 1,
      'agentCapabilities': {
        'mcpCapabilities': {'http': true, 'sse': false},
      },
      'authMethods': <dynamic>[],
    });
    await initialized;

    final sending = service.sendMessage('Hi');
    final request = await transport.waitForMethod('session/new');
    transport.respondToLast({'sessionId': 'session-1'});
    await sending;

    expect(request['params']['mcpServers'], [
      {
        'name': 'files',
        'command': 'npx',
        'args': ['-y', 'server-filesystem'],
        'env': [
          {'name': 'TOKEN', 'value': 'x'},
        ],
      },
      {
        'type': 'http',
        'name': 'web',
        'url': 'https://mcp.example.com',
        'headers': [
          {'name': 'Authorization', 'value': 'Bearer t'},
        ],
      },
    ]);
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
  _FakeAcpTransport({this.fileSystem});

  @override
  final AcpFileSystem? fileSystem;

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

  @override
  Future<bool> get resumed async => false;

  @override
  String? get startupError => null;

  @override
  void release() {}

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

class _MemoryFileSystem implements AcpFileSystem {
  _MemoryFileSystem(Map<String, String> initial) : files = {...initial};

  final Map<String, String> files;

  @override
  String resolve(String path, String workingDirectory) =>
      path.startsWith('/') ? path : '$workingDirectory/$path';

  @override
  Future<String> readText(String path) async {
    final value = files[path];
    if (value == null) throw AcpFileNotFound(path);
    return value;
  }

  @override
  Future<void> writeText(String path, String content) async {
    files[path] = content;
  }
}
