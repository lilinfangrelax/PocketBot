import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pocket_bot/screens/home_screen.dart';
import 'package:pocket_bot/services/connection_manager.dart';
import 'package:pocket_bot/widgets/fluent_tab_bar.dart';

import 'e2e_harness.dart';

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

  testWidgets('缺少密码或私钥时提示', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      manager = await pumpPocketBotApp(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(FluentTabBar),
          matching: find.text('发现'),
        ),
      );
      await tester.pumpAndSettle();

      final homeScroll = find.descendant(
        of: find.byType(HomeScreen),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('保存并登录'),
        300,
        scrollable: homeScroll.first,
      );

      await _enterText(
        tester,
        find.widgetWithText(TextFormField, '主机'),
        'example.invalid',
      );
      await _enterText(
        tester,
        find.widgetWithText(TextFormField, '用户名'),
        'tester',
      );

      await tester.scrollUntilVisible(
        find.text('保存并登录'),
        300,
        scrollable: homeScroll.first,
      );
      await tester.tap(find.text('保存并登录'));
      await tester.pumpAndSettle();
      await pumpUntil(
        tester,
        () => isShowing('请填写 SSH 密码或私钥'),
        description: '提示缺少 SSH 凭据',
      );
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });
}
