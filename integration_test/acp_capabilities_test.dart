import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pocket_bot/services/connection_manager.dart';

import 'e2e_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('展示并切换代理的配置选项', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      await resetE2eDatabase();
      requireMockAgentCommand();
      manager = await startMockChat(tester);

      await sendChatMessage(tester, 'e2e-config');
      await pumpUntil(
        tester,
        () => isShowing('MOCK_AGENT_OK: e2e-config', findRichText: true),
        description: '配置轮回复',
      );

      final ws = manager.wsService;
      expect(ws.configOptions.map((option) => option.id), ['model', 'mode']);
      expect(find.text('Mock Fast'), findsOneWidget);
      expect(find.text('Agent'), findsOneWidget);

      await tester.tap(find.text('Mock Smart'));
      await pumpUntil(
        tester,
        () => ws.configOptions
                .firstWhere((option) => option.id == 'model')
                .currentId ==
            'mock-smart',
        description: '模型选项提交',
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Mock Smart'))
            .selected,
        isTrue,
      );

      await tester.tap(find.widgetWithText(ChoiceChip, 'Plan'));
      await pumpUntil(
        tester,
        () => ws.configOptions
                .firstWhere((option) => option.id == 'mode')
                .currentId ==
            'plan',
        description: '模式选项提交',
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Plan'))
            .selected,
        isTrue,
      );
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });

  testWidgets('展示代理计划并允许展开步骤', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      await resetE2eDatabase();
      requireMockAgentCommand();
      manager = await startMockChat(tester);

      await sendChatMessage(tester, 'e2e-plan');
      await pumpUntil(
        tester,
        () => isShowing('MOCK_PLAN_OK', findRichText: true),
        description: '计划轮回复',
      );

      expect(find.text('计划 1/3'), findsOneWidget);
      expect(find.text('连接 Mock 代理'), findsOneWidget);
      expect(find.text('发送验收消息'), findsNothing);

      await tester.tap(find.text('计划 1/3'));
      await tester.pumpAndSettle();
      expect(find.text('检查现有配置'), findsOneWidget);
      expect(find.text('发送验收消息'), findsOneWidget);
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });

  testWidgets('展示 cursor/update_todos 的待办与计划', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      await resetE2eDatabase();
      requireMockAgentCommand();
      manager = await startMockChat(tester);

      await sendChatMessage(tester, 'e2e-todos');
      await pumpUntil(
        tester,
        () => isShowing('MOCK_TODOS_OK', findRichText: true),
        description: '待办轮回复',
      );

      expect(find.text('✓ 阅读 ACP 代码'), findsOneWidget);
      expect(find.text('○ 补充 E2E 测试'), findsOneWidget);
      expect(find.text('计划 1/2'), findsOneWidget);
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });

  testWidgets('斜杠命令菜单来自 available_commands_update', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      await resetE2eDatabase();
      requireMockAgentCommand();
      manager = await startMockChat(tester);

      await sendChatMessage(tester, 'e2e-commands');
      await pumpUntil(
        tester,
        () => manager!.wsService.availableCommands.isNotEmpty,
        description: '代理下发斜杠命令',
      );
      await pumpUntil(
        tester,
        () => isShowing('MOCK_AGENT_OK: e2e-commands', findRichText: true),
        description: '命令轮回复',
      );

      await tester.tap(find.byKey(const ValueKey('chat-input')));
      await tester.enterText(find.byKey(const ValueKey('chat-input')), '/');
      await tester.pumpAndSettle();
      expect(find.text('/reset'), findsOneWidget);
      expect(find.text('/plan'), findsOneWidget);

      await tester.tap(find.text('/reset'));
      await tester.pump();
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('chat-input')),
      );
      expect(field.controller?.text, '/reset ');
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });

  testWidgets('代理通过 fs 读写会话目录中的文件', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      await resetE2eDatabase();
      requireMockAgentCommand();
      manager = await startMockChat(tester);

      await sendChatMessage(tester, 'e2e-fs');
      await pumpUntil(
        tester,
        () => isShowing('MOCK_FS: E2E_FS_OK', findRichText: true),
        description: '文件读写往返',
      );
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });
}
