import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:pocket_bot/models/message.dart';

const customAcpPrefsKey = 'acp_custom_agents';
const customAcpIdPrefix = 'custom:';

bool isCustomAcpId(String id) => id.startsWith(customAcpIdPrefix);

/// An ACP agent the user named themselves, started by a local command.
class CustomAcpAgent {
  final String id;
  final String name;
  final String command;
  final List<String> args;

  const CustomAcpAgent({
    required this.id,
    required this.name,
    required this.command,
    this.args = const [],
  });

  String get commandLine {
    if (args.isEmpty) return command;
    return '$command ${args.join(' ')}';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'command': command,
        'args': args,
      };

  static CustomAcpAgent? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final command = (raw['command'] as String? ?? '').trim();
    final name = (raw['name'] as String? ?? '').trim();
    var id = (raw['id'] as String? ?? '').trim();
    if (command.isEmpty) return null;
    if (!isCustomAcpId(id)) {
      id = '$customAcpIdPrefix${command.hashCode.abs()}';
    }
    return CustomAcpAgent(
      id: id,
      name: name.isEmpty ? command : name,
      command: command,
      args: _stringList(raw['args']),
    );
  }
}

/// What the registry screen returns: a published agent or a saved custom one.
class AcpAgentChoice {
  final String id;
  final String name;

  const AcpAgentChoice({required this.id, required this.name});
}

List<String> _stringList(dynamic raw) {
  if (raw is! List) return const [];
  return raw.map((item) => item.toString()).toList();
}

List<CustomAcpAgent> parseCustomAcpAgents(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  final decoded = jsonDecode(raw);
  if (decoded is! List) return const [];
  final agents = <CustomAcpAgent>[];
  for (final item in decoded) {
    final agent = CustomAcpAgent.fromJson(item);
    if (agent != null) agents.add(agent);
  }
  return agents;
}

String encodeCustomAcpAgents(List<CustomAcpAgent> agents) {
  return jsonEncode(agents.map((agent) => agent.toJson()).toList());
}

/// Split an arguments field on whitespace, keeping quoted pieces together.
List<String> splitAcpArgs(String raw) {
  final args = <String>[];
  final current = StringBuffer();
  var quote = '';
  for (final rune in raw.runes) {
    final char = String.fromCharCode(rune);
    if (quote.isNotEmpty) {
      if (char == quote) {
        quote = '';
      } else {
        current.write(char);
      }
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      continue;
    }
    if (char.trim().isEmpty) {
      if (current.isNotEmpty) {
        args.add(current.toString());
        current.clear();
      }
      continue;
    }
    current.write(char);
  }
  if (current.isNotEmpty) args.add(current.toString());
  return args;
}

String newCustomAcpId() =>
    '$customAcpIdPrefix${DateTime.now().microsecondsSinceEpoch}';

class CustomAcpStore {
  static Future<List<CustomAcpAgent>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return parseCustomAcpAgents(prefs.getString(customAcpPrefsKey));
  }

  static Future<void> save(List<CustomAcpAgent> agents) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(customAcpPrefsKey, encodeCustomAcpAgents(agents));
  }

  static Future<CustomAcpAgent?> find(String id) async {
    for (final agent in await load()) {
      if (agent.id == id) return agent;
    }
    return null;
  }

  static Future<void> upsert(CustomAcpAgent agent) async {
    final agents = await load();
    final index = agents.indexWhere((item) => item.id == agent.id);
    if (index >= 0) {
      agents[index] = agent;
    } else {
      agents.add(agent);
    }
    await save(agents);
  }

  static Future<void> remove(String id) async {
    final agents = await load();
    agents.removeWhere((agent) => agent.id == id);
    await save(agents);
  }
}

GatewayInfo applyCustomAcpAgent(GatewayInfo gateway, CustomAcpAgent agent) {
  return gateway.copyWith(
    agentId: agent.id,
    agentLabel: agent.name,
    command: agent.command,
    args: agent.args,
  );
}
