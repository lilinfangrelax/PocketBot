import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pocket_bot/services/connection_manager.dart';
import 'package:pocket_bot/widgets/fluent_tab_bar.dart';

import 'e2e_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('空列表打开创建群组', (tester) async {
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
        () => isShowing('群聊'),
        description: '通讯录显示群聊入口',
      );
      await tester.tap(find.text('群聊').first);
      await tester.pump();
      await pumpUntil(
        tester,
        () => isShowing('暂无群聊'),
        description: '群聊列表为空',
      );

      await tester.tap(find.text('创建群聊'));
      await tester.pump();
      await pumpUntil(
        tester,
        () => isShowing('群组名称'),
        description: '打开创建群组',
      );
      expect(find.text('创建群组'), findsOneWidget);
      expect(find.text('群聊工作目录'), findsOneWidget);
      expect(find.text('请先添加联系人'), findsOneWidget);
      expect(find.textContaining('开发中'), findsNothing);
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });
}
