import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_bot/models/message.dart';
import 'package:pocket_bot/services/custom_acp.dart';

void main() {
  test('parses and encodes saved custom agents', () {
    const raw = '''
    [
      {"id": "custom:1", "name": "Teshi", "command": "teshi", "args": ["acp"]},
      {"name": "missing-command"},
      {"command": "my-agent", "args": ["--flag", "value"]}
    ]
    ''';
    final agents = parseCustomAcpAgents(raw);
    expect(agents, hasLength(2));
    expect(agents.first.commandLine, 'teshi acp');
    expect(agents.last.name, 'my-agent');
    expect(isCustomAcpId(agents.last.id), isTrue);

    final restored = parseCustomAcpAgents(encodeCustomAcpAgents(agents));
    expect(restored.first.id, 'custom:1');
    expect(restored.last.args, ['--flag', 'value']);
    expect(parseCustomAcpAgents(''), isEmpty);
    expect(parseCustomAcpAgents('{}'), isEmpty);
  });

  test('splits arguments and keeps quoted text together', () {
    expect(splitAcpArgs('acp --model gpt'), ['acp', '--model', 'gpt']);
    expect(splitAcpArgs(''), isEmpty);
    expect(
      splitAcpArgs('acp --cwd "C:\\Program Files\\app"'),
      ['acp', '--cwd', r'C:\Program Files\app'],
    );
  });

  test('applies the custom command over the default agent argv', () {
    final gateway = applyCustomAcpAgent(
      GatewayInfo.local(agentId: 'custom:1'),
      const CustomAcpAgent(
        id: 'custom:1',
        name: 'Teshi',
        command: r'C:\Tools\teshi.exe',
        args: [],
      ),
    );
    expect(gateway.command, r'C:\Tools\teshi.exe');
    expect(gateway.args, isEmpty);
    expect(gateway.agentLabel, 'Teshi');
  });
}
