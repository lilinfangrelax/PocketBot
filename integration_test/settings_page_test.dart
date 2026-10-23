import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pocket_bot/screens/settings_screen.dart';
import 'package:pocket_bot/services/connection_manager.dart';
import 'package:pocket_bot/widgets/fluent_tab_bar.dart';

import 'e2e_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('打开设置能看到各分区', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      manager = await pumpPocketBotApp(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(FluentTabBar),
          matching: find.text('我'),
        ),
      );
      await tester.pump();
      await pumpUntil(
        tester,
        () => isShowing('更新通道'),
        description: '设置页显示更新通道',
      );
      expect(find.text('主题'), findsOneWidget);
      expect(find.text('通知'), findsOneWidget);

      final settingsScroll = find.descendant(
        of: find.byType(SettingsScreen),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('查看日志'),
        300,
        scrollable: settingsScroll.first,
      );
      expect(find.text('MCP 服务器'), findsOneWidget);
      expect(find.text('退出 Agent 登录'), findsOneWidget);
      expect(find.text('调试模式'), findsOneWidget);
      expect(find.text('查看日志'), findsOneWidget);
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });

  testWidgets('应用分区展示头像和语言', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      manager = await pumpPocketBotApp(tester);
      await _openSettings(tester);

      expect(find.text('头像'), findsOneWidget);
      expect(find.text('未设置'), findsOneWidget);
      expect(find.text('语言'), findsOneWidget);
      expect(find.text('简体中文'), findsOneWidget);
      expect(find.text('检查更新'), findsOneWidget);

      await tester.tap(find.text('头像'));
      await tester.pump();
      await pumpUntil(
        tester,
        () => isShowing('选择照片'),
        description: '打开头像选择',
      );
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });

  testWidgets('清除全部会话前需要确认', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      manager = await pumpPocketBotApp(tester);
      await _openSettings(tester);
      final settingsScroll = find.descendant(
        of: find.byType(SettingsScreen),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('清除全部会话'),
        300,
        scrollable: settingsScroll.first,
      );
      await tester.tap(find.text('清除全部会话'));
      await tester.pump();
      await pumpUntil(
        tester,
        () => isShowing('此操作无法撤销'),
        description: '清除会话前要求确认',
      );
      await tester.tap(find.text('取消'));
      await tester.pump();
      await pumpUntil(
        tester,
        () => isShowing('设置'),
        description: '取消后仍在设置页',
      );
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });

  testWidgets('打开主题选择', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      manager = await pumpPocketBotApp(tester);
      await _openSettings(tester);
      await tester.tap(find.text('主题'));
      await tester.pump();
      await pumpUntil(
        tester,
        () => isShowing('选择主题'),
        description: '打开主题选择',
      );
      expect(find.text('浅色'), findsOneWidget);
      expect(find.text('深色'), findsOneWidget);
      expect(find.text('跟随系统'), findsWidgets);
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });

  testWidgets('代理与关于分区展示其余入口', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      manager = await pumpPocketBotApp(tester);
      await _openSettings(tester);
      final settingsScroll = find.descendant(
        of: find.byType(SettingsScreen),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('隐私政策'),
        300,
        scrollable: settingsScroll.first,
      );
      expect(find.text('自动允许代理操作'), findsOneWidget);
      expect(find.text('开源'), findsOneWidget);
      expect(find.text('隐私政策'), findsOneWidget);
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });

  testWidgets('打开空的 MCP 服务器页', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      manager = await pumpPocketBotApp(tester);
      await _openSettings(tester);
      final settingsScroll = find.descendant(
        of: find.byType(SettingsScreen),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('MCP 服务器'),
        300,
        scrollable: settingsScroll.first,
      );
      await tester.tap(find.text('MCP 服务器'));
      await tester.pump();
      await pumpUntil(
        tester,
        () => isShowing('还没有 MCP 服务器'),
        description: '打开空的 MCP 列表',
      );
      expect(find.text('添加 MCP 服务器'), findsOneWidget);
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });

  testWidgets('打开调试日志', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      manager = await pumpPocketBotApp(tester);
      await _openSettings(tester);
      final settingsScroll = find.descendant(
        of: find.byType(SettingsScreen),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('查看日志'),
        300,
        scrollable: settingsScroll.first,
      );
      await tester.drag(settingsScroll.first, const Offset(0, -160));
      await tester.pump();
      await tester.tap(find.text('查看日志'));
      await tester.pump();
      await pumpUntil(
        tester,
        () => isShowing('调试日志'),
        description: '打开调试日志',
      );
      expect(find.text('调试模式未开启'), findsOneWidget);
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });
}

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(FluentTabBar),
      matching: find.text('我'),
    ),
  );
  await tester.pump();
  await pumpUntil(
    tester,
    () => isShowing('更新通道'),
    description: '打开设置页',
  );
}
