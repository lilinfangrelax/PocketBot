import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pocket_bot/models/message.dart';
import 'package:pocket_bot/screens/home_screen.dart';
import 'package:pocket_bot/services/connection_manager.dart';
import 'package:pocket_bot/services/ssh_host_keys.dart';
import 'package:pocket_bot/services/websocket_service.dart' as ws;
import 'package:pocket_bot/widgets/fluent_tab_bar.dart';

import '../e2e_harness.dart';

/// Manual end-to-end check against a real SSH host running Cursor's ACP agent.
///
/// This file lives outside `*_test.dart` at the top level of
/// `integration_test/`, so `tool/e2e_integration.ps1` does not pick it up.
///
/// Usage (PowerShell):
///   $env:POCKETBOT_REAL_SSH_HOST='47.119.137.225'
///   $env:POCKETBOT_REAL_SSH_PORT='37777'
///   $env:POCKETBOT_REAL_SSH_USER='enhook'
///   $env:POCKETBOT_REAL_SSH_KEY_FILE="$env:USERPROFILE\.ssh\id_rsa"
///   $env:NO_PROXY='127.0.0.1,localhost'; $env:no_proxy='127.0.0.1,localhost'
///   flutter test integration_test/manual/real_ssh_test.dart -d windows
///
/// `NO_PROXY` is required: the test driver reaches the app through a localhost
/// VM-service WebSocket, which a system HTTP proxy would intercept.
///
/// The run installs `pocketbot-remote` under the remote `~/.pocketbot` and
/// starts the Cursor CLI there. The remote agent process is intentionally kept
/// alive after disconnect so a later reconnect can resume it.
String _requireEnv(String name) {
  final value = Platform.environment[name];
  if (value == null || value.isEmpty) {
    throw StateError('缺少环境变量 $name');
  }
  return value;
}

Future<void> _enterText(
  WidgetTester tester,
  Finder finder,
  String text,
) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
  await tester.enterText(finder, text);
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('真实 SSH 主机上连接 Cursor agent 并收到回复', (tester) async {
    final host = _requireEnv('POCKETBOT_REAL_SSH_HOST');
    final port = int.parse(_requireEnv('POCKETBOT_REAL_SSH_PORT'));
    final username = _requireEnv('POCKETBOT_REAL_SSH_USER');
    final keyPath = _requireEnv('POCKETBOT_REAL_SSH_KEY_FILE');
    final privateKey = await File(keyPath).readAsString();
    expect(privateKey, contains('PRIVATE KEY'));

    final info = await PackageInfo.fromPlatform();
    debugPrint('[REAL-SSH] app version ${info.version}+${info.buildNumber}');

    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      SshHostKeys.prompt = (check) async {
        debugPrint('[REAL-SSH] host key ${check.host}:${check.port} '
            '${check.keyType} ${check.fingerprint}');
        return true;
      };

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
        find.widgetWithText(TextFormField, '主机'),
        300,
        scrollable: homeScroll.first,
      );
      await _enterText(tester, find.widgetWithText(TextFormField, '主机'), host);
      await _enterText(
        tester,
        find.widgetWithText(TextFormField, '端口'),
        '$port',
      );
      await _enterText(
        tester,
        find.widgetWithText(TextFormField, '用户名'),
        username,
      );
      await _enterText(
        tester,
        find.widgetWithText(TextFormField, '私钥 PEM（可选）'),
        privateKey,
      );

      await tester.scrollUntilVisible(
        find.text('登录并选择目录'),
        300,
        scrollable: homeScroll.first,
      );
      await tester.tap(find.text('登录并选择目录'));

      await pumpUntil(
        tester,
        () => isShowing('选择工作目录'),
        timeout: const Duration(minutes: 2),
        description: 'SSH 登录后打开远程目录选择',
      );
      await pumpUntil(
        tester,
        () {
          final label = find.text('在此目录启动 Agent');
          if (label.evaluate().isEmpty) return false;
          final button = find.ancestor(
            of: label,
            matching: find.byWidgetPredicate(
              (widget) => widget is ButtonStyleButton,
            ),
          );
          if (button.evaluate().isEmpty) return false;
          return tester.widget<ButtonStyleButton>(button.first).onPressed !=
              null;
        },
        timeout: const Duration(minutes: 1),
        description: '远程目录加载完成',
      );
      final pathLabel = find.widgetWithText(TextField, '当前目录');
      if (pathLabel.evaluate().isNotEmpty) {
        debugPrint('[REAL-SSH] remote directory: '
            '${tester.widget<TextField>(pathLabel).controller?.text}');
      }
      debugPrint('[REAL-SSH] starting agent in the remote home directory');
      await tester.tap(find.text('在此目录启动 Agent'));
      await tester.pump();

      await pumpUntil(
        tester,
        () =>
            manager!.state == ws.ConnectionState.connected ||
            manager.state == ws.ConnectionState.error,
        timeout: const Duration(minutes: 15),
        description: '安装远端服务并启动 Cursor agent',
      );
      if (manager.state == ws.ConnectionState.error) {
        throw TestFailure('SSH 连接失败：${manager.errorMessage}');
      }
      debugPrint('[REAL-SSH] connected: ${manager.wsService.currentAgentId} '
          '${manager.wsService.agentInfo}');

      await pumpUntil(
        tester,
        () => isShowing('开始聊天'),
        description: '显示开始聊天入口',
      );
      await openChatFromDiscovery(tester);
      await pumpUntil(
        tester,
        () {
          final service = manager!.wsService;
          return service.activeSession != null;
        },
        timeout: const Duration(minutes: 3),
        description: '建立真实 ACP 会话',
      );

      await sendChatMessage(
        tester,
        'Reply with exactly REAL_AGENT_OK. Do not call any tools or modify files.',
      );
      await pumpUntil(
        tester,
        () {
          final session = manager!.wsService.activeSession;
          if (session == null) return false;
          return session.messages.any((message) =>
              !message.isUser &&
              message.kind == MessageKind.chat &&
              message.text.contains('REAL_AGENT_OK'));
        },
        timeout: const Duration(minutes: 3),
        description: 'Cursor agent 回复 REAL_AGENT_OK',
      );
      await pumpUntil(
        tester,
        () {
          final send = find.byWidgetPredicate(
            (widget) => widget is IconButton && widget.tooltip == '发送',
          );
          final stop = find.byWidgetPredicate(
            (widget) => widget is IconButton && widget.tooltip == '停止',
          );
          return send.evaluate().isNotEmpty && stop.evaluate().isEmpty;
        },
        timeout: const Duration(minutes: 3),
        description: '回复生成结束',
      );
      expect(
        find.textContaining('REAL_AGENT_OK').evaluate().length,
        greaterThanOrEqualTo(2),
        reason: '聊天界面应同时显示用户消息和真实 agent 的回复',
      );
      debugPrint('[REAL-SSH] real agent round-trip succeeded');
    } finally {
      SshHostKeys.prompt = null;
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  }, timeout: const Timeout(Duration(minutes: 30)));
}
