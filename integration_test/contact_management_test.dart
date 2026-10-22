import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pocket_bot/config/gateway_config.dart';
import 'package:pocket_bot/models/ai_contact_config.dart';
import 'package:pocket_bot/services/ai_contact_service.dart';
import 'package:pocket_bot/services/connection_manager.dart';
import 'package:pocket_bot/services/contact_service.dart';

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

Future<void> _openContactDetail(WidgetTester tester) async {
  await tester.tap(find.text('通讯录'));
  await tester.pumpAndSettle();
  await pumpUntil(
    tester,
    () => isShowing('E2E助手'),
    description: '通讯录中显示联系人',
  );
  await tester.tap(find.text('E2E助手').first);
  await tester.pumpAndSettle();
  await pumpUntil(
    tester,
    () => isShowing('联系人详情'),
    description: '打开联系人详情',
  );
}

Future<void> _enterText(
  WidgetTester tester,
  Finder finder,
  String text,
) async {
  await tester.tap(finder);
  await tester.pump();
  await tester.enterText(finder, text);
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('编辑联系人名称', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      await resetE2eDatabase();
      final config = await _seedContact();
      manager = await pumpPocketBotApp(tester);

      await _openContactDetail(tester);
      await tester.tap(find.byIcon(Icons.edit));
      await tester.pumpAndSettle();
      await pumpUntil(
        tester,
        () => isShowing('编辑联系人'),
        description: '打开编辑联系人页',
      );

      await _enterText(tester, find.byType(TextField).first, 'E2E助手改名');
      await tester.tap(find.text('保存').last);
      await tester.pumpAndSettle();
      await pumpUntil(
        tester,
        () => isShowing('E2E助手改名'),
        description: '联系人详情显示新名称',
      );
      expect((await ContactService().getContact(config.contactId))?.name,
          'E2E助手改名');

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await pumpUntil(
        tester,
        () => isShowing('E2E助手改名'),
        description: '通讯录列表显示新名称',
      );
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });

  testWidgets('删除联系人', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      await resetE2eDatabase();
      final config = await _seedContact();
      manager = await pumpPocketBotApp(tester);

      await _openContactDetail(tester);
      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();
      await pumpUntil(
        tester,
        () => isShowing('确定要删除'),
        description: '显示删除确认',
      );
      await tester.tap(find.text('删除').last);
      await tester.pumpAndSettle();
      await pumpUntil(
        tester,
        () => !isShowing('E2E助手'),
        description: '通讯录列表移除联系人',
      );
      expect((await ContactService().getContact(config.contactId))?.isActive,
          isFalse);
      expect(
        (await ContactService().getAllContacts())
            .where((contact) => contact.id == config.contactId),
        isEmpty,
      );
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });
}
