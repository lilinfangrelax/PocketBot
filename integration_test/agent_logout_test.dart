import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pocket_bot/screens/settings_screen.dart';
import 'package:pocket_bot/services/connection_manager.dart';
import 'package:pocket_bot/widgets/fluent_tab_bar.dart';

import 'e2e_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('从设置页退出 Agent 登录', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      await resetE2eDatabase();
      requireMockAgentCommand();
      await selectMockAgent();
      manager = await pumpPocketBotApp(tester);
      await connectMockAgentFromDiscovery(tester, manager);

      await tester.tap(
        find.descendant(
          of: find.byType(FluentTabBar),
          matching: find.text('我'),
        ),
      );
      await tester.pumpAndSettle();

      final settingsScroll = find.descendant(
        of: find.byType(SettingsScreen),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('退出 Agent 登录'),
        300,
        scrollable: settingsScroll.first,
      );
      await tester.tap(find.text('退出 Agent 登录'));
      await tester.pumpAndSettle();
      expect(find.text('退出 Agent 登录？'), findsOneWidget);

      await tester.tap(find.text('退出登录'));
      await pumpUntil(
        tester,
        () => isShowing('已退出 Agent 登录'),
        description: '显示退出登录成功提示',
      );
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });
}
