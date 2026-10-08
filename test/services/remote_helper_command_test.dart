import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_bot/services/remote_helper.dart';
import 'package:pocketbot_remote/pocketbot_remote.dart';

void main() {
  const linux = RemotePlatform(os: 'linux', arch: 'x86_64');
  const windows = RemotePlatform(os: 'windows', arch: 'x86_64');

  test('probe and download commands keep the version and home variable', () {
    final probe = helperProbeCommand(linux, '1.2.5-beta');
    expect(probe, contains('pocketbot-remote-1.2.5-beta'));
    expect(probe, contains(r'$HOME'));
    expect(probe, contains('echo READY'));

    final download = helperRemoteDownloadCommand(
      platform: windows,
      version: '1.2.5-beta',
      url: 'https://example.com/pocketbot-remote-windows-x64.exe',
    );
    expect(download, contains('pocketbot-remote-1.2.5-beta.exe'));
    expect(download, contains(r'$env:USERPROFILE'));
    expect(download, contains('https://example.com/pocketbot-remote-windows-x64.exe'));
  });

  test('reads the READY path and installs by upload when the host is offline', () async {
    expect(readyHelperPath('noise\nREADY /home/me/.pocketbot/helper\n'),
        '/home/me/.pocketbot/helper');

    final commands = <String>[];
    final uploaded = <String, int>{};
    var probes = 0;
    final path = await ensureRemoteHelper(
      platform: linux,
      version: '1.2.5-beta',
      exec: (command) async {
        commands.add(command);
        if (command.contains('echo READY')) {
          probes += 1;
          if (probes < 3) return 'MISSING\n';
          return 'READY /home/me/.pocketbot/pocketbot-remote-1.2.5-beta\n';
        }
        if (command.contains('curl')) throw Exception('offline');
        if (command.startsWith('printf')) return '/home/me';
        return '';
      },
      upload: (remotePath, bytes) async {
        uploaded[remotePath] = bytes.length;
      },
      download: (_) async => [1, 2, 3, 4],
    );

    expect(path, '/home/me/.pocketbot/pocketbot-remote-1.2.5-beta');
    expect(uploaded['/home/me/.pocketbot/pocketbot-remote-1.2.5-beta'], 4);
    expect(commands.any((command) => command.contains('curl')), isTrue);
  });
}
