import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pocket_bot/config/gateway_config.dart';
import 'package:pocket_bot/models/ai_contact_config.dart';
import 'package:pocket_bot/models/group_chat.dart';
import 'package:pocket_bot/services/ai_contact_service.dart';
import 'package:pocket_bot/services/connection_manager.dart';
import 'package:pocket_bot/services/group_chat_service.dart';

import 'e2e_harness.dart';

Future<AIContactConfig> _createContact({
  required String name,
  required String atName,
  required String gatewayId,
  required String workingDirectory,
}) {
  return AIContactService().createAIContact(
    name: name,
    atName: atName,
    agentId: 'pocketbot-mock',
    agentLabel: 'Mock Agent',
    gatewayId: gatewayId,
    workingDirectory: workingDirectory,
  );
}

Future<(AIContactConfig, GroupChat)> _seedGroup() async {
  final gateway = mockGateway();
  await GatewayConfig.addGateway(gateway);
  await GatewayConfig.saveLastConnected(gateway.connectionId);
  final config = await _createContact(
    name: 'E2E助手',
    atName: 'e2e_helper',
    gatewayId: gateway.connectionId,
    workingDirectory: gateway.workingDirectory,
  );
  final group =
      await GroupChatService().createGroup('E2E群', [config.contactId]);
  return (config, group);
}

Future<(AIContactConfig, AIContactConfig, GroupChat)> _seedMultiGroup({
  bool secondBroken = false,
}) async {
  final gateway = mockGateway();
  await GatewayConfig.addGateway(gateway);
  await GatewayConfig.saveLastConnected(gateway.connectionId);
  final first = await _createContact(
    name: 'E2E助手',
    atName: 'e2e_helper',
    gatewayId: gateway.connectionId,
    workingDirectory: gateway.workingDirectory,
  );
  final second = await _createContact(
    name: 'E2E二号',
    atName: 'e2e_helper2',
    gatewayId: secondBroken ? 'missing-gateway' : gateway.connectionId,
    workingDirectory: gateway.workingDirectory,
  );
  final group = await GroupChatService()
      .createGroup('E2E群', [first.contactId, second.contactId]);
  return (first, second, group);
}

Future<void> _openGroupChat(WidgetTester tester) async {
  await tester.tap(find.text('通讯录'));
  await tester.pumpAndSettle();
  await pumpUntil(
    tester,
    () => isShowing('群聊'),
    description: '通讯录显示群聊入口',
  );
  await tester.tap(find.text('群聊').first);
  await tester.pumpAndSettle();
  await pumpUntil(
    tester,
    () => isShowing('E2E群'),
    description: '群聊列表显示 E2E群',
  );
  await tester.tap(find.text('E2E群').first);
  await pumpUntil(
    tester,
    () => find.byKey(const ValueKey('group-chat-input')).evaluate().isNotEmpty,
    description: '打开群聊页',
  );
}

Future<void> _sendGroupMessage(WidgetTester tester, String text) async {
  await tester.enterText(
    find.byKey(const ValueKey('group-chat-input')),
    text,
  );
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('group-chat-send')));
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('被 @ 的 AI 联系人回复群消息', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      await resetE2eDatabase();
      requireMockAgentCommand();
      final (config, group) = await _seedGroup();
      manager = await pumpPocketBotApp(tester);

      await _openGroupChat(tester);
      await _sendGroupMessage(tester, '@e2e_helper e2e-group');
      await pumpUntil(
        tester,
        () =>
            isShowing('MOCK_AGENT_OK', findRichText: true) &&
            isShowing('E2E助手'),
        description: '群聊显示代理回复',
      );

      expect(
        isShowing('MOCK_AGENT_OK: 群聊「E2E群」中，我 说：', findRichText: true),
        isTrue,
      );

      final messages = await GroupChatService().getGroupMessages(group.id);
      final replies =
          messages.where((message) => message.senderId == config.contactId);
      expect(replies, hasLength(1));
      expect(replies.first.content, contains('MOCK_AGENT_OK'));
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });

  testWidgets('未被 @ 的 AI 联系人不回复', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      await resetE2eDatabase();
      requireMockAgentCommand();
      final (config, group) = await _seedGroup();
      manager = await pumpPocketBotApp(tester);

      await _openGroupChat(tester);
      await _sendGroupMessage(tester, 'e2e-silent');
      await pumpUntil(
        tester,
        () => isShowing('e2e-silent', findRichText: true),
        description: '群聊显示用户消息',
      );

      await Future<void>.delayed(const Duration(seconds: 2));
      await tester.pump();
      expect(isShowing('MOCK_AGENT_OK', findRichText: true), isFalse);
      expect(find.text('E2E助手'), findsNothing);

      final messages = await GroupChatService().getGroupMessages(group.id);
      final replies =
          messages.where((message) => message.senderId == config.contactId);
      expect(replies, isEmpty);
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });

  testWidgets('多个被 @ 的 AI 联系人分别回复', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      await resetE2eDatabase();
      requireMockAgentCommand();
      final (first, second, group) = await _seedMultiGroup();
      manager = await pumpPocketBotApp(tester);

      await _openGroupChat(tester);
      await _sendGroupMessage(tester, '@e2e_helper @e2e_helper2 e2e-multi');
      await pumpUntil(
        tester,
        () =>
            isShowing('MOCK_AGENT_OK', findRichText: true) &&
            find.text('E2E助手').evaluate().isNotEmpty &&
            find.text('E2E二号').evaluate().isNotEmpty,
        description: '群聊显示两个代理的回复',
      );

      final messages = await GroupChatService().getGroupMessages(group.id);
      final firstReplies =
          messages.where((message) => message.senderId == first.contactId);
      final secondReplies =
          messages.where((message) => message.senderId == second.contactId);
      expect(firstReplies, hasLength(1));
      expect(secondReplies, hasLength(1));
      expect(firstReplies.single.content, contains('MOCK_AGENT_OK'));
      expect(secondReplies.single.content, contains('MOCK_AGENT_OK'));
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });

  testWidgets('某个代理不可用时其他被 @ 的联系人仍回复', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      await resetE2eDatabase();
      requireMockAgentCommand();
      final (first, second, group) =
          await _seedMultiGroup(secondBroken: true);
      manager = await pumpPocketBotApp(tester);

      await _openGroupChat(tester);
      await _sendGroupMessage(tester, '@e2e_helper @e2e_helper2 e2e-multi');
      await pumpUntil(
        tester,
        () => isShowing('E2E二号 无法回复'),
        description: '群聊提示 E2E二号 无法回复',
      );
      await pumpUntil(
        tester,
        () =>
            isShowing('MOCK_AGENT_OK', findRichText: true) &&
            find.text('E2E助手').evaluate().isNotEmpty,
        description: '群聊显示可供代理的回复',
      );

      final messages = await GroupChatService().getGroupMessages(group.id);
      final firstReplies =
          messages.where((message) => message.senderId == first.contactId);
      final secondReplies =
          messages.where((message) => message.senderId == second.contactId);
      expect(firstReplies, hasLength(1));
      expect(firstReplies.single.content, contains('MOCK_AGENT_OK'));
      expect(secondReplies, isEmpty);
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });
}
