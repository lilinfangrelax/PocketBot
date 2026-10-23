import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pocket_bot/config/gateway_config.dart';
import 'package:pocket_bot/models/message.dart';
import 'package:pocket_bot/screens/home_screen.dart';
import 'package:pocket_bot/services/connection_manager.dart';
import 'package:pocket_bot/widgets/fluent_tab_bar.dart';

import 'e2e_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('未连接时看到本机启动和 SSH 表单', (tester) async {
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
      await tester.pump();
      await pumpUntil(
        tester,
        () => isShowing('未连接'),
        description: '发现页显示未连接',
      );

      final homeScroll = find.descendant(
        of: find.byType(HomeScreen),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('保存并登录'),
        300,
        scrollable: homeScroll.first,
      );

      expect(find.text('启动 Cursor'), findsOneWidget);
      expect(find.text('工作目录'), findsOneWidget);
      expect(find.text('ACP Registry，点按更换代理'), findsOneWidget);
      expect(find.text('保存并登录'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '主机'), findsOneWidget);
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });

  testWidgets('已保存但未检查的 SSH 主机显示登录', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      await GatewayConfig.addGateway(GatewayInfo.ssh(
        host: 'example.invalid',
        username: 'tester',
        name: '未检查主机',
      ));
      manager = await pumpPocketBotApp(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(FluentTabBar),
          matching: find.text('发现'),
        ),
      );
      await tester.pump();
      await pumpUntil(
        tester,
        () => isShowing('登录') && isShowing('未检查'),
        description: '发现页显示未检查的 SSH 主机',
      );
      expect(find.text('未连接'), findsWidgets);
      expect(find.textContaining('SSH 在线 0/1'), findsOneWidget);
      expect(find.text('登录'), findsOneWidget);
      expect(find.text('未检查'), findsOneWidget);
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });

  testWidgets('打开 ACP Registry', (tester) async {
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
      await tester.pump();
      await pumpUntil(
        tester,
        () => isShowing('ACP Registry，点按更换代理'),
        description: '发现页显示代理入口',
      );
      final homeScroll = find.descendant(
        of: find.byType(HomeScreen),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('ACP Registry，点按更换代理'),
        200,
        scrollable: homeScroll.first,
      );
      await tester.tap(find.text('ACP Registry，点按更换代理'));
      await tester.pump();
      await pumpUntil(
        tester,
        () => isShowing('ACP Registry') &&
            isShowing('搜索 Cursor、Claude、Gemini'),
        description: '打开 ACP Registry',
      );
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });
}
