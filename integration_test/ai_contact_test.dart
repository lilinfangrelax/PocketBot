import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pocket_bot/config/gateway_config.dart';
import 'package:pocket_bot/config/session_storage.dart';
import 'package:pocket_bot/main.dart';
import 'package:pocket_bot/services/ai_contact_service.dart';
import 'package:pocket_bot/services/connection_manager.dart';
import 'package:pocket_bot/services/contact_agent_linker.dart';
import 'package:pocket_bot/services/group_chat_service.dart';
import 'package:pocket_bot/services/websocket_service.dart' as ws;
import 'package:provider/provider.dart';

import 'e2e_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('通讯录与 AI 联系人', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      resetE2eDatabase();
      requireMockAgentCommand();

      final gateway = mockGateway();
      await GatewayConfig.addGateway(gateway);
      await GatewayConfig.saveLastConnected(gateway.connectionId);

      final config = await AIContactService().createAIContact(
        name: 'E2E助手',
        atName: 'e2e_helper',
        agentId: 'pocketbot-mock',
        agentLabel: 'Mock Agent',
        gatewayId: gateway.connectionId,
        workingDirectory: gateway.workingDirectory,
      );

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

      await tester.tap(find.text('通讯录'));
      await tester.pumpAndSettle();
      await pumpUntil(
        tester,
        () => isShowing('E2E助手'),
        description: '通讯录中显示联系人',
      );
      expect(find.text('E2E助手'), findsWidgets);
      expect(find.text('@e2e_helper'), findsWidgets);

      await tester.tap(find.text('E2E助手').first);
      await tester.pumpAndSettle();
      await pumpUntil(
        tester,
        () => isShowing('Mock Agent ·'),
        description: '联系人详情解析出代理连接',
      );

      // ElevatedButton.icon builds _ElevatedButtonWithIcon, which find.byType
      // misses because it compares exact runtimeType.
      final sendButton = find.ancestor(
        of: find.text('发消息'),
        matching: find.byWidgetPredicate((widget) => widget is ElevatedButton),
      );
      await pumpUntil(
        tester,
        () {
          final elements = sendButton.evaluate();
          if (elements.isEmpty) return false;
          final widget = elements.first.widget;
          return widget is ElevatedButton && widget.onPressed != null;
        },
        description: '发消息按钮可用',
      );
      await pumpUntil(
        tester,
        () =>
            connection.wsService.isConnected ||
            connection.pooledServices.any((service) => service.isConnected),
        description: '联系人代理已连接',
      );
      expect(config.contactId, isNotEmpty);

      await tester.tap(sendButton);
      await pumpUntil(
        tester,
        () => find.byKey(const ValueKey('chat-input')).evaluate().isNotEmpty,
        description: '打开联系人聊天页',
      );

      await tester.enterText(
        find.byKey(const ValueKey('chat-input')),
        'e2e-contact',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await pumpUntil(
        tester,
        () => isShowing('MOCK_AGENT_OK: e2e-contact', findRichText: true),
        description: '聊天中显示代理回复',
      );

      final services = [connection.wsService, ...connection.pooledServices];
      final messages = services
          .expand((service) => service.activeSession?.messages ?? const []);
      expect(
        messages.any((message) => message.text.contains('MOCK_AGENT_OK')),
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
