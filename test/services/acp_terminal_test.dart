import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_bot/services/acp_terminal.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final shell = Platform.isWindows ? 'cmd' : 'sh';
  List<String> shellArgs(String script) =>
      Platform.isWindows ? ['/c', script] : ['-c', script];

  test('captures stdout and the exit code', () async {
    final host = LocalAcpTerminalHost();
    addTearDown(host.dispose);

    final terminal = await host.create(
      command: shell,
      args: shellArgs('echo terminal-ok'),
      environment: const {},
    );
    await terminal.exited.timeout(const Duration(seconds: 15));

    expect(terminal.hasExited, isTrue);
    expect(terminal.exitCode, 0);
    expect(terminal.signal, isNull);
    expect(terminal.truncated, isFalse);
    expect(terminal.output.trim(), 'terminal-ok');
  });

  test('applies the requested environment and working directory', () async {
    final host = LocalAcpTerminalHost();
    final directory = await Directory.systemTemp.createTemp('pocketbot_term');
    addTearDown(() async {
      await host.dispose();
      await directory.delete(recursive: true);
    });

    final script = Platform.isWindows
        ? 'echo %POCKETBOT_TERMINAL_ENV% && cd'
        : 'printf "%s\\n" "\$POCKETBOT_TERMINAL_ENV" && pwd';
    final terminal = await host.create(
      command: shell,
      args: shellArgs(script),
      environment: const {'POCKETBOT_TERMINAL_ENV': 'terminal-env-ok'},
      cwd: directory.path,
    );
    await terminal.exited.timeout(const Duration(seconds: 15));

    final output = terminal.output;
    expect(output, contains('terminal-env-ok'));
    final normalized = output.replaceAll('\\', '/').toLowerCase();
    final expected = directory.path.replaceAll('\\', '/').toLowerCase();
    expect(normalized, contains(expected));
  });

  test('keeps only the tail of the output when it exceeds the limit', () async {
    final host = LocalAcpTerminalHost();
    addTearDown(host.dispose);

    final terminal = await host.create(
      command: shell,
      args: shellArgs(
          Platform.isWindows ? 'echo 0123456789' : 'printf 0123456789'),
      environment: const {},
      outputByteLimit: 4,
    );
    await terminal.exited.timeout(const Duration(seconds: 15));

    expect(terminal.truncated, isTrue);
    expect(terminal.output.length, lessThanOrEqualTo(4));
    // The retained tail can include the line ending, so ignore it here.
    expect('0123456789', endsWith(terminal.output.trimRight()));
  });

  test('discards all output when the byte limit is zero', () async {
    final host = LocalAcpTerminalHost();
    addTearDown(host.dispose);

    final terminal = await host.create(
      command: shell,
      args: shellArgs('echo hidden'),
      environment: const {},
      outputByteLimit: 0,
    );
    await terminal.exited.timeout(const Duration(seconds: 15));

    expect(terminal.output, isEmpty);
    expect(terminal.truncated, isTrue);
  });

  test('kill ends a running command tree and settles exited', () async {
    final host = LocalAcpTerminalHost();
    addTearDown(host.dispose);

    final terminal = await host.create(
      command: shell,
      args: shellArgs(
        Platform.isWindows
            ? 'echo ready & ping -n 30 127.0.0.1 > nul'
            : 'printf ready; sleep 30',
      ),
      environment: const {},
    );
    // Wait until the shell has spawned the long-running child, otherwise the
    // test would only kill the shell and pass for the wrong reason.
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!terminal.output.contains('ready')) {
      if (DateTime.now().isAfter(deadline)) {
        fail('command did not start');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    await terminal.kill();
    await terminal.exited.timeout(const Duration(seconds: 5));
    expect(terminal.hasExited, isTrue);
  });

  test('release settles a running command and its exit future', () async {
    final host = LocalAcpTerminalHost();
    addTearDown(host.dispose);

    final terminal = await host.create(
      command: shell,
      args: shellArgs(
        Platform.isWindows ? 'ping -n 30 127.0.0.1 > nul' : 'sleep 30',
      ),
      environment: const {},
    );
    await terminal.release();
    await terminal.exited.timeout(const Duration(seconds: 10));
    expect(terminal.hasExited, isTrue);
  });
}
