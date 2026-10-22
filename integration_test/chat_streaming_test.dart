import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pocket_bot/services/connection_manager.dart';

import 'e2e_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('代理回复分块流式呈现', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      await resetE2eDatabase();
      requireMockAgentCommand();
      manager = await startMockChat(tester);

      await sendChatMessage(tester, 'e2e-stream');
      await pumpUntil(
        tester,
        () => isShowing('MOCK_STREAM:1'),
        description: '显示第一段流式文本',
      );
      expect(
        isShowing('MOCK_STREAM:3'),
        isFalse,
        reason: '完成前不应直接出现最后一段',
      );

      await pumpUntil(
        tester,
        () => isShowing('MOCK_STREAM:3'),
        description: '显示最后一段流式文本',
      );
      await pumpUntil(
        tester,
        () =>
            manager!.wsService.activeSession?.messages
                .every((message) => !message.isStreaming) ??
            false,
        description: '结束流式状态',
      );

      final session = manager.wsService.activeSession!;
      final reply = session.messages.lastWhere(
        (message) => !message.isUser && message.text.contains('MOCK_STREAM'),
      );
      expect(reply.isStreaming, isFalse);
      expect(
        reply.text.trim(),
        'MOCK_STREAM:1 MOCK_STREAM:2 MOCK_STREAM:3',
      );
      expect(isShowing('MOCK_STREAM:2'), isTrue);
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });

  testWidgets('空消息不会发送', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      await resetE2eDatabase();
      requireMockAgentCommand();
      manager = await startMockChat(tester);

      await tester.enterText(
        find.byKey(const ValueKey('chat-input')),
        '   ',
      );
      await tester.pump();

      final sendButton = find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == '发送',
      );
      expect(sendButton, findsOneWidget);
      expect(tester.widget<IconButton>(sendButton).onPressed, isNull);

      final messages =
          manager.wsService.activeSession?.messages ?? const [];
      expect(messages.any((message) => message.isUser), isFalse);
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });

  testWidgets('代理回复中的代码块可复制', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      await resetE2eDatabase();
      requireMockAgentCommand();
      manager = await startMockChat(tester);

      await sendChatMessage(tester, 'e2e-markdown');
      await pumpUntil(
        tester,
        () =>
            isShowing("print('hello');", findRichText: true) &&
            isShowing('复制'),
        description: '显示 Markdown 代码块与复制操作',
      );

      await tester.tap(find.text('复制').first);
      await tester.pump();
      expect(find.text('已复制'), findsWidgets);
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });
}
