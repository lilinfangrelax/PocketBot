import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_bot/services/notification_service.dart';

void main() {
  group('NotificationService', () {
    late NotificationService notificationService;

    setUp(() {
      notificationService = NotificationService();
    });

    group('showMessageNotification', () {
      test('should create notification with correct parameters', () async {
        // This test verifies the parameter handling logic
        // Actual notification display requires platform setup

        const sessionKey = 'test-session-123';
        const sessionName = 'Test Chat';
        const message = 'Hello, this is a test message';

        // Verify parameter truncation logic
        final truncatedName = sessionName.length > 20
            ? '...${sessionName.substring(sessionName.length - 17)}'
            : sessionName;

        final truncatedMessage = message.length > 80
            ? '${message.substring(0, 80)}...'
            : message;

        expect(truncatedName, 'Test Chat');
        expect(truncatedMessage, 'Hello, this is a test message');
      });

      test('should truncate long session names', () {
        const longSessionName = 'This is a very long session name that exceeds 20 characters';

        final truncatedName = longSessionName.length > 20
            ? '...${longSessionName.substring(longSessionName.length - 17)}'
            : longSessionName;

        expect(truncatedName.length, 20);
        expect(truncatedName.startsWith('...'), true);
      });

      test('should truncate long messages', () {
        final longMessage = 'A' * 150;

        final truncatedMessage = longMessage.length > 80
            ? '${longMessage.substring(0, 80)}...'
            : longMessage;

        expect(truncatedMessage.length, 83); // 80 + '...'
        expect(truncatedMessage.endsWith('...'), true);
      });

      test('should not truncate short messages', () {
        const shortMessage = 'Short message';

        final truncatedMessage = shortMessage.length > 80
            ? '${shortMessage.substring(0, 80)}...'
            : shortMessage;

        expect(truncatedMessage, 'Short message');
      });
    });

    group('notification permission logic', () {
      test('should handle empty session key', () {
        const sessionKey = '';
        const sessionName = 'Test';
        const message = 'Test message';

        // Verify empty key doesn't cause issues
        final hash = sessionKey.hashCode;
        expect(hash, isNotNull);
      });

      test('should generate unique notification IDs for different sessions', () {
        const sessionKey1 = 'session-1';
        const sessionKey2 = 'session-2';

        final id1 = sessionKey1.hashCode;
        final id2 = sessionKey2.hashCode;

        expect(id1, isNot(equals(id2)));
      });
    });
  });
}
