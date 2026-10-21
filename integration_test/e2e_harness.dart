import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pocket_bot/models/message.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _storage = FlutterSecureStorage();
const _gatewaysKey = 'gateways_config';
const _lastConnectedKey = 'last_connected_gateway';
const _sessionsKey = 'chat_sessions';
const _agentIdKey = 'acp_agent_id';
const _agentLabelKey = 'acp_agent_label';

/// Preserves the signed-in user's chats, saved agents and agent selection so
/// an E2E run can start from a clean state and put everything back afterwards.
class AppStateSnapshot {
  AppStateSnapshot._({
    required this.gateways,
    required this.lastConnected,
    required this.sessions,
    required this.agentId,
    required this.agentLabel,
  });

  final String? gateways;
  final String? lastConnected;
  final String? sessions;
  final String? agentId;
  final String? agentLabel;

  static Future<AppStateSnapshot> capture() async {
    final prefs = await SharedPreferences.getInstance();
    return AppStateSnapshot._(
      gateways: await _storage.read(key: _gatewaysKey),
      lastConnected: await _storage.read(key: _lastConnectedKey),
      sessions: await _storage.read(key: _sessionsKey),
      agentId: prefs.getString(_agentIdKey),
      agentLabel: prefs.getString(_agentLabelKey),
    );
  }

  Future<void> clear() async {
    await _storage.delete(key: _gatewaysKey);
    await _storage.delete(key: _lastConnectedKey);
    await _storage.delete(key: _sessionsKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_agentIdKey);
    await prefs.remove(_agentLabelKey);
  }

  Future<void> restore() async {
    await _restoreKey(_gatewaysKey, gateways);
    await _restoreKey(_lastConnectedKey, lastConnected);
    await _restoreKey(_sessionsKey, sessions);
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

void resetE2eDatabase() {
  final keep = Platform.environment['POCKETBOT_E2E_KEEP_DB'];
  if (keep == '1' || keep?.toLowerCase() == 'true') return;
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
