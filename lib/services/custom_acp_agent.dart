import 'dart:convert';
import 'dart:io';

import 'package:pocket_bot/services/cursor_agent.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stored selection id for a user-defined ACP command.
///
/// The prefix keeps these agents out of the public ACP Registry lookup.
const customAcpPrefix = 'custom:';

const customAcpAgentsKey = 'custom_acp_agents';

final RegExp _agentIdPattern = RegExp(r'^[A-Za-z0-9_-]+$');

/// What the agent picker returns, whether it came from the registry or not.
class AcpAgentSelection {
  final String id;
  final String label;

  const AcpAgentSelection({required this.id, required this.label});
}

/// A local ACP command, shaped like Teshi's agent profile: program, args, env.
class CustomAcpAgent {
  final String id;
  final String name;
  final String program;
  final List<String> args;
  final Map<String, String> env;

  const CustomAcpAgent({
    required this.id,
    required this.name,
    required this.program,
    this.args = const [],
    this.env = const {},
  });

  String get selectionId => '$customAcpPrefix$id';

  factory CustomAcpAgent.fromJson(Map<String, dynamic> json) {
    return CustomAcpAgent(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      program: json['program'] as String? ?? '',
      args: _stringList(json['args']),
      env: _stringMap(json['env']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'program': program,
        'args': args,
        if (env.isNotEmpty) 'env': env,
      };
}

bool isCustomAcpAgentId(String agentId) => agentId.startsWith(customAcpPrefix);

/// Local id after `custom:`, or null when [agentId] is a registry id.
String? customAcpLocalId(String agentId) {
  if (!isCustomAcpAgentId(agentId)) return null;
  final local = agentId.substring(customAcpPrefix.length);
  return local.isEmpty ? null : local;
}

/// Null when the profile can be saved.
String? validateCustomAcpAgent(CustomAcpAgent agent) {
  if (!_agentIdPattern.hasMatch(agent.id)) {
    return 'ID 只能包含字母、数字、短横线和下划线';
  }
  if (agent.name.trim().isEmpty) return '名称不能为空';
  if (agent.program.trim().isEmpty) return '程序不能为空';
  return null;
}

/// Turns a display name into an id. Empty when nothing usable remains.
String suggestCustomAcpId(String name) {
  final buffer = StringBuffer();
  for (final rune in name.trim().toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    if (_agentIdPattern.hasMatch(char)) {
      buffer.write(char);
    } else if (char.trim().isEmpty && buffer.isNotEmpty) {
      buffer.write('-');
    }
  }
  return buffer.toString().replaceAll(RegExp(r'-+'), '-').replaceAll(
        RegExp(r'^-+|-+$'),
        '',
      );
}

List<CustomAcpAgent> parseCustomAcpAgents(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! List) return const [];
  final agents = <CustomAcpAgent>[];
  for (final item in decoded) {
    if (item is! Map) continue;
    final agent = CustomAcpAgent.fromJson(Map<String, dynamic>.from(item));
    if (validateCustomAcpAgent(agent) != null) continue;
    agents.add(agent);
  }
  agents.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return agents;
}

CustomAcpAgent? findCustomAcpAgent(
  List<CustomAcpAgent> agents,
  String agentId,
) {
  final local = customAcpLocalId(agentId);
  if (local == null) return null;
  for (final agent in agents) {
    if (agent.id == local) return agent;
  }
  return null;
}

/// One argument per non-empty line. Lines are not split on spaces.
List<String> parseCustomAcpArgs(String text) {
  return text
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
}

/// `KEY=VALUE` per line. The first `=` separates the name from the value.
Map<String, String> parseCustomAcpEnv(String text) {
  final env = <String, String>{};
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final index = line.indexOf('=');
    if (index <= 0) {
      throw FormatException('环境变量需要写成 KEY=VALUE：$line');
    }
    env[line.substring(0, index).trim()] = line.substring(index + 1);
  }
  return env;
}

class CustomAcpCatalog {
  static Future<List<CustomAcpAgent>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(customAcpAgentsKey);
    if (raw == null || raw.isEmpty) return const [];
    return parseCustomAcpAgents(raw);
  }

  static Future<void> upsert(CustomAcpAgent agent) async {
    final error = validateCustomAcpAgent(agent);
    if (error != null) throw FormatException(error);
    final agents = await load();
    final next = [
      for (final item in agents)
        if (item.id != agent.id) item,
      agent,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    await _write(next);
  }

  static Future<void> remove(String id) async {
    final agents = await load();
    await _write([
      for (final item in agents)
        if (item.id != id) item
    ]);
  }

  static Future<void> _write(List<CustomAcpAgent> agents) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      customAcpAgentsKey,
      jsonEncode([for (final agent in agents) agent.toJson()]),
    );
  }
}

/// Resolves a custom program without the Cursor Agent install layout.
Future<ResolvedAgent> resolveCustomProgram(String program) async {
  final command = program.trim();
  if (command.isEmpty) {
    throw Exception('CUSTOM_AGENT_NOT_FOUND:自定义代理程序为空');
  }
  if (_looksLikePath(command)) {
    if (!File(command).existsSync()) {
      throw Exception('CUSTOM_AGENT_NOT_FOUND:找不到自定义代理程序 $command');
    }
    return _resolved(command);
  }
  final found = await _which(command);
  if (found == null) {
    throw Exception('CUSTOM_AGENT_NOT_FOUND:找不到自定义代理程序 $command');
  }
  return _resolved(found);
}

bool _looksLikePath(String command) {
  return command.contains('\\') ||
      command.contains('/') ||
      command.endsWith('.cmd') ||
      command.endsWith('.ps1') ||
      command.endsWith('.bat') ||
      command.endsWith('.exe');
}

ResolvedAgent _resolved(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.ps1')) {
    return ResolvedAgent(
      executable: Platform.isWindows ? 'powershell.exe' : 'pwsh',
      prefixArgs: ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path],
    );
  }
  return ResolvedAgent(
    executable: path,
    runInShell: lower.endsWith('.cmd') || lower.endsWith('.bat'),
  );
}

Future<String?> _which(String command) async {
  try {
    final result = await Process.run(
      Platform.isWindows ? 'where' : 'which',
      [command],
      runInShell: true,
    );
    if (result.exitCode != 0) return null;
    final line = result.stdout.toString().split(RegExp(r'\r?\n')).first.trim();
    return line.isEmpty ? null : line;
  } catch (_) {
    return null;
  }
}

List<String> _stringList(dynamic raw) {
  if (raw is! List) return const [];
  return raw.map((item) => item.toString()).toList();
}

Map<String, String> _stringMap(dynamic raw) {
  if (raw is! Map) return const {};
  return raw.map((key, value) => MapEntry('$key', '$value'));
}
