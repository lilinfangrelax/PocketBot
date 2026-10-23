import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pocket_bot/services/connection_manager.dart';

import 'e2e_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('新建会话进入未连接的聊天', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      await resetE2eDatabase();
      manager = await pumpPocketBotApp(tester);

      await pumpUntil(
        tester,
        () => isShowing('暂无会话'),
        description: '消息页为空',
      );
      await tester.tap(find.text('新建会话'));
      await tester.pump();
      await pumpUntil(
        tester,
        () => isShowing('开始对话'),
        description: '打开空聊天',
      );
      expect(find.text('连接已断开，请重新连接 Agent'), findsOneWidget);
      expect(find.text('重连'), findsOneWidget);
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });

  testWidgets('搜索能找到刚新建的会话', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      await resetE2eDatabase();
      manager = await pumpPocketBotApp(tester);

      await pumpUntil(
        tester,
        () => isShowing('暂无会话'),
        description: '消息页为空',
      );
      await tester.tap(find.text('新建会话'));
      await tester.pump();
      await pumpUntil(
        tester,
        () => isShowing('今天'),
        description: '聊天标题显示今天',
      );
      await tester.tap(find.byKey(const ValueKey('screen-back')).last);
      await tester.pump();
      await pumpUntil(
        tester,
        () => find.bySemanticsLabel('搜索会话').evaluate().isNotEmpty,
        description: '回到消息列表',
      );
      await tester.tap(find.bySemanticsLabel('搜索会话'));
      await tester.pump();
      await pumpUntil(
        tester,
        () => isShowing('新对话'),
        description: '搜索结果包含新对话',
      );
      expect(find.text('暂无消息'), findsWidgets);
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });
}
