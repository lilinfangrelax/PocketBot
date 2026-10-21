import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pocket_bot/config/gateway_config.dart';
import 'package:pocket_bot/config/session_storage.dart';
import 'package:pocket_bot/models/group_chat.dart';
import 'package:pocket_bot/services/ai_contact_service.dart';
import 'package:pocket_bot/services/connection_manager.dart';
import 'package:pocket_bot/services/contact_agent_linker.dart';
import 'package:pocket_bot/services/group_chat_service.dart';
import 'package:pocket_bot/services/websocket_service.dart' as ws;

import 'e2e_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('群聊 @ 路由', (tester) async {
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
      final groupService = GroupChatService();
      groupService.linker = ContactAgentLinker(manager);

      final group = await groupService.createGroup('E2E群', [config.contactId]);
      expect(group.members, hasLength(1));
      expect(group.members.first.atName, 'e2e_helper');

      final mentioned = GroupMessage(
        id: 'msg_e2e_mentioned',
        groupId: group.id,
        senderId: 'user_me',
        senderName: '我',
        content: '@e2e_helper e2e-group',
        timestamp: DateTime.now(),
      );
      await groupService.sendGroupMessage(mentioned);
      final replies = await groupService.dispatchToAgents(group, mentioned);
      expect(replies, hasLength(1));
      expect(replies.first.senderName, 'E2E助手');
      expect(replies.first.content, contains('MOCK_AGENT_OK'));

      final afterMention = await groupService.getGroupMessages(group.id);
      expect(
        afterMention.any(
          (message) =>
              message.senderId == config.contactId &&
              message.content.contains('MOCK_AGENT_OK'),
        ),
        isTrue,
      );

      final silent = GroupMessage(
        id: 'msg_e2e_silent',
        groupId: group.id,
        senderId: 'user_me',
        senderName: '我',
        content: 'e2e-silent',
        timestamp: DateTime.now(),
      );
      await groupService.sendGroupMessage(silent);
      final silentReplies = await groupService.dispatchToAgents(group, silent);
      expect(silentReplies, isEmpty);
      final afterSilent = await groupService.getGroupMessages(group.id);
      final agentMessages =
          afterSilent.where((message) => message.senderId == config.contactId);
      expect(agentMessages, hasLength(1));
    } finally {
      await unmountApp(tester);
      if (manager != null) {
        await waitUntil(
          () => manager!.state != ws.ConnectionState.connecting,
          description: '主连接结束',
        );
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
