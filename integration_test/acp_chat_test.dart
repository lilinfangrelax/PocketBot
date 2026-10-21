import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pocket_bot/config/session_storage.dart';
import 'package:pocket_bot/main.dart';
import 'package:pocket_bot/services/connection_manager.dart';
import 'package:pocket_bot/services/contact_agent_linker.dart';
import 'package:pocket_bot/services/group_chat_service.dart';
import 'package:pocket_bot/services/websocket_service.dart' as ws;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'e2e_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('本机 ACP 连接与聊天', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      resetE2eDatabase();
      requireMockAgentCommand();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('acp_agent_id', 'pocketbot-mock');
      await prefs.setString('acp_agent_label', 'Mock Agent');

      manager = ConnectionManager();
      final connection = manager;
      GroupChatService().linker = ContactAgentLinker(connection);

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ConnectionManager>.value(value: connection),
          ChangeNotifierProvider(create: (_) => ws.WebSocketService()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => UserConfigProvider()),
        ],
        child: const PocketBotApp(),
      ));
      await tester.pumpAndSettle();

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
        () => connection.state == ws.ConnectionState.connected,
        description: '连接 Mock 代理',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('已连接到 Mock Agent'), findsWidgets);

      await tester.tap(find.text('开始聊天'));
      await pumpUntil(
        tester,
        () => find.byKey(const ValueKey('chat-input')).evaluate().isNotEmpty,
        description: '打开聊天页',
      );

      await tester.enterText(
        find.byKey(const ValueKey('chat-input')),
        'e2e-ping',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await pumpUntil(
        tester,
        () => isShowing('MOCK_AGENT_OK: e2e-ping', findRichText: true),
        description: '聊天中显示代理回复',
      );

      final messages = connection.wsService.activeSession?.messages ?? [];
      expect(
        messages
            .any((message) => message.text.contains('MOCK_AGENT_OK: e2e-ping')),
        isTrue,
      );
    } finally {
      await unmountApp(tester);
      if (manager != null) {
        await manager.disconnect();
        for (final service in manager.pooledServices) {
          await service.disconnect();
        }
        manager.dispose();
      }
      await SessionStorage.flush();
      await snapshot.restore();
    }
  });
}
