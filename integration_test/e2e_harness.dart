import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pocket_bot/config/session_storage.dart';
import 'package:pocket_bot/main.dart';
import 'package:pocket_bot/models/message.dart';
import 'package:pocket_bot/services/ai_contact_service.dart';
import 'package:pocket_bot/services/connection_manager.dart';
import 'package:pocket_bot/services/contact_agent_linker.dart';
import 'package:pocket_bot/services/database_service.dart';
import 'package:pocket_bot/services/group_chat_service.dart';
import 'package:pocket_bot/services/websocket_service.dart' as ws;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _storage = FlutterSecureStorage();
const _gatewaysKey = 'gateways_config';
const _lastConnectedKey = 'last_connected_gateway';
const _sessionsKey = 'chat_sessions';
const _agentIdKey = 'acp_agent_id';
const _agentLabelKey = 'acp_agent_label';
const _autoApproveKey = 'acp_auto_approve_permissions';
const _mcpKey = 'mcp_servers';
const _sshKnownHostsKey = 'ssh_known_hosts';

/// Preserves the signed-in user's chats, saved agents and agent selection so
/// an E2E run can start from a clean state and put everything back afterwards.
class AppStateSnapshot {
  AppStateSnapshot._({
    required this.gateways,
    required this.lastConnected,
    required this.sessions,
    required this.mcpServers,
    required this.sshKnownHosts,
    required this.agentId,
    required this.agentLabel,
    required this.autoApprove,
  });

  final String? gateways;
  final String? lastConnected;
  final String? sessions;
  final String? mcpServers;
  final String? sshKnownHosts;
  final String? agentId;
  final String? agentLabel;
  final bool? autoApprove;

  static Future<AppStateSnapshot> capture() async {
    final prefs = await SharedPreferences.getInstance();
    return AppStateSnapshot._(
      gateways: await _storage.read(key: _gatewaysKey),
      lastConnected: await _storage.read(key: _lastConnectedKey),
      sessions: await _storage.read(key: _sessionsKey),
      mcpServers: await _storage.read(key: _mcpKey),
      sshKnownHosts: await _storage.read(key: _sshKnownHostsKey),
      agentId: prefs.getString(_agentIdKey),
      agentLabel: prefs.getString(_agentLabelKey),
      autoApprove: prefs.getBool(_autoApproveKey),
    );
  }

  Future<void> clear() async {
    await _storage.delete(key: _gatewaysKey);
    await _storage.delete(key: _lastConnectedKey);
    await _storage.delete(key: _sessionsKey);
    await _storage.delete(key: _mcpKey);
    await _storage.delete(key: _sshKnownHostsKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_agentIdKey);
    await prefs.remove(_agentLabelKey);
    await prefs.remove(_autoApproveKey);
  }

  Future<void> restore() async {
    await _restoreKey(_gatewaysKey, gateways);
    await _restoreKey(_lastConnectedKey, lastConnected);
    await _restoreKey(_sessionsKey, sessions);
    await _restoreKey(_mcpKey, mcpServers);
    await _restoreKey(_sshKnownHostsKey, sshKnownHosts);
    final prefs = await SharedPreferences.getInstance();
    if (agentId == null) {
      await prefs.remove(_agentIdKey);
    } else {
      await prefs.setString(_agentIdKey, agentId!);
    }
    if (agentLabel == null) {
      await prefs.remove(_agentLabelKey);
    } else {
      await prefs.setString(_agentLabelKey, agentLabel!);
    }
    if (autoApprove == null) {
      await prefs.remove(_autoApproveKey);
    } else {
      await prefs.setBool(_autoApproveKey, autoApprove!);
    }
  }

  Future<void> _restoreKey(String key, String? value) async {
    if (value == null) {
      await _storage.delete(key: key);
    } else {
      await _storage.write(key: key, value: value);
    }
  }
}

String requireE2eDbDir() {
  final dir = Platform.environment['POCKETBOT_E2E_DB_DIR'];
  if (dir == null || dir.isEmpty) {
    throw StateError(
      'POCKETBOT_E2E_DB_DIR 未设置。请通过 tool/e2e_integration.ps1 运行 E2E。',
    );
  }
  return dir;
}

String requireMockAgentCommand() {
  final command = Platform.environment['POCKETBOT_E2E_MOCK_AGENT'];
  if (command == null || command.isEmpty) {
    throw StateError(
      'POCKETBOT_E2E_MOCK_AGENT 未设置。请通过 tool/e2e_integration.ps1 运行 E2E。',
    );
  }
  return command;
}

GatewayInfo mockGateway({String? workingDirectory}) {
  return GatewayInfo.local(
    name: 'Mock Agent',
    workingDirectory: workingDirectory ?? Directory.current.path,
    agentId: 'pocketbot-mock',
    agentLabel: 'Mock Agent',
  );
}

Future<void> resetE2eDatabase() async {
  final keep = Platform.environment['POCKETBOT_E2E_KEEP_DB'];
  if (keep == '1' || keep?.toLowerCase() == 'true') return;
  await DatabaseService().close();
  AIContactService.resetTableCache();
  final base = p.join(requireE2eDbDir(), 'pocket_bot.db');
  for (final suffix in const ['', '-wal', '-shm', '-journal']) {
    final file = File('$base$suffix');
    if (file.existsSync()) file.deleteSync();
  }
}

/// Unmounts the app and lets debounced session writes land before storage is
/// restored, so dispose-time saves cannot race with [AppStateSnapshot.restore].
Future<void> unmountApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await Future<void>.delayed(const Duration(milliseconds: 600));
}

Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 60),
  String description = 'condition',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure('等待超时：$description');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 60),
  String description = 'condition',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure('等待超时：$description');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

bool isShowing(String text, {bool findRichText = false}) {
  return find
      .textContaining(text, findRichText: findRichText)
      .evaluate()
      .isNotEmpty;
}

Future<void> selectMockAgent() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_agentIdKey, 'pocketbot-mock');
  await prefs.setString(_agentLabelKey, 'Mock Agent');
}

Future<ConnectionManager> pumpPocketBotApp(
  WidgetTester tester, {
  ConnectionManager? manager,
}) async {
  final connection = manager ?? ConnectionManager();
  GroupChatService().linker = ContactAgentLinker(connection);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<ConnectionManager>.value(value: connection),
      ChangeNotifierProvider(create: (_) => ws.WebSocketService()),
      ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ChangeNotifierProvider<UserConfigProvider>.value(
        value: UserConfigProvider(),
      ),
    ],
    child: const PocketBotApp(),
  ));
  await tester.pumpAndSettle();
  return connection;
}

Future<void> disposePocketBotApp(
  WidgetTester tester,
  ConnectionManager? manager,
) async {
  await unmountApp(tester);
  if (manager != null) {
    await manager.disconnect();
    for (final service in List.of(manager.pooledServices)) {
      await service.disconnect();
    }
    manager.dispose();
  }
  await SessionStorage.flush();
}

Future<void> connectMockAgentFromDiscovery(
  WidgetTester tester,
  ConnectionManager manager,
) async {
  await tester.tap(find.text('发现'));
  await tester.pumpAndSettle();
  await pumpUntil(
    tester,
    () => isShowing('启动 Mock Agent'),
    description: '发现页加载 Mock 代理',
  );
  await tester.tap(find.text('启动 Mock Agent'));
  await pumpUntil(
    tester,
    () => manager.state == ws.ConnectionState.connected,
    description: '连接 Mock 代理',
  );
  await tester.pumpAndSettle();
}

Future<void> openChatFromDiscovery(WidgetTester tester) async {
  await tester.tap(find.text('开始聊天'));
  await pumpUntil(
    tester,
    () => find.byKey(const ValueKey('chat-input')).evaluate().isNotEmpty,
    description: '打开聊天页',
  );
}

Future<ConnectionManager> startMockChat(WidgetTester tester) async {
  await selectMockAgent();
  final manager = await pumpPocketBotApp(tester);
  await connectMockAgentFromDiscovery(tester, manager);
  await openChatFromDiscovery(tester);
  return manager;
}

Future<void> sendChatMessage(WidgetTester tester, String text) async {
  // Integration tests use the real text input channel, so the field must be
  // focused (and its input connection attached) before injecting text.
  await tester.tap(find.byKey(const ValueKey('chat-input')));
  await tester.pump();
  await tester.enterText(find.byKey(const ValueKey('chat-input')), text);
  await tester.pump();
  final sendButton = find.byWidgetPredicate(
    (widget) => widget is IconButton && widget.tooltip == '发送',
  );
  if (sendButton.evaluate().isEmpty) {
    throw TestFailure('发送按钮不存在（代理可能仍在生成回复）');
  }
  final button = tester.widget<IconButton>(sendButton);
  if (button.onPressed == null) {
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('chat-input')),
    );
    throw TestFailure('发送按钮不可用，输入框内容="${field.controller?.text}"');
  }
  await tester.tap(sendButton);
  await tester.pump();
}

bool chatInputIsEmpty(WidgetTester tester) {
  final field = tester.widget<TextField>(
    find.byKey(const ValueKey('chat-input')),
  );
  return field.controller?.text.isEmpty ?? true;
}
