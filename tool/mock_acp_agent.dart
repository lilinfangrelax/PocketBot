import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Deterministic ACP agent used by PocketBot E2E tests.
///
/// Speaks newline-delimited JSON-RPC 2.0 over stdin/stdout. Every prompt is
/// answered with `MOCK_AGENT_OK: <prompt text>` split into a few streamed
/// chunks so the client's streaming path is exercised.
Future<void> main(List<String> args) async {
  var sessionCounter = 0;
  var messageCounter = 0;

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
    if (method == null) continue;
    final id = message['id'];
    final params = (message['params'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};

    switch (method) {
      case 'initialize':
        respond(id, {
          'protocolVersion': 1,
          'agentCapabilities': {
            'loadSession': false,
            'sessionCapabilities': <String, Object?>{},
            'promptCapabilities': {
              'image': false,
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
        respond(id, {
          'sessionId': 'mock-session-$sessionCounter',
          'modes': {
            'availableModes': <Object?>[],
            'currentModeId': 'agent',
          },
        });
        break;
      case 'session/prompt':
        messageCounter += 1;
        final sessionId = params['sessionId'] as String? ?? '';
        final blocks = params['prompt'] as List? ?? const [];
        final promptText = blocks
            .whereType<Map>()
            .where((block) => block['type'] == 'text')
            .map((block) => '${block['text'] ?? ''}')
            .join('\n');
        final reply = 'MOCK_AGENT_OK: $promptText';
        final messageId = 'mock-message-$messageCounter';
        final third = (reply.length / 3).ceil();
        final chunks = <String>[
          if (reply.isNotEmpty)
            reply.substring(0, third.clamp(0, reply.length)),
          if (reply.length > third)
            reply.substring(third, (third * 2).clamp(0, reply.length)),
          if (reply.length > third * 2) reply.substring(third * 2),
        ];
        for (final chunk in chunks) {
          send({
            'jsonrpc': '2.0',
            'method': 'session/update',
            'params': {
              'sessionId': sessionId,
              'update': {
                'sessionUpdate': 'agent_message_chunk',
                'messageId': messageId,
                'content': {'type': 'text', 'text': chunk},
              },
            },
          });
          await stdout.flush();
        }
        respond(id, {'stopReason': 'end_turn'});
        break;
      case 'session/cancel':
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
