import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_bot/services/remote_helper.dart';
import 'package:pocketbot_remote/pocketbot_remote.dart';

/// Decodes `powershell -EncodedCommand` the way Windows PowerShell does.
String powershellScript(String command) {
  const marker = '-EncodedCommand ';
  final index = command.indexOf(marker);
  if (index < 0) return command;
  final bytes = base64Decode(command.substring(index + marker.length).trim());
  final data = ByteData.sublistView(bytes);
  final units = <int>[
    for (var i = 0; i < bytes.length; i += 2) data.getUint16(i, Endian.little),
  ];
  return String.fromCharCodes(units);
}

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
    expect(download, isNot(contains('"')));
    final script = powershellScript(download);
    expect(script, contains('pocketbot-remote-1.2.5-beta.exe'));
    expect(script, contains(r'$env:USERPROFILE'));
    expect(script,
        contains('https://example.com/pocketbot-remote-windows-x64.exe'));
  });

  test('windows probe has no quote cmd can turn into an open string', () {
    final command = helperProbeCommand(windows, '1.2.9-beta');
    expect(command,
        startsWith('powershell -NoProfile -NonInteractive -EncodedCommand '));
    expect(command, isNot(contains('"')));
    final script = powershellScript(command);
    expect(script, contains(r"$ver = ''"));
    expect(script, isNot(contains('""')));
    expect(script, contains(r'$env:USERPROFILE'));
    expect(script, contains('pocketbot-remote-1.2.9-beta.exe'));
    expect(script, contains("Write-Output 'MISSING'"));
  });

  test('maps an OpenSSH drive path before launching on Windows', () {
    expect(
      remoteLaunchDirectory(windows, '/d:/Dev/Rust/teshi/dev'),
      r'D:\Dev\Rust\teshi\dev',
    );
    expect(remoteLaunchDirectory(windows, r'D:\Dev\app'), r'D:\Dev\app');
    expect(remoteLaunchDirectory(windows, ''), '.');
    expect(remoteLaunchDirectory(linux, '/home/me/dev'), '/home/me/dev');
  });

  test('reads the READY path and installs by upload when the host is offline',
      () async {
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

  test('keeps an already installed helper and uploads the windows build',
      () async {
    var downloads = 0;
    final ready = await ensureRemoteHelper(
      platform: windows,
      version: '1.2.5-beta',
      exec: (command) async {
        final script = powershellScript(command);
        expect(script, contains(r'$env:USERPROFILE'));
        expect(script, contains('pocketbot-remote-1.2.5-beta.exe'));
        return r'READY C:\Users\me\.pocketbot\pocketbot-remote-1.2.5-beta.exe';
      },
      upload: (_, __) async => fail('should not upload'),
      download: (_) async {
        downloads += 1;
        return const [1];
      },
    );
    expect(downloads, 0);
    expect(ready, r'C:\Users\me\.pocketbot\pocketbot-remote-1.2.5-beta.exe');

    var probes = 0;
    String? uploadedTo;
    final installed = await ensureRemoteHelper(
      platform: windows,
      version: '1.2.5-beta',
      exec: (command) async {
        final script = powershellScript(command);
        if (script.contains('Write-Output')) {
          probes += 1;
          if (probes < 3) return 'MISSING';
          return r'READY C:\Users\me\.pocketbot\pocketbot-remote-1.2.5-beta.exe';
        }
        if (script.contains('Invoke-WebRequest')) throw Exception('offline');
        if (command.contains('%USERPROFILE%')) return r'C:\Users\me';
        return '';
      },
      upload: (remotePath, bytes) async {
        uploadedTo = remotePath;
        expect(bytes, [9, 8]);
      },
      download: (_) async => [9, 8],
    );
    expect(
        installed, r'C:\Users\me\.pocketbot\pocketbot-remote-1.2.5-beta.exe');
    expect(
        uploadedTo, r'C:\Users\me\.pocketbot\pocketbot-remote-1.2.5-beta.exe');
  });
}
