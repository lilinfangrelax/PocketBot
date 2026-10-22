import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pocket_bot/models/message.dart';
import 'package:pocket_bot/services/connection_manager.dart';

import 'e2e_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('允许代理执行工具并收到回复', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      await resetE2eDatabase();
      requireMockAgentCommand();
      manager = await startMockChat(tester);

      await sendChatMessage(tester, 'e2e-tool');
      await pumpUntil(
        tester,
        () => find.text('运行 E2E 命令').evaluate().length == 2,
        description: '显示工具调用卡片与权限确认',
      );
      expect(find.text('待确认'), findsOneWidget);
      expect(find.text('允许一次'), findsOneWidget);
      expect(find.text('拒绝'), findsOneWidget);

      await tester.tap(find.text('允许一次'));
      await pumpUntil(
        tester,
        () => isShowing('MOCK_TOOL_ALLOWED: e2e-tool', findRichText: true),
        description: '代理继续回复',
      );

      expect(find.text('待确认'), findsNothing);
      expect(find.text('允许一次'), findsNothing);
      expect(find.text('运行 E2E 命令'), findsOneWidget);
      expect(find.text('完成'), findsOneWidget);

      final session = manager.wsService.activeSession!;
      final tool = session.messages.lastWhere(
        (message) => message.kind == MessageKind.tool,
      );
      expect(tool.toolStatus, 'completed');
      expect(tool.text, contains('E2E_TOOL_OK'));
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });

  testWidgets('拒绝工具权限时终止工具并回复', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      await resetE2eDatabase();
      requireMockAgentCommand();
      manager = await startMockChat(tester);

      await sendChatMessage(tester, 'e2e-tool');
      await pumpUntil(
        tester,
        () =>
            isShowing('待确认') &&
            find.text('运行 E2E 命令').evaluate().length == 2,
        description: '显示待确认的工具调用',
      );

      await tester.tap(find.text('拒绝'));
      await pumpUntil(
        tester,
        () => isShowing('MOCK_TOOL_DENIED: e2e-tool', findRichText: true),
        description: '代理在拒绝后回复',
      );

      expect(find.text('待确认'), findsNothing);
      expect(find.text('拒绝'), findsNothing);
      expect(find.text('失败'), findsOneWidget);

      final session = manager.wsService.activeSession!;
      final tool = session.messages.lastWhere(
        (message) => message.kind == MessageKind.tool,
      );
      expect(tool.toolStatus, 'failed');
      expect(tool.text, contains('E2E_TOOL_REJECTED'));
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });
}
