import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pocket_bot/config/mcp_config.dart';
import 'package:pocket_bot/models/mcp_server_config.dart';
import 'package:pocket_bot/screens/settings_screen.dart';
import 'package:pocket_bot/services/connection_manager.dart';
import 'package:pocket_bot/widgets/fluent_tab_bar.dart';

import 'e2e_harness.dart';

Future<void> _openMcpScreen(WidgetTester tester) async {
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
    find.text('MCP 服务器'),
    300,
    scrollable: settingsScroll.first,
  );
  await tester.tap(find.text('MCP 服务器'));
  await tester.pumpAndSettle();
  await pumpUntil(
    tester,
    () => isShowing('添加 MCP 服务器'),
    description: '打开 MCP 服务器页',
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

Future<List<McpServerConfig>> _waitForConfig(
  bool Function(List<McpServerConfig> servers) predicate, {
  String description = 'MCP 配置',
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (true) {
    final servers = await McpConfig.load();
    if (predicate(servers)) return servers;
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure('等待超时：$description（当前 ${servers.length} 个服务器）');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

const _seededServer = McpServerConfig(
  id: 'e2e-mcp',
  name: 'E2E MCP',
  command: 'node',
  args: ['server.js'],
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('添加 stdio MCP 服务器', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      manager = await pumpPocketBotApp(tester);

      await _openMcpScreen(tester);
      expect(find.text('还没有 MCP 服务器'), findsOneWidget);

      await tester.tap(find.text('添加 MCP 服务器'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await _enterText(
        tester,
        find.widgetWithText(TextField, '名称'),
        'E2E MCP',
      );
      await _enterText(
        tester,
        find.widgetWithText(TextField, '命令'),
        'node',
      );
      await _enterText(
        tester,
        find.widgetWithText(TextField, '参数（每行一个）'),
        'server.js',
      );
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);

      await pumpUntil(
        tester,
        () => isShowing('E2E MCP'),
        description: 'MCP 列表显示新服务器',
      );
      expect(find.text('node server.js'), findsOneWidget);

      final servers = await _waitForConfig(
        (servers) => servers.any((server) => server.name == 'E2E MCP'),
        description: 'MCP 配置保存新服务器',
      );
      final saved = servers.firstWhere((server) => server.name == 'E2E MCP');
      expect(saved.transport, McpTransport.stdio);
      expect(saved.command, 'node');
      expect(saved.args, ['server.js']);
      expect(saved.enabled, isTrue);
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });

  testWidgets('删除 MCP 服务器', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      manager = await pumpPocketBotApp(tester);
      await manager.saveMcpServers([_seededServer]);

      await _openMcpScreen(tester);
      expect(find.text('E2E MCP'), findsOneWidget);

      await tester.tap(find.byTooltip('删除'));
      await tester.pumpAndSettle();
      await pumpUntil(
        tester,
        () => !isShowing('E2E MCP'),
        description: 'MCP 列表移除服务器',
      );
      expect(find.text('还没有 MCP 服务器'), findsOneWidget);

      final servers = await _waitForConfig(
        (servers) => servers.every((server) => server.name != 'E2E MCP'),
        description: 'MCP 配置移除服务器',
      );
      expect(servers, isEmpty);
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });
}
