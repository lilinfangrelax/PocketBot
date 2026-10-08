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
  });
}
