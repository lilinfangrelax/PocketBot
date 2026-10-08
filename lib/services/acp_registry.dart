import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pocketbot_remote/pocketbot_remote.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pocket_bot/models/message.dart';

const acpRegistryUrl =
    'https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json';

const acpRegistryCacheKey = 'acp_registry_json';

class RegistryBinary {
  final String archive;
  final String cmd;
  final List<String> args;
  final Map<String, String> env;
  final String? sha256;

  const RegistryBinary({
    required this.archive,
    required this.cmd,
    this.args = const [],
    this.env = const {},
    this.sha256,
  });
}

class RegistryPackage {
  final String package;
  final String? cmd;
  final List<String> args;
  final Map<String, String> env;

  const RegistryPackage({
    required this.package,
    this.cmd,
    this.args = const [],
    this.env = const {},
  });
}

class PreparedLaunch {
  final String command;
  final List<String> args;
  final String? archiveUrl;
  final String? sha256;
  final String? relativeCommand;
  final Map<String, String> env;
  final List<String> legacyArgv;

  const PreparedLaunch({
    required this.command,
    required this.args,
    this.archiveUrl,
    this.sha256,
    this.relativeCommand,
    this.env = const {},
    this.legacyArgv = const [],
  });
}

class AcpRegistryAgent {
  final String id;
  final String name;
  final String version;
  final String description;
  final Map<String, RegistryBinary> binaries;
  final RegistryPackage? npx;
  final RegistryPackage? uvx;

  const AcpRegistryAgent({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    this.binaries = const {},
    this.npx,
    this.uvx,
  });

  String get distributionLabel {
    final kinds = <String>[
      if (binaries.isNotEmpty) 'binary',
      if (npx != null) 'npx',
      if (uvx != null) 'uvx',
    ];
    return kinds.join(' / ');
  }

  PreparedLaunch? launchFor(RemotePlatform platform) {
    final binary = binaries[platform.registryKey];
    if (binary != null) {
      return PreparedLaunch(
        command: binary.cmd,
        args: binary.args,
        archiveUrl: binary.archive,
        sha256: binary.sha256,
        relativeCommand: binary.cmd,
        env: binary.env,
        legacyArgv: id == 'cursor' ? const ['agent', 'acp'] : const [],
      );
    }
    final node = npx;
    if (node != null) {
      return PreparedLaunch(
        command: 'npx',
        args: _packageArgs(node, runner: 'npx'),
        env: node.env,
      );
    }
    final python = uvx;
    if (python != null) {
      return PreparedLaunch(
        command: 'uvx',
        args: _packageArgs(python, runner: 'uvx'),
        env: python.env,
      );
    }
    return null;
  }

  List<String> _packageArgs(RegistryPackage spec, {required String runner}) {
    if (spec.cmd == null || spec.cmd!.isEmpty) {
      if (runner == 'npx') return ['-y', spec.package, ...spec.args];
      return [spec.package, ...spec.args];
    }
    if (runner == 'npx') {
      return ['--package', spec.package, '-y', spec.cmd!, ...spec.args];
    }
    return ['--from', spec.package, spec.cmd!, ...spec.args];
  }
}

List<AcpRegistryAgent> parseAcpRegistry(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map) return const [];
  final rawAgents = decoded['agents'];
  if (rawAgents is! List) return const [];
  final agents = <AcpRegistryAgent>[];
  for (final item in rawAgents) {
    if (item is! Map) continue;
    final id = item['id'] as String? ?? '';
    final name = item['name'] as String? ?? '';
    if (id.isEmpty || name.isEmpty) continue;
    final distribution = item['distribution'];
    final dist = distribution is Map ? distribution : const {};
    agents.add(AcpRegistryAgent(
      id: id,
      name: name,
      version: item['version'] as String? ?? '',
      description: item['description'] as String? ?? '',
      binaries: _binaries(dist['binary']),
      npx: _package(dist['npx']),
      uvx: _package(dist['uvx']),
    ));
  }
  agents.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return agents;
}

Map<String, RegistryBinary> _binaries(dynamic raw) {
  if (raw is! Map) return const {};
  final result = <String, RegistryBinary>{};
  raw.forEach((key, value) {
    if (value is! Map) return;
    final archive = value['archive'] as String? ?? '';
    final cmd = value['cmd'] as String? ?? '';
    if (archive.isEmpty || cmd.isEmpty) return;
    result['$key'] = RegistryBinary(
      archive: archive,
      cmd: cmd,
      args: _stringList(value['args']),
      env: _stringMap(value['env']),
      sha256: value['sha256'] as String?,
    );
  });
  return result;
}

RegistryPackage? _package(dynamic raw) {
  if (raw is! Map) return null;
  final package = raw['package'] as String? ?? '';
  if (package.isEmpty) return null;
  final cmd = raw['cmd'] as String?;
  return RegistryPackage(
    package: package,
    cmd: cmd == null || cmd.isEmpty ? null : cmd,
    args: _stringList(raw['args']),
    env: _stringMap(raw['env']),
  );
}

List<String> _stringList(dynamic raw) {
  if (raw is! List) return const [];
  return raw.map((item) => item.toString()).toList();
}

Map<String, String> _stringMap(dynamic raw) {
  if (raw is! Map) return const {};
  return raw.map((key, value) => MapEntry('$key', '$value'));
}

class AcpRegistryCatalog {
  static Future<List<AcpRegistryAgent>> load({http.Client? client}) async {
    final httpClient = client ?? http.Client();
    try {
      final response = await httpClient
          .get(Uri.parse(acpRegistryUrl))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(acpRegistryCacheKey, response.body);
        return parseAcpRegistry(response.body);
      }
    } catch (_) {
      // Fall through to the last cached catalog.
    } finally {
      if (client == null) httpClient.close();
    }
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(acpRegistryCacheKey);
    if (cached != null && cached.isNotEmpty) return parseAcpRegistry(cached);
    throw Exception('REGISTRY_UNAVAILABLE:无法获取 ACP Registry');
  }
}

Future<GatewayInfo> prepareGatewayLaunch(
  GatewayInfo gateway,
  RemotePlatform platform, {
  Future<List<AcpRegistryAgent>> Function()? loadAgents,
}) async {
  if (gateway.agentId.isEmpty) return gateway;
  List<AcpRegistryAgent> agents;
  try {
    agents = await (loadAgents ?? AcpRegistryCatalog.load)();
  } catch (error) {
    if (gateway.agentId == 'cursor') return gateway;
    rethrow;
  }
  AcpRegistryAgent? agent;
  for (final item in agents) {
    if (item.id == gateway.agentId) {
      agent = item;
      break;
    }
  }
  if (agent == null) {
    if (gateway.agentId == 'cursor') return gateway;
    throw Exception('AGENT_NOT_IN_REGISTRY:Registry 里没有 ${gateway.agentId}');
  }
  final launch = agent.launchFor(platform);
  if (launch == null) {
    if (gateway.agentId == 'cursor') return gateway;
    throw Exception(
      'AGENT_UNSUPPORTED_PLATFORM:${agent.name} 没有 ${platform.label} 的安装方式',
    );
  }
  return gateway.copyWith(
    command: launch.command,
    args: launch.args,
    agentLabel: agent.name,
    agentVersion: agent.version,
    archiveUrl: launch.archiveUrl,
    archiveSha256: launch.sha256,
    launchEnv: launch.env,
    legacyArgv: launch.legacyArgv,
  );
}
