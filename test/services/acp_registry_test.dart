import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_bot/models/message.dart';
import 'package:pocket_bot/services/acp_registry.dart';
import 'package:pocketbot_remote/pocketbot_remote.dart';

void main() {
  const registry = '''
  {
    "version": "1.0.0",
    "agents": [
      {
        "id": "cursor",
        "name": "Cursor",
        "version": "2026.10.01",
        "description": "Cursor agent",
        "distribution": {
          "binary": {
            "linux-x86_64": {
              "archive": "https://example.com/cursor.tar.gz",
              "cmd": "./dist-package/cursor-agent",
              "args": ["acp"]
            }
          }
        }
      },
      {
        "id": "gemini",
        "name": "Gemini CLI",
        "version": "0.63.0",
        "description": "Google Gemini",
        "distribution": {
          "npx": {
            "package": "@google/gemini-cli@0.63.0",
            "args": ["--acp"]
          }
        }
      },
      {
        "id": "fast-agent",
        "name": "fast-agent",
        "version": "0.10.1",
        "description": "Python agent",
        "distribution": {
          "uvx": {
            "package": "fast-agent-acp==0.10.1",
            "cmd": "fast-agent",
            "args": ["-x"],
            "env": {"FAST_AGENT_MODEL": "codexplan"}
          }
        }
      }
    ]
  }
  ''';

  test('parses binary, npx, and uvx registry entries', () {
    final agents = parseAcpRegistry(registry);
    expect(agents.map((agent) => agent.id), ['cursor', 'fast-agent', 'gemini']);

    final cursor = agents.first.launchFor(
      const RemotePlatform(os: 'linux', arch: 'x86_64'),
    );
    expect(cursor?.archiveUrl, 'https://example.com/cursor.tar.gz');
    expect(cursor?.relativeCommand, './dist-package/cursor-agent');
    expect(cursor?.args, ['acp']);
    expect(cursor?.legacyArgv, ['agent', 'acp']);
    expect(
      agents.first.launchFor(const RemotePlatform(os: 'windows', arch: 'aarch64')),
      isNull,
    );

    final gemini = agents.last.launchFor(
      const RemotePlatform(os: 'darwin', arch: 'aarch64'),
    );
    expect(gemini?.command, 'npx');
    expect(gemini?.args, ['-y', '@google/gemini-cli@0.63.0', '--acp']);

    final python = agents[1].launchFor(
      const RemotePlatform(os: 'linux', arch: 'aarch64'),
    );
    expect(python?.command, 'uvx');
    expect(python?.args, ['--from', 'fast-agent-acp==0.10.1', 'fast-agent', '-x']);
    expect(python?.env['FAST_AGENT_MODEL'], 'codexplan');
  });

  test('prepareGatewayLaunch keeps a legacy cursor command when registry misses it', () async {
    final gateway = GatewayInfo.local(agentId: 'cursor');
    final prepared = await prepareGatewayLaunch(
      gateway,
      const RemotePlatform(os: 'windows', arch: 'aarch64'),
      loadAgents: () async => parseAcpRegistry(registry),
    );
    expect(prepared.command, 'agent');
    expect(prepared.archiveUrl, isNull);
  });

  test('prepareGatewayLaunch copies the registry command onto the gateway', () async {
    final gateway = GatewayInfo.ssh(
      host: '10.0.0.8',
      username: 'me',
      agentId: 'gemini',
    );
    final prepared = await prepareGatewayLaunch(
      gateway,
      const RemotePlatform(os: 'linux', arch: 'x86_64'),
      loadAgents: () async => parseAcpRegistry(registry),
    );
    expect(prepared.command, 'npx');
    expect(prepared.args, contains('--acp'));
    expect(prepared.agentLabel, 'Gemini CLI');
    expect(prepared.toJson()['agentId'], 'gemini');
    expect(prepared.toJson().containsKey('archiveUrl'), isFalse);
    expect(prepared.toJson().containsKey('resumeAgent'), isFalse);
  });

  test('prefers a binary distribution and keeps runtime fields out of json', () {
    final agents = parseAcpRegistry('''
    {
      "agents": [
        {
          "id": "kilo",
          "name": "Kilo",
          "version": "1.2.0",
          "distribution": {
            "binary": {
              "linux-x86_64": {
                "archive": "https://example.com/kilo.tar.gz",
                "cmd": "./kilo",
                "args": ["acp"],
                "sha256": "abc",
                "env": {"KILO_HOME": "/opt/kilo"}
              }
            },
            "npx": {"package": "kilo", "cmd": "kilo", "args": ["acp"]}
          }
        },
        {"name": "missing-id"}
      ]
    }
    ''');
    expect(agents, hasLength(1));
    final launch = agents.single.launchFor(
      const RemotePlatform(os: 'linux', arch: 'x86_64'),
    );
    expect(launch?.archiveUrl, 'https://example.com/kilo.tar.gz');
    expect(launch?.sha256, 'abc');
    expect(launch?.env['KILO_HOME'], '/opt/kilo');
    expect(launch?.command, './kilo');
    expect(launch?.legacyArgv, isEmpty);

    final saved = GatewayInfo.local(agentId: 'kilo', agentLabel: 'Kilo').copyWith(
      archiveUrl: launch?.archiveUrl,
      resumeAgent: true,
    );
    final json = saved.toJson();
    expect(json['agentId'], 'kilo');
    expect(json['agentLabel'], 'Kilo');
    expect(json.containsKey('archiveUrl'), isFalse);
    final restored = GatewayInfo.fromJson(json);
    expect(restored.agentId, 'kilo');
    expect(restored.archiveUrl, isNull);
    expect(restored.resumeAgent, isFalse);
  });

  test('prepareGatewayLaunch reports a missing or unsupported agent', () async {
    const platform = RemotePlatform(os: 'linux', arch: 'aarch64');
    final unchanged = GatewayInfo.ssh(
      host: '10.0.0.8',
      username: 'me',
      command: 'custom',
    );
    expect(
      await prepareGatewayLaunch(
        unchanged,
        platform,
        loadAgents: () async => throw StateError('should not load'),
      ),
      same(unchanged),
    );

    await expectLater(
      prepareGatewayLaunch(
        GatewayInfo.local(agentId: 'missing'),
        platform,
        loadAgents: () async => parseAcpRegistry(registry),
      ),
      throwsA(predicate((error) => '$error'.contains('AGENT_NOT_IN_REGISTRY'))),
    );
    await expectLater(
      prepareGatewayLaunch(
        GatewayInfo.local(agentId: 'gemini'),
        platform,
        loadAgents: () async => throw Exception('REGISTRY_UNAVAILABLE:offline'),
      ),
      throwsA(predicate((error) => '$error'.contains('REGISTRY_UNAVAILABLE'))),
    );
    expect(
      await prepareGatewayLaunch(
        GatewayInfo.local(agentId: 'cursor', command: 'agent'),
        platform,
        loadAgents: () async => throw Exception('REGISTRY_UNAVAILABLE:offline'),
      ),
      predicate<GatewayInfo>((gateway) => gateway.command == 'agent' && gateway.archiveUrl == null),
    );
  });
}
