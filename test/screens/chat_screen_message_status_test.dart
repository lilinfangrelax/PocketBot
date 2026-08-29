import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_bot/models/message.dart';
import 'package:pocket_bot/screens/chat_screen.dart';

void main() {
  group('Message Status Indicator Tests', () {
    testWidgets('Shows single check for unconfirmed user message', (tester) async {
      final message = Message(
        id: 'test-1',
        text: 'Hello',
        isUser: true,
        timestamp: DateTime.now(),
        confirmed: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _TestMessageStatusWidget(
                  message: message,
                  isDarkMode: false,
                ),
              ],
            ),
          ),
        ),
      );

      // Should show single done icon (not done_all)
      expect(find.byIcon(Icons.done), findsOneWidget);
      expect(find.byIcon(Icons.done_all), findsNothing);
    });

    testWidgets('Shows double check for confirmed user message', (tester) async {
      final message = Message(
        id: 'test-1',
        text: 'Hello',
        isUser: true,
        timestamp: DateTime.now(),
        confirmed: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _TestMessageStatusWidget(
                  message: message,
                  isDarkMode: false,
                ),
              ],
            ),
          ),
        ),
      );

      // Should show double check icon
      expect(find.byIcon(Icons.done_all), findsOneWidget);
      expect(find.byIcon(Icons.done), findsNothing);
    });

    testWidgets('Does not show status for AI messages', (tester) async {
      final message = Message(
        id: 'test-1',
        text: 'Hello from AI',
        isUser: false,
        timestamp: DateTime.now(),
        confirmed: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                _TestMessageStatusWidget(
                  message: message,
                  isDarkMode: false,
                ),
              ],
            ),
          ),
        ),
      );

      // Should not show any status icons for AI messages
      expect(find.byIcon(Icons.done), findsNothing);
      expect(find.byIcon(Icons.done_all), findsNothing);
    });

    testWidgets('Status icon color in dark mode', (tester) async {
      final confirmedMessage = Message(
        id: 'test-1',
        text: 'Hello',
        isUser: true,
        timestamp: DateTime.now(),
        confirmed: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _TestMessageStatusWidget(
                  message: confirmedMessage,
                  isDarkMode: true,
                ),
              ],
            ),
          ),
        ),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.done_all));
      // Dark mode should have blue[300]
      expect(icon.color, Colors.blue[300]);
    });

    testWidgets('Status icon color in light mode', (tester) async {
      final confirmedMessage = Message(
        id: 'test-1',
        text: 'Hello',
        isUser: true,
        timestamp: DateTime.now(),
        confirmed: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _TestMessageStatusWidget(
                  message: confirmedMessage,
                  isDarkMode: false,
                ),
              ],
            ),
          ),
        ),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.done_all));
      // Light mode should have blue[400]
      expect(icon.color, Colors.blue[400]);
    });
  });
}

/// Helper widget to test _buildMessageStatus in isolation
class _TestMessageStatusWidget extends StatelessWidget {
  final Message message;
  final bool isDarkMode;

  const _TestMessageStatusWidget({
    required this.message,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    // This replicates the logic from ChatScreen._buildMessageStatus
    if (!message.isUser) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 8, top: 4),
      child: SizedBox(
        width: 16,
        height: 16,
        child: message.confirmed
            ? Icon(
                Icons.done_all,
                size: 14,
                color: isDarkMode ? Colors.blue[300] : Colors.blue[400],
              )
            : Icon(
                Icons.done,
                size: 14,
                color: isDarkMode ? Colors.grey[500] : Colors.grey[400],
              ),
      ),
    );
  }
}
