import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pocket_bot/config/gateway_config.dart';
import 'package:pocket_bot/config/session_storage.dart';
import 'package:pocket_bot/services/connection_manager.dart';
import 'package:pocket_bot/widgets/fluent_tab_bar.dart';

import 'e2e_harness.dart';

Future<void> _sendAndWait(
  WidgetTester tester,
  ConnectionManager manager,
  String text,
) async {
  await sendChatMessage(tester, text);
  await pumpUntil(
    tester,
    () => isShowing('MOCK_AGENT_OK: $text', findRichText: true),
    description: '收到「$text」的代理回复',
  );
  await pumpUntil(
    tester,
    () =>
        manager.wsService.activeSession?.messages
            .every((message) => !message.isStreaming) ??
        false,
    description: '结束「$text」的流式状态',
  );
}

Future<void> _returnToSessionList(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('screen-back')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byType(FluentTabBar),
      matching: find.text('消息'),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('重启应用后恢复聊天历史', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      await resetE2eDatabase();
      requireMockAgentCommand();
      manager = await startMockChat(tester);
      await _sendAndWait(tester, manager, 'e2e-history');

      await unmountApp(tester);
      await SessionStorage.flush();
      await manager.disconnect();
      for (final service in List.of(manager.pooledServices)) {
        await service.disconnect();
      }
      manager.dispose();
      manager = null;
      await GatewayConfig.clear();

      manager = await pumpPocketBotApp(tester);
      await pumpUntil(
        tester,
        () => isShowing('e2e-history'),
        description: '消息列表恢复历史会话',
      );

      await tester.tap(find.text('e2e-history').first);
      await pumpUntil(
        tester,
        () => find.byKey(const ValueKey('chat-input')).evaluate().isNotEmpty,
        description: '打开历史会话',
      );
      await pumpUntil(
        tester,
        () => isShowing('MOCK_AGENT_OK: e2e-history', findRichText: true),
        description: '恢复历史代理回复',
      );
      expect(find.text('e2e-history'), findsWidgets);
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });

  testWidgets('多个会话切换时保留各自消息', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      await resetE2eDatabase();
      requireMockAgentCommand();
      manager = await startMockChat(tester);

      await _sendAndWait(tester, manager, 'e2e-alpha');
      final alphaKey = manager.wsService.currentSessionKey!;
      await manager.wsService.renameSession(alphaKey, '会话A');

      manager.wsService.createNewSession();
      await tester.pumpAndSettle();
      await _sendAndWait(tester, manager, 'e2e-beta');
      final betaKey = manager.wsService.currentSessionKey!;
      await manager.wsService.renameSession(betaKey, '会话B');
      await SessionStorage.flush();

      await _returnToSessionList(tester);
      await pumpUntil(
        tester,
        () => isShowing('会话A') && isShowing('会话B'),
        description: '消息列表显示两个会话',
      );

      await tester.tap(find.text('会话A'));
      await pumpUntil(
        tester,
        () => find.byKey(const ValueKey('chat-input')).evaluate().isNotEmpty,
        description: '打开会话A',
      );
      await tester.pumpAndSettle();
      await pumpUntil(
        tester,
        () => isShowing('e2e-alpha'),
        description: '会话A显示自己的消息',
      );
      expect(isShowing('e2e-beta'), isFalse);

      await _returnToSessionList(tester);
      await pumpUntil(
        tester,
        () => isShowing('会话B'),
        description: '返回消息列表',
      );
      await tester.tap(find.text('会话B'));
      await pumpUntil(
        tester,
        () => find.byKey(const ValueKey('chat-input')).evaluate().isNotEmpty,
        description: '打开会话B',
      );
      await tester.pumpAndSettle();
      await pumpUntil(
        tester,
        () => isShowing('e2e-beta'),
        description: '会话B显示自己的消息',
      );
      expect(isShowing('e2e-alpha'), isFalse);
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });

  testWidgets('删除会话后列表与存储同步移除', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      await resetE2eDatabase();
      requireMockAgentCommand();
      manager = await startMockChat(tester);
      await _sendAndWait(tester, manager, 'e2e-delete');
      final sessionKey = manager.wsService.currentSessionKey!;
      await SessionStorage.flush();

      await _returnToSessionList(tester);
      await pumpUntil(
        tester,
        () => isShowing('e2e-delete'),
        description: '消息列表显示待删除会话',
      );

      await tester.drag(
        find.text('e2e-delete'),
        const Offset(-600, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除').last);
      await pumpUntil(
        tester,
        () => !isShowing('e2e-delete'),
        description: '删除后消息列表移除会话',
      );

      final sessions = await SessionStorage.loadAllSessions();
      expect(
        sessions.any((session) => session.key == sessionKey),
        isFalse,
      );
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });
}
