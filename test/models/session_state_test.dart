import 'package:pocket_bot/models/message.dart';
import 'package:pocket_bot/models/session_state.dart';
import 'package:test/test.dart';

void main() {
  group('SessionState Tests', () {
    late SessionState session;

    setUp(() {
      session = SessionState(
        sessionKey: 'test-session-1',
        agentId: 'main',
      );
    });

    test('Initial state is inactive with zero unread', () {
      expect(session.isActive, false);
      expect(session.unreadCount, 0);
      expect(session.messages, isEmpty);
    });

    test('Activate session sets isActive to true', () {
      session.activate();
      expect(session.isActive, true);
      expect(session.unreadCount, 0);
    });

    test('Deactivate session sets isActive to false', () {
      session.activate();
      session.deactivate();
      expect(session.isActive, false);
    });

    test('Mark as read clears unread count', () {
      session.unreadCount = 5;
      session.markAsRead();
      expect(session.unreadCount, 0);
    });

    group('Message Handling', () {
      test('Add user message does not increase unread count', () {
        final userMessage = Message(
          id: 'msg-1',
          text: 'Hello',
          isUser: true,
          timestamp: DateTime.now(),
        );

        session.addMessage(userMessage);

        expect(session.messages.length, 1);
        expect(session.unreadCount, 0);
      });

      test('Add AI message to inactive session increases unread count', () {
        final aiMessage = Message(
          id: 'ai-1',
          text: 'Hello, I am AI',
          isUser: false,
          timestamp: DateTime.now(),
        );

        session.addMessage(aiMessage);

        expect(session.messages.length, 1);
        expect(session.unreadCount, 1);
      });

      test('Add AI message to active session does not increase unread count', () {
        session.activate();

        final aiMessage = Message(
          id: 'ai-1',
          text: 'Hello, I am AI',
          isUser: false,
          timestamp: DateTime.now(),
        );

        session.addMessage(aiMessage);

        expect(session.messages.length, 1);
        expect(session.unreadCount, 0);
      });

      test('Duplicate messages are ignored', () {
        final message = Message(
          id: 'msg-1',
          text: 'Hello',
          isUser: true,
          timestamp: DateTime.now(),
        );

        session.addMessage(message);
        session.addMessage(message);

        expect(session.messages.length, 1);
      });

      test('Messages are ordered by insertion', () {
        final now = DateTime.now();
        final msg1 = Message(id: '1', text: 'First', isUser: true, timestamp: now);
        final msg2 = Message(id: '2', text: 'Second', isUser: false, timestamp: now.add(const Duration(seconds: 1)));
        final msg3 = Message(id: '3', text: 'Third', isUser: true, timestamp: now.add(const Duration(seconds: 2)));

        session.addMessage(msg1);
        session.addMessage(msg2);
        session.addMessage(msg3);

        expect(session.messages[0].id, '1');
        expect(session.messages[1].id, '2');
        expect(session.messages[2].id, '3');
      });
    });

    group('Update Last Message', () {
      test('Update last AI message replaces the message', () {
        final originalMsg = Message(
          id: 'ai-1',
          text: 'Original',
          isUser: false,
          timestamp: DateTime.now(),
        );
        final updatedMsg = Message(
          id: 'ai-1',
          text: 'Updated text',
          isUser: false,
          timestamp: DateTime.now(),
        );

        session.addMessage(originalMsg);
        session.updateLastMessage(updatedMsg);

        expect(session.messages.length, 1);
        expect(session.messages[0].text, 'Updated text');
      });

      test('Update last message does not affect user messages', () {
        final userMsg = Message(id: 'u1', text: 'User', isUser: true, timestamp: DateTime.now());
        final aiMsg = Message(id: 'ai1', text: 'AI', isUser: false, timestamp: DateTime.now());
        final updatedAiMsg = Message(id: 'ai1', text: 'AI Updated', isUser: false, timestamp: DateTime.now());

        session.addMessage(userMsg);
        session.addMessage(aiMsg);
        session.updateLastMessage(updatedAiMsg);

        expect(session.messages.length, 2);
        expect(session.messages[0].text, 'User');
        expect(session.messages[1].text, 'AI Updated');
      });
    });

    group('Clear Messages', () {
      test('Clear messages resets all state', () {
        final msg = Message(id: '1', text: 'Test', isUser: true, timestamp: DateTime.now());
        session.addMessage(msg);
        session.unreadCount = 5;

        session.clearMessages();

        expect(session.messages, isEmpty);
        expect(session.unreadCount, 0);
        expect(session.currentRunId, isNull);
      });
    });

    group('To ChatSession Conversion', () {
      test('Converts to ChatSession correctly', () {
        final userMsg = Message(id: '1', text: 'User msg', isUser: true, timestamp: DateTime.now());
        final aiMsg = Message(id: '2', text: 'AI msg', isUser: false, timestamp: DateTime.now());

        session.addMessage(userMsg);
        session.addMessage(aiMsg);
        session.unreadCount = 3;

        final chatSession = session.toChatSession();

        expect(chatSession.key, 'test-session-1');
        expect(chatSession.messages.length, 2);
        expect(chatSession.unreadCount, 3);
        expect(chatSession.agentId, 'main');
      });
    });

    group('From ChatSession Factory', () {
      test('Creates SessionState from ChatSession', () {
        final chatSession = ChatSession(
          id: 'session-1',
          key: 'session-1',
          title: 'Test Session',
          createdAt: DateTime.now(),
          lastUpdated: DateTime.now(),
          messages: [],
          unreadCount: 5,
          agentId: 'custom-agent',
        );

        final state = SessionState.fromChatSession(chatSession);

        expect(state.sessionKey, 'session-1');
        expect(state.agentId, 'custom-agent');
        expect(state.unreadCount, 5);
      });
    });
  });

  group('Multiple Sessions Tests', () {
    late SessionState sessionA;
    late SessionState sessionB;

    setUp(() {
      sessionA = SessionState(sessionKey: 'session-A', agentId: 'main');
      sessionB = SessionState(sessionKey: 'session-B', agentId: 'main');
    });

    test('Sessions are independent', () {
      final msgA = Message(id: 'a1', text: 'A msg', isUser: false, timestamp: DateTime.now());
      final msgB = Message(id: 'b1', text: 'B msg', isUser: true, timestamp: DateTime.now());

      sessionA.addMessage(msgA);
      sessionB.addMessage(msgB);

      expect(sessionA.messages.length, 1);
      expect(sessionB.messages.length, 1);
      expect(sessionA.messages[0].text, 'A msg');
      expect(sessionB.messages[0].text, 'B msg');
    });

    test('Activate one session does not affect another', () {
      sessionA.activate();
      final aiMsg = Message(id: 'b1', text: 'AI reply', isUser: false, timestamp: DateTime.now());

      sessionB.addMessage(aiMsg);

      expect(sessionA.isActive, true);
      expect(sessionB.isActive, false);
      expect(sessionA.unreadCount, 0);
      expect(sessionB.unreadCount, 1);
    });

    test('Switching sessions: deactivate A, activate B', () {
      sessionA.activate();
      sessionA.deactivate();
      sessionB.activate();

      expect(sessionA.isActive, false);
      expect(sessionB.isActive, true);
    });
  });

  group('Message Read Status Tests', () {
    late SessionState session;

    setUp(() {
      session = SessionState(sessionKey: 'test-session', agentId: 'main');
    });

    test('Mark messages as read sets readAt for unread AI messages', () {
      final now = DateTime.now();
      final userMsg = Message(id: 'u1', text: 'User', isUser: true, timestamp: now);
      final aiMsg1 = Message(id: 'a1', text: 'AI 1', isUser: false, timestamp: now.add(const Duration(seconds: 1)));
      final aiMsg2 = Message(id: 'a2', text: 'AI 2', isUser: false, timestamp: now.add(const Duration(seconds: 2)));

      session.addMessage(userMsg);
      session.addMessage(aiMsg1);
      session.addMessage(aiMsg2);

      // Mark as read
      final nowRead = DateTime.now();
      session.messages = session.messages.map((m) {
        if (!m.isUser && m.readAt == null) {
          return m.copyWith(readAt: nowRead);
        }
        return m;
      }).toList();

      expect(session.messages.where((m) => !m.isUser && m.readAt != null).length, 2);
      expect(session.messages.where((m) => m.isUser && m.readAt == null).length, 1);
    });
  });

  group('Message Confirmed Status Tests', () {
    late SessionState session;

    setUp(() {
      session = SessionState(sessionKey: 'test-session', agentId: 'main');
    });

    test('User message confirmed defaults to false', () {
      final userMsg = Message(
        id: 'u1',
        text: 'Hello',
        isUser: true,
        timestamp: DateTime.now(),
      );

      session.addMessage(userMsg);

      expect(session.messages.first.confirmed, false);
    });

    test('Update message can set confirmed to true', () {
      final userMsg = Message(
        id: 'u1',
        text: 'Hello',
        isUser: true,
        timestamp: DateTime.now(),
        confirmed: false,
      );

      session.addMessage(userMsg);

      // Simulate Gateway confirmation
      final confirmedMsg = userMsg.copyWith(confirmed: true);
      session.updateMessage(confirmedMsg);

      expect(session.messages.first.confirmed, true);
    });

    test('Update message by ID updates correct message', () {
      final msg1 = Message(id: 'm1', text: 'Msg 1', isUser: true, timestamp: DateTime.now());
      final msg2 = Message(id: 'm2', text: 'Msg 2', isUser: true, timestamp: DateTime.now());
      final msg3 = Message(id: 'm3', text: 'Msg 3', isUser: true, timestamp: DateTime.now());

      session.addMessage(msg1);
      session.addMessage(msg2);
      session.addMessage(msg3);

      // Confirm only message 2
      final confirmedMsg2 = msg2.copyWith(confirmed: true);
      session.updateMessage(confirmedMsg2);

      expect(session.messages[0].confirmed, false);
      expect(session.messages[1].confirmed, true);
      expect(session.messages[2].confirmed, false);
    });

    test('AI message confirmed field is not affected by update', () {
      final aiMsg = Message(
        id: 'ai1',
        text: 'AI response',
        isUser: false,
        timestamp: DateTime.now(),
        confirmed: false,
      );

      session.addMessage(aiMsg);

      // Try to set confirmed on AI message (should still work)
      final updatedAiMsg = aiMsg.copyWith(confirmed: true);
      session.updateMessage(updatedAiMsg);

      expect(session.messages.first.confirmed, true);
    });

    test('Update non-existent message does nothing', () {
      final msg = Message(id: 'm1', text: 'Test', isUser: true, timestamp: DateTime.now());
      session.addMessage(msg);

      final nonExistent = Message(id: 'non-existent', text: 'Not added', isUser: true, timestamp: DateTime.now());
      session.updateMessage(nonExistent);

      expect(session.messages.length, 1);
      expect(session.messages.first.id, 'm1');
    });
  });
}
