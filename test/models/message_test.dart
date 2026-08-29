import 'package:pocket_bot/models/message.dart';
import 'package:test/test.dart';

void main() {
  group('Message Model Tests', () {
    test('Create message with all fields', () {
      final message = Message(
        id: 'test-123',
        text: 'Hello, World!',
        isUser: true,
        timestamp: DateTime(2024, 1, 1, 12, 0, 0),
      );

      expect(message.id, 'test-123');
      expect(message.text, 'Hello, World!');
      expect(message.isUser, true);
      expect(message.timestamp, DateTime(2024, 1, 1, 12, 0, 0));
    });

    test('Message equality', () {
      final message1 = Message(
        id: 'test-123',
        text: 'Hello',
        isUser: true,
        timestamp: DateTime.now(),
      );

      final message2 = Message(
        id: 'test-123',
        text: 'Different text',
        isUser: false,
        timestamp: DateTime.now(),
      );

      expect(message1, equals(message2));
    });

    test('Message to JSON', () {
      final timestamp = DateTime(2024, 1, 1, 12, 0, 0);
      final message = Message(
        id: 'test-123',
        text: 'Hello',
        isUser: true,
        timestamp: timestamp,
      );

      final json = message.toJson();

      expect(json['id'], 'test-123');
      expect(json['text'], 'Hello');
      expect(json['isUser'], true);
      expect(json['timestamp'], timestamp.toIso8601String());
    });

    test('Message from JSON', () {
      final json = {
        'id': 'test-456',
        'text': 'Test message',
        'isUser': false,
        'timestamp': '2024-01-01T12:00:00.000',
      };

      final message = Message.fromJson(json);

      expect(message.id, 'test-456');
      expect(message.text, 'Test message');
      expect(message.isUser, false);
      expect(message.timestamp, DateTime(2024, 1, 1, 12, 0, 0));
    });

    test('Message from JSON with null fields', () {
      final json = <String, dynamic>{};

      final message = Message.fromJson(json);

      expect(message.id, '');
      expect(message.text, '');
      expect(message.isUser, false);
    });

    test('Message copyWith updates id', () {
      final original = Message(
        id: 'original-id',
        text: 'Original text',
        isUser: true,
        timestamp: DateTime(2024, 1, 1),
      );

      final copied = original.copyWith(id: 'new-id');

      expect(copied.id, 'new-id');
      expect(copied.text, 'Original text');
      expect(copied.isUser, true);
    });

    test('Message copyWith updates text', () {
      final original = Message(
        id: 'test-id',
        text: 'Original',
        isUser: true,
        timestamp: DateTime.now(),
      );

      final copied = original.copyWith(text: 'Updated');

      expect(copied.id, 'test-id');
      expect(copied.text, 'Updated');
    });

    test('Message copyWith updates isUser', () {
      final original = Message(
        id: 'test-id',
        text: 'Message',
        isUser: true,
        timestamp: DateTime.now(),
      );

      final copied = original.copyWith(isUser: false);

      expect(copied.isUser, false);
    });

    test('Message copyWith updates timestamp', () {
      final original = Message(
        id: 'test-id',
        text: 'Message',
        isUser: true,
        timestamp: DateTime(2024, 1, 1),
      );
      final newTimestamp = DateTime(2024, 6, 15);

      final copied = original.copyWith(timestamp: newTimestamp);

      expect(copied.timestamp, newTimestamp);
    });

    test('Message copyWith updates isStreaming', () {
      final original = Message(
        id: 'test-id',
        text: 'Streaming...',
        isUser: false,
        timestamp: DateTime.now(),
        isStreaming: false,
      );

      final copied = original.copyWith(isStreaming: true);

      expect(copied.isStreaming, true);
    });

    test('Message copyWith updates readAt', () {
      final original = Message(
        id: 'test-id',
        text: 'Message',
        isUser: false,
        timestamp: DateTime.now(),
      );

      final readAt = DateTime.now();
      final copied = original.copyWith(readAt: readAt);

      expect(copied.readAt, readAt);
    });

    test('Message copyWith preserves unchanged fields', () {
      final timestamp = DateTime(2024, 1, 1);
      final original = Message(
        id: 'test-id',
        text: 'Message text',
        isUser: true,
        timestamp: timestamp,
        isStreaming: true,
      );

      final copied = original.copyWith();

      expect(copied.id, 'test-id');
      expect(copied.text, 'Message text');
      expect(copied.isUser, true);
      expect(copied.timestamp, timestamp);
      expect(copied.isStreaming, true);
    });

    test('Message confirmed field defaults to false', () {
      final message = Message(
        id: 'test-id',
        text: 'Hello',
        isUser: true,
        timestamp: DateTime.now(),
      );

      expect(message.confirmed, false);
    });

    test('Message confirmed field can be set to true', () {
      final message = Message(
        id: 'test-id',
        text: 'Hello',
        isUser: true,
        timestamp: DateTime.now(),
        confirmed: true,
      );

      expect(message.confirmed, true);
    });

    test('Message copyWith updates confirmed', () {
      final original = Message(
        id: 'test-id',
        text: 'Hello',
        isUser: true,
        timestamp: DateTime.now(),
        confirmed: false,
      );

      final copied = original.copyWith(confirmed: true);

      expect(original.confirmed, false);
      expect(copied.confirmed, true);
      expect(copied.id, 'test-id');
      expect(copied.text, 'Hello');
    });

    test('Message to JSON includes confirmed field', () {
      final message = Message(
        id: 'test-id',
        text: 'Hello',
        isUser: true,
        timestamp: DateTime(2024, 1, 1),
        confirmed: true,
      );

      final json = message.toJson();

      expect(json['confirmed'], true);
    });

    test('Message from JSON includes confirmed field', () {
      final json = {
        'id': 'test-id',
        'text': 'Hello',
        'isUser': true,
        'timestamp': '2024-01-01T12:00:00.000',
        'confirmed': true,
      };

      final message = Message.fromJson(json);

      expect(message.confirmed, true);
    });

    test('Message from JSON defaults confirmed to false when missing', () {
      final json = {
        'id': 'test-id',
        'text': 'Hello',
        'isUser': true,
        'timestamp': '2024-01-01T12:00:00.000',
      };

      final message = Message.fromJson(json);

      expect(message.confirmed, false);
    });
  });

  group('GatewayInfo Model Tests', () {
    test('Create gateway info', () {
      final gateway = GatewayInfo(
        host: '192.168.1.100',
        port: 18789,
        token: 'test-token',
        name: 'ACP Agent',
        version: '1.0.0',
      );

      expect(gateway.host, '192.168.1.100');
      expect(gateway.port, 18789);
      expect(gateway.token, 'test-token');
      expect(gateway.name, 'ACP Agent');
      expect(gateway.version, '1.0.0');
    });

    test('Gateway URI generation', () {
      final gateway = GatewayInfo(
        host: '192.168.1.100',
        port: 18789,
        token: 'test-token',
      );

      expect(gateway.uri, 'ssh://192.168.1.100:18789');
    });

    test('Gateway equality', () {
      final gateway1 = GatewayInfo(
        host: '192.168.1.100',
        port: 18789,
        token: 'token1',
      );

      final gateway2 = GatewayInfo(
        host: '192.168.1.100',
        port: 18789,
        token: 'token2',
      );

      expect(gateway1, equals(gateway2));
    });

    test('Gateway to JSON', () {
      final gateway = GatewayInfo(
        host: '192.168.1.100',
        port: 18789,
        token: 'test-token',
        name: 'Test Gateway',
        version: '2.0.0',
      );

      final json = gateway.toJson();

      expect(json['host'], '192.168.1.100');
      expect(json['port'], 18789);
      expect(json['token'], 'test-token');
      expect(json['name'], 'Test Gateway');
      expect(json['version'], '2.0.0');
    });

    test('Local agent target uses stdio identity', () {
      final gateway = GatewayInfo.local(
        workingDirectory: r'C:\Dev\PocketBot',
      );

      expect(gateway.kind, AgentTransportKind.local);
      expect(gateway.uri, 'agent://local');
      expect(gateway.connectionId, contains('local|'));
      expect(gateway.requiresAuth, isFalse);
    });

    test('SSH connection id is the host, not the working directory', () {
      final first = GatewayInfo.ssh(
        host: '192.168.1.100',
        username: 'user',
        password: 'secret',
        workingDirectory: '/home/user/a',
      );
      final second = first.copyWith(workingDirectory: '/home/user/b');

      expect(first.connectionId, 'ssh|user@192.168.1.100:22');
      expect(first.connectionId, second.connectionId);
      expect(second.displayLabel, contains('/home/user/b'));
      expect(second.requiresAuth, isFalse);
    });

    test('Gateway from JSON', () {
      final json = {
        'host': '10.0.0.1',
        'port': 9000,
        'token': 'abc123',
        'name': 'Remote Gateway',
        'version': '3.0.0',
      };

      final gateway = GatewayInfo.fromJson(json);

      expect(gateway.host, '10.0.0.1');
      expect(gateway.port, 9000);
      expect(gateway.token, 'abc123');
      expect(gateway.name, 'Remote Gateway');
      expect(gateway.version, '3.0.0');
    });
  });

  group('ChatSession Model Tests', () {
    test('Create new session', () {
      final session = ChatSession.create(title: 'Test Session');

      expect(session.id, isNotEmpty);
      expect(session.title, 'Test Session');
      expect(session.messages, isEmpty);
    });

    test('Add message to session', () {
      final session = ChatSession.create();
      final message = Message(
        id: 'msg-1',
        text: 'Hello',
        isUser: true,
        timestamp: DateTime.now(),
      );

      session.addMessage(message);

      expect(session.messages.length, 1);
      expect(session.messages.first, message);
    });

    test('Session to JSON', () {
      final timestamp = DateTime(2024, 1, 1, 12, 0, 0);
      final session = ChatSession(
        id: 'session-123',
        key: 'session-123',
        title: 'Test',
        createdAt: timestamp,
        lastUpdated: timestamp,
        messages: [],
      );

      final json = session.toJson();

      expect(json['id'], 'session-123');
      expect(json['title'], 'Test');
      expect(json['createdAt'], timestamp.toIso8601String());
      expect(json['lastUpdated'], timestamp.toIso8601String());
      expect(json['messages'], isEmpty);
    });

    test('Session from JSON', () {
      final json = {
        'id': 'session-456',
        'title': 'From JSON',
        'createdAt': '2024-01-01T12:00:00.000',
        'lastMessageAt': '2024-01-01T12:30:00.000',
        'messages': [
          {
            'id': 'msg-1',
            'text': 'Test',
            'isUser': true,
            'timestamp': '2024-01-01T12:00:00.000'
          }
        ],
      };

      final session = ChatSession.fromJson(json);

      expect(session.id, 'session-456');
      expect(session.title, 'From JSON');
      expect(session.messages.length, 1);
    });
  });
}
