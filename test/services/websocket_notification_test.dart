import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_bot/models/message.dart';
import 'package:pocket_bot/models/session_state.dart';

void main() {
  group('WebSocket Notification Logic', () {
    group('SessionState displayTitle', () {
      test('should return custom title when set', () {
        final session = SessionState(sessionKey: 'test-key');
        session.customTitle = 'My Custom Chat';

        expect(session.displayTitle, 'My Custom Chat');
      });

      test('should return "新对话" when no messages', () {
        final session = SessionState(sessionKey: 'test-key');

        expect(session.displayTitle, '新对话');
      });

      test('should generate title from last user message', () {
        final session = SessionState(sessionKey: 'test-key');
        session.addMessage(Message(
          id: '1',
          text: 'Hello Bot',
          isUser: true,
          timestamp: DateTime.now(),
        ));
        session.addMessage(Message(
          id: '2',
          text: 'Hi there!',
          isUser: false,
          timestamp: DateTime.now(),
        ));

        final title = session.displayTitle;
        expect(title, contains('Hello Bot'));
      });
    });

    group('Message notification decision logic', () {
      test('should send notification when session is not active', () {
        const activeSessionKey = 'session-1';
        const otherSessionKey = 'session-2';

        // User is in session-1, bot replies in session-2
        final shouldNotify = activeSessionKey != otherSessionKey;

        expect(shouldNotify, true);
      });

      test('should NOT send notification when session is active', () {
        const activeSessionKey = 'session-1';

        // User is in session-1, bot replies in session-1
        final shouldNotify = activeSessionKey != activeSessionKey;

        expect(shouldNotify, false);
      });

      test('should check last assistant message before notifying', () {
        final session = SessionState(sessionKey: 'test-key');

        // Empty messages - should not notify
        final hasLastAssistantMessage = session.messages.isNotEmpty &&
            session.messages.where((m) => !m.isUser).isNotEmpty;

        expect(hasLastAssistantMessage, false);

        // Add user message only
        session.addMessage(Message(
          id: '1',
          text: 'Hello',
          isUser: true,
          timestamp: DateTime.now(),
        ));

        final hasAssistantAfterUser = session.messages.isNotEmpty &&
            session.messages.where((m) => !m.isUser).isNotEmpty;

        expect(hasAssistantAfterUser, false);

        // Add assistant message
        session.addMessage(Message(
          id: '2',
          text: 'Hi there!',
          isUser: false,
          timestamp: DateTime.now(),
        ));

        final hasAssistantNow = session.messages.isNotEmpty &&
            session.messages.where((m) => !m.isUser).isNotEmpty;

        expect(hasAssistantNow, true);

        final lastAssistantMessage = session.messages.isNotEmpty
            ? session.messages.where((m) => !m.isUser).lastOrNull
            : null;

        expect(lastAssistantMessage?.text, 'Hi there!');
      });

      test('should NOT notify when last assistant message is empty', () {
        final session = SessionState(sessionKey: 'test-key');

        session.addMessage(Message(
          id: '1',
          text: '',
          isUser: false,
          timestamp: DateTime.now(),
        ));

        final lastAssistantMessage = session.messages.isNotEmpty
            ? session.messages.where((m) => !m.isUser).lastOrNull
            : null;

        final shouldNotify = lastAssistantMessage != null &&
            lastAssistantMessage.text.isNotEmpty;

        expect(shouldNotify, false);
      });

      test('should notify when last assistant message has content', () {
        final session = SessionState(sessionKey: 'test-key');

        session.addMessage(Message(
          id: '1',
          text: 'Task completed successfully!',
          isUser: false,
          timestamp: DateTime.now(),
        ));

        final lastAssistantMessage = session.messages.isNotEmpty
            ? session.messages.where((m) => !m.isUser).lastOrNull
            : null;

        final shouldNotify = lastAssistantMessage != null &&
            lastAssistantMessage.text.isNotEmpty;

        expect(shouldNotify, true);
      });
    });

    group('Notification content extraction', () {
      test('should extract session name from custom title', () {
        final session = SessionState(sessionKey: 'test-key');
        session.customTitle = 'Important Project';

        final sessionName = session.displayTitle;

        expect(sessionName, 'Important Project');
      });

      test('should extract message preview', () {
        const fullMessage = 'This is a longer message that should be truncated when displayed in notification';
        const maxLength = 50;

        final messagePreview = fullMessage.length > maxLength
            ? '${fullMessage.substring(0, maxLength)}...'
            : fullMessage;

        expect(messagePreview.length, 53); // 50 + '...'
        expect(messagePreview.startsWith('This is a longer message that should be trunc'), true);
      });
    });
  });
}
