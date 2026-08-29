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
}
