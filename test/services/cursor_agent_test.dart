import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_bot/services/cursor_agent.dart';

void main() {
  test('picks the newest Cursor agent version directory', () {
    expect(CursorAgent.versionSortKey('2026.8.25-3e8eec8'), 20260825);
    expect(CursorAgent.versionSortKey('2026.07.09-a3815c0'), 20260709);
    expect(
      CursorAgent.versionSortKey('2026.08.25-12-00-00-abc'),
      20260825,
    );
  });

  test('unwraps agent.cmd to node.exe plus index.js', () async {
    final root = await Directory.systemTemp.createTemp('cursor-agent-');
    addTearDown(() => root.delete(recursive: true));

    final version = Directory('${root.path}${Platform.pathSeparator}versions${Platform.pathSeparator}2026.08.25-3e8eec8');
    await version.create(recursive: true);
    await File('${version.path}${Platform.pathSeparator}node.exe').writeAsString('');
    await File('${version.path}${Platform.pathSeparator}index.js').writeAsString('');

    final resolved = CursorAgent.resolveFromInstallDir(root.path);
    expect(resolved, isNotNull);
    expect(resolved!.executable, endsWith('node.exe'));
    expect(resolved.prefixArgs.single, endsWith('index.js'));
    expect(resolved.runInShell, isFalse);
  });

  test('picks the latest version directory and ignores other folders',
      () async {
    final root = await Directory.systemTemp.createTemp('cursor-versions-');
    addTearDown(() => root.delete(recursive: true));
    for (final name in const [
      '2026.7.9-a3815c0',
      '2026.10.1-abcdef0',
      '2026.8.25-3e8eec8',
      'backup',
      '2026.10.2',
    ]) {
      await Directory('${root.path}${Platform.pathSeparator}$name')
          .create(recursive: true);
    }

    final latest = CursorAgent.pickLatestVersionDirectory(root);
    expect(latest, isNotNull);
    expect(latest!.path, endsWith('2026.10.1-abcdef0'));
    expect(
      CursorAgent.pickLatestVersionDirectory(
        Directory('${root.path}${Platform.pathSeparator}missing'),
      ),
      isNull,
    );
  });

  test('uses the home folder for an empty or root working directory', () {
    expect(CursorAgent.resolveWorkingDirectory(''), isNotEmpty);
    expect(CursorAgent.resolveWorkingDirectory('/'), isNotEmpty);
    expect(CursorAgent.resolveWorkingDirectory(' /srv/repo '), '/srv/repo');
  });

  test('wraps PowerShell and cmd agents when node is absent', () async {
    final root = await Directory.systemTemp.createTemp('cursor-scripts-');
    addTearDown(() => root.delete(recursive: true));

    final ps1 = File('${root.path}${Platform.pathSeparator}agent.ps1');
    await ps1.writeAsString('');
    final resolvedPs = await CursorAgent.resolve(ps1.path);
    expect(
      resolvedPs.executable,
      Platform.isWindows ? 'powershell.exe' : 'pwsh',
    );
    expect(resolvedPs.prefixArgs, contains('-File'));

    final cmd = File('${root.path}${Platform.pathSeparator}agent.cmd');
    await cmd.writeAsString('');
    final resolvedCmd = await CursorAgent.resolve(cmd.path);
    expect(resolvedCmd.executable, cmd.path);
    expect(resolvedCmd.runInShell, isTrue);
  });

  test('keeps an explicit executable path', () async {
    final root = await Directory.systemTemp.createTemp('cursor-explicit-');
    addTearDown(() => root.delete(recursive: true));
    final path = '${root.path}${Platform.pathSeparator}agent.exe';

    final resolved = await CursorAgent.resolve(path);
    expect(resolved.executable, path);
    expect(resolved.prefixArgs, isEmpty);
    expect(resolved.runInShell, isFalse);
  });
}
