import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pocket_bot/config/gateway_config.dart';
import 'package:pocket_bot/models/ai_contact_config.dart';
import 'package:pocket_bot/services/ai_contact_service.dart';
import 'package:pocket_bot/services/connection_manager.dart';

import 'e2e_harness.dart';

Future<AIContactConfig> _seedContact() async {
  final gateway = mockGateway();
  await GatewayConfig.addGateway(gateway);
  await GatewayConfig.saveLastConnected(gateway.connectionId);
  return AIContactService().createAIContact(
    name: 'E2E助手',
    atName: 'e2e_helper',
    agentId: 'pocketbot-mock',
    agentLabel: 'Mock Agent',
    gatewayId: gateway.connectionId,
    workingDirectory: gateway.workingDirectory,
  );
}

Future<void> _openContacts(WidgetTester tester) async {
  await tester.tap(find.text('通讯录'));
  await tester.pumpAndSettle();
  await pumpUntil(
    tester,
    () => isShowing('E2E助手'),
    description: '通讯录中显示联系人',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('创建 AI 联系人并绑定 Mock 代理', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      await resetE2eDatabase();
      requireMockAgentCommand();
      await _seedContact();
      manager = await pumpPocketBotApp(tester);

      await _openContacts(tester);
      expect(find.text('E2E助手'), findsWidgets);
      expect(find.text('@e2e_helper'), findsWidgets);

      await tester.tap(find.text('E2E助手').first);
      await tester.pumpAndSettle();
      await pumpUntil(
        tester,
        () => isShowing('Mock Agent ·'),
        description: '联系人详情解析出代理连接',
      );
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });

  testWidgets('从通讯录打开 AI 联系人聊天', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      await resetE2eDatabase();
      requireMockAgentCommand();
      await _seedContact();
      manager = await pumpPocketBotApp(tester);

      await _openContacts(tester);
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
            manager!.wsService.isConnected ||
            manager.pooledServices.any((service) => service.isConnected),
        description: '联系人代理已连接',
      );

      await tester.tap(sendButton);
      await pumpUntil(
        tester,
        () => find.byKey(const ValueKey('chat-input')).evaluate().isNotEmpty,
        description: '打开联系人聊天页',
      );

      await sendChatMessage(tester, 'e2e-contact');
      await pumpUntil(
        tester,
        () => isShowing('MOCK_AGENT_OK: e2e-contact', findRichText: true),
        description: '聊天中显示代理回复',
      );

      final services = [manager.wsService, ...manager.pooledServices];
      final messages = services
          .expand((service) => service.activeSession?.messages ?? const []);
      expect(
        messages.any((message) => message.text.contains('MOCK_AGENT_OK')),
        isTrue,
      );
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });
}
