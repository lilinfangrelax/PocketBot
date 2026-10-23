import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pocket_bot/config/gateway_config.dart';
import 'package:pocket_bot/models/ai_contact_config.dart';
import 'package:pocket_bot/services/ai_contact_service.dart';
import 'package:pocket_bot/services/connection_manager.dart';
import 'package:pocket_bot/services/contact_service.dart';
import 'package:pocket_bot/widgets/fluent_tab_bar.dart';

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

  testWidgets('从通讯录打开新建联系人', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      await resetE2eDatabase();
      manager = await pumpPocketBotApp(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(FluentTabBar),
          matching: find.text('通讯录'),
        ),
      );
      await tester.pump();
      await pumpUntil(
        tester,
        () => find.bySemanticsLabel('添加联系人').evaluate().isNotEmpty,
        description: '通讯录显示添加联系人',
      );
      await tester.tap(find.bySemanticsLabel('添加联系人'));
      await tester.pump();
      await pumpUntil(
        tester,
        () => isShowing('新建联系人'),
        description: '打开新建联系人',
      );
      expect(find.text('名称 *'), findsOneWidget);
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });

  testWidgets('AI 助手默认关闭', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      await resetE2eDatabase();
      manager = await pumpPocketBotApp(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(FluentTabBar),
          matching: find.text('通讯录'),
        ),
      );
      await tester.pump();
      await pumpUntil(
        tester,
        () => find.bySemanticsLabel('添加联系人').evaluate().isNotEmpty,
        description: '通讯录显示添加联系人',
      );
      await tester.tap(find.bySemanticsLabel('添加联系人'));
      await tester.pump();
      await pumpUntil(
        tester,
        () => isShowing('AI 助手'),
        description: '新建联系人显示 AI 助手',
      );
      expect(find.text('群聊中自动回复'), findsNothing);

      await tester.tap(find.text('AI 助手'));
      await tester.pump();
      await pumpUntil(
        tester,
        () => isShowing('群聊中自动回复'),
        description: '打开 AI 助手后显示自动回复',
      );
      expect(find.textContaining('还没有保存的连接'), findsOneWidget);
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });

  testWidgets('按名称搜索联系人', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      await resetE2eDatabase();
      final contacts = ContactService();
      await contacts.createContact(name: '甲乙', atName: 'jia');
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await contacts.createContact(name: '丙丁', atName: 'bing');
      manager = await pumpPocketBotApp(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(FluentTabBar),
          matching: find.text('通讯录'),
        ),
      );
      await tester.pump();
      await pumpUntil(
        tester,
        () => isShowing('甲乙') && isShowing('丙丁'),
        description: '通讯录显示两个联系人',
      );
      await tester.enterText(find.byType(EditableText).first, '甲');
      await tester.pump();
      await pumpUntil(
        tester,
        () => isShowing('甲乙') && !isShowing('丙丁'),
        description: '搜索只保留甲乙',
      );
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });

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
