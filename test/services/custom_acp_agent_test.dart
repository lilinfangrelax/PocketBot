import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_bot/models/message.dart';
import 'package:pocket_bot/services/acp_registry.dart';
import 'package:pocket_bot/services/custom_acp_agent.dart';
import 'package:pocketbot_remote/pocketbot_remote.dart';

void main() {
  test('parses and validates a custom agent profile', () {
    final agents = parseCustomAcpAgents('''
    [
      {
        "id": "chrys",
        "name": "Chrys",
        "program": "chrys",
        "args": ["acp", "-a", "Code"],
        "env": {"CHRYS_HOME": "D:\\\\chrys"}
      },
      {"id": "bad id", "name": "Bad", "program": "x"}
    ]
    ''');
    expect(agents, hasLength(1));
    expect(agents.single.selectionId, 'custom:chrys');
    expect(agents.single.args, ['acp', '-a', 'Code']);
    expect(agents.single.env['CHRYS_HOME'], r'D:\chrys');
    expect(validateCustomAcpAgent(agents.single), isNull);
    expect(
      validateCustomAcpAgent(
        const CustomAcpAgent(id: 'has space', name: 'A', program: 'a'),
      ),
      isNotNull,
    );
  });

  test('arguments stay on their own lines', () {
    expect(parseCustomAcpArgs('acp\n-a Code\n'), ['acp', '-a Code']);
    expect(parseCustomAcpEnv('A=1\nB=x=y\n'), {'A': '1', 'B': 'x=y'});
    expect(() => parseCustomAcpEnv('missing'), throwsFormatException);
    expect(suggestCustomAcpId('Chrys ACP'), 'chrys-acp');
  });

  test('prepareGatewayLaunch uses the custom command and skips the registry',
      () async {
    const platform = RemotePlatform(os: 'windows', arch: 'x86_64');
    final prepared = await prepareGatewayLaunch(
      GatewayInfo.local(agentId: 'custom:chrys', agentLabel: 'old'),
      platform,
      loadAgents: () async => throw StateError('registry should not load'),
      loadCustomAgents: () async => const [
        CustomAcpAgent(
          id: 'chrys',
          name: 'Chrys',
          program: r'D:\dev\Python\chrys\.venv\Scripts\chrys.exe',
          args: ['acp'],
          env: {'CHRYS_PROFILE': 'Code'},
        ),
      ],
    );
    expect(prepared.command, r'D:\dev\Python\chrys\.venv\Scripts\chrys.exe');
    expect(prepared.args, ['acp']);
    expect(prepared.agentLabel, 'Chrys');
    expect(prepared.launchEnv['CHRYS_PROFILE'], 'Code');
    expect(prepared.archiveUrl, isEmpty);
    expect(prepared.legacyArgv, isEmpty);

    await expectLater(
      prepareGatewayLaunch(
        GatewayInfo.local(agentId: 'custom:missing'),
        platform,
        loadAgents: () async => throw StateError('registry should not load'),
        loadCustomAgents: () async => const [],
      ),
      throwsA(predicate((error) => '$error'.contains('CUSTOM_AGENT_MISSING'))),
    );
  });

  test('resolveCustomProgram accepts an existing executable path', () async {
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}pocketbot-custom-agent-test.exe',
    );
    await file.writeAsString('not-a-real-binary');
    addTearDown(() async {
      if (file.existsSync()) await file.delete();
    });
    final resolved = await resolveCustomProgram(file.path);
    expect(resolved.executable, file.path);
    expect(resolved.runInShell, isFalse);
    await expectLater(
      resolveCustomProgram('pocketbot-custom-agent-not-installed'),
      throwsA(
          predicate((error) => '$error'.contains('CUSTOM_AGENT_NOT_FOUND'))),
    );
  });
}
