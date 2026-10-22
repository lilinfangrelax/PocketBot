import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pocket_bot/services/connection_manager.dart';
import 'package:pocket_bot/services/websocket_service.dart' as ws;

import 'e2e_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('连接本机代理并收到确定性回复', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      await resetE2eDatabase();
      requireMockAgentCommand();
      await selectMockAgent();
      manager = await pumpPocketBotApp(tester);

      expect(find.text('消息'), findsWidgets);

      await tester.tap(find.text('发现'));
      await tester.pumpAndSettle();
      await pumpUntil(
        tester,
        () => isShowing('启动 Mock Agent'),
        description: '发现页加载 Mock 代理',
      );

      await tester.tap(find.text('启动 Mock Agent'));
      await pumpUntil(
        tester,
        () => manager!.state == ws.ConnectionState.connected,
        description: '连接 Mock 代理',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('已连接到 Mock Agent'), findsWidgets);

      await openChatFromDiscovery(tester);
      await sendChatMessage(tester, 'e2e-ping');
      await pumpUntil(
        tester,
        () => isShowing('MOCK_AGENT_OK: e2e-ping', findRichText: true),
        description: '聊天中显示代理回复',
      );

      final messages = manager.wsService.activeSession?.messages ?? [];
      expect(
        messages.any((message) => message.text.contains('MOCK_AGENT_OK: e2e-ping')),
        isTrue,
      );
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });
}
