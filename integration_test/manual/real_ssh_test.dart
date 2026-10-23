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

/// Real end-to-end check for `features/zh-CN/真实远程Agent.feature`.
///
/// This file lives outside `*_test.dart` at the top level of
/// `integration_test/`, so `tool/e2e_integration.ps1` does not pick it up.
///
/// Usage (PowerShell), from the repo root `.env`:
///   powershell -ExecutionPolicy Bypass -File tool/e2e_real_ssh.ps1
///
/// Required `.env` keys: POCKETBOT_REAL_SSH_HOST, POCKETBOT_REAL_SSH_PORT,
/// POCKETBOT_REAL_SSH_USER, POCKETBOT_REAL_SSH_KEY_FILE.
/// Optional: POCKETBOT_REAL_SSH_KEY_PASSPHRASE.
/// Process environment overrides `.env`. The runner must still set `NO_PROXY`
/// before `flutter test`, because the driver WebSocket is opened by the tool
/// process rather than this test.
///
/// The run installs `pocketbot-remote` under the remote `~/.pocketbot` and
/// starts the Cursor CLI there. The remote agent process is intentionally kept
/// alive after disconnect so a later reconnect can resume it.
final Map<String, String> _dotenv = _loadDotEnv();

Map<String, String> _loadDotEnv() {
  final file = File('.env');
  if (!file.existsSync()) return const {};
  final values = <String, String>{};
  for (final raw in file.readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final eq = line.indexOf('=');
    if (eq < 1) continue;
    final name = line.substring(0, eq).trim();
    var value = line.substring(eq + 1).trim();
    final quoted = value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")));
    if (quoted) value = value.substring(1, value.length - 1);
    values[name] = value;
  }
  return values;
}

String _requireEnv(String name) {
  final fromProcess = Platform.environment[name];
  final value =
      (fromProcess != null && fromProcess.isNotEmpty) ? fromProcess : _dotenv[name];
  if (value == null || value.isEmpty) {
    throw StateError(
      '缺少 $name。请在仓库根目录 .env 中填写后运行 tool/e2e_real_ssh.ps1',
    );
  }
  return value;
}

String? _optionalEnv(String name) {
  final fromProcess = Platform.environment[name];
  if (fromProcess != null && fromProcess.isNotEmpty) return fromProcess;
  final value = _dotenv[name];
  if (value == null || value.isEmpty) return null;
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

/// The saved-host row sits above the SSH form. A [ListView] does not build
/// rows that are scrolled out of cache, so pull the list back toward the top
/// until [text] is mounted.
Future<void> _waitUntilShown(
  WidgetTester tester,
  Finder scrollable,
  String text, {
  required Duration timeout,
  required String description,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!isShowing(text)) {
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure('等待超时：$description');
    }
    if (isShowing('离线')) {
      throw TestFailure('SSH 登录失败，主机显示离线');
    }
    await tester.drag(scrollable, const Offset(0, 500));
    await tester.pump(const Duration(milliseconds: 200));
  }
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
      final passphrase = _optionalEnv('POCKETBOT_REAL_SSH_KEY_PASSPHRASE');
      if (passphrase != null) {
        await _enterText(
          tester,
          find.widgetWithText(TextFormField, '私钥密码（私钥加密时填写）'),
          passphrase,
        );
      }

      await tester.scrollUntilVisible(
        find.text('保存并登录'),
        300,
        scrollable: homeScroll.first,
      );
      await tester.tap(find.text('保存并登录'));
      await tester.pump();

      await _waitUntilShown(
        tester,
        homeScroll.first,
        '选目录启动',
        timeout: const Duration(minutes: 2),
        description: 'SSH 登录成功后出现选目录启动',
      );
      await tester.ensureVisible(find.text('选目录启动'));
      await tester.tap(find.text('选目录启动'));
      await tester.pump();

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
      await pumpUntil(
        tester,
        () => !isShowing('正在登录远程主机'),
        timeout: const Duration(seconds: 5),
        description: '关闭正在登录提示',
      );
      final startAgent = find.text('在此目录启动 Agent');
      await tester.ensureVisible(startAgent);
      await tester.pump();
      await tester.tap(startAgent);
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
