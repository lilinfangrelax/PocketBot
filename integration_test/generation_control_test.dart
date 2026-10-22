import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pocket_bot/services/connection_manager.dart';
import 'package:pocket_bot/services/websocket_service.dart' as ws;

import 'e2e_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('停止正在生成的回复', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      await resetE2eDatabase();
      requireMockAgentCommand();
      manager = await startMockChat(tester);

      await sendChatMessage(tester, 'e2e-slow');
      await pumpUntil(
        tester,
        () => isShowing('MOCK_SLOW:1'),
        description: '显示慢速回复的第一段',
      );
      expect(find.byTooltip('停止'), findsOneWidget);

      await tester.tap(find.byTooltip('停止'));
      await tester.pump();
      await pumpUntil(
        tester,
        () => find.byTooltip('停止').evaluate().isEmpty,
        description: '停止生成按钮消失',
      );

      await Future<void>.delayed(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(isShowing('MOCK_SLOW:2'), isFalse);
      expect(isShowing('MOCK_SLOW:1'), isTrue);
      expect(
        manager.wsService.activeSession?.messages
                .every((message) => !message.isStreaming) ??
            true,
        isTrue,
      );
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });

  testWidgets('断线发送失败后保留输入并重连重发', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      await resetE2eDatabase();
      requireMockAgentCommand();
      manager = await startMockChat(tester);

      await manager.disconnect();
      await tester.pumpAndSettle();
      expect(isShowing('连接已断开'), isTrue);

      await tester.enterText(
        find.byKey(const ValueKey('chat-input')),
        'e2e-retry',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pump();
      await pumpUntil(
        tester,
        () => isShowing('发送失败'),
        description: '显示发送失败提示',
      );

      final input = tester.widget<TextField>(
        find.byKey(const ValueKey('chat-input')),
      );
      expect(input.controller?.text, 'e2e-retry');

      // The transient notice auto-dismisses after 3s; let it clear so it
      // cannot cover the input bar when we send again.
      await Future<void>.delayed(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      await tester.tap(find.text('重连'));
      await pumpUntil(
        tester,
        () => manager!.state == ws.ConnectionState.connected,
        description: '重连 Mock 代理',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('发送'));
      await pumpUntil(
        tester,
        () => isShowing('MOCK_AGENT_OK: e2e-retry', findRichText: true),
        description: '重连后收到代理回复',
      );
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });
}
