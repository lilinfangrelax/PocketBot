import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pocket_bot/utils/logger.dart';

class ResolvedAgent {
  final String executable;
  final List<String> prefixArgs;
  final bool runInShell;

  const ResolvedAgent({
    required this.executable,
    this.prefixArgs = const [],
    this.runInShell = false,
  });
}

/// Locates the Cursor CLI agent (`agent acp`) on this machine.
class CursorAgent {
  static const defaultCommand = 'agent';
  static const defaultArgs = ['acp'];
  static final _versionDirPattern =
      RegExp(r'^\d{4}\.\d{1,2}\.\d{1,2}(-\d{2}-\d{2}-\d{2})?-[a-f0-9]+$');

  static String defaultWorkingDirectory() {
    return Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.current.path;
  }

  static String resolveWorkingDirectory(String cwd) {
    final trimmed = cwd.trim();
    if (trimmed.isEmpty || trimmed == '/') {
      return defaultWorkingDirectory();
    }
    return trimmed;
  }

  static Future<ResolvedAgent> resolve([String command = defaultCommand]) async {
    if (_looksLikePath(command)) {
      return _fromPath(command);
    }

    final fromPath = await _which(command);
    if (fromPath != null) {
      return _fromPath(fromPath);
    }

    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData != null && localAppData.isNotEmpty) {
      final installDir = '$localAppData${Platform.pathSeparator}cursor-agent';
      final fromInstall = resolveFromInstallDir(installDir);
      if (fromInstall != null) return fromInstall;

      final candidates = [
        '$installDir${Platform.pathSeparator}agent.cmd',
        '$installDir${Platform.pathSeparator}agent.ps1',
        '$installDir${Platform.pathSeparator}cursor-agent.cmd',
        '$installDir${Platform.pathSeparator}cursor-agent.ps1',
      ];
      for (final path in candidates) {
        if (File(path).existsSync()) {
          Logger.info('[ACP] Using Cursor Agent at $path');
          return _fromPath(path);
        }
      }
    }

    throw Exception(
      'CURSOR_AGENT_NOT_FOUND:找不到 Cursor Agent（agent）。请先安装 Cursor 并运行 agent login。',
    );
  }

  /// Prefer the real `node.exe` + `index.js` so ACP stdio is not wrapped by
  /// `agent.cmd` / PowerShell (those break stdin piping on Windows).
  @visibleForTesting
  static ResolvedAgent? resolveFromInstallDir(String installDir) {
    final nodeInRoot = File('$installDir${Platform.pathSeparator}node.exe');
    final indexInRoot = File('$installDir${Platform.pathSeparator}index.js');
    if (nodeInRoot.existsSync() && indexInRoot.existsSync()) {
      Logger.info('[ACP] Using Cursor Agent at ${nodeInRoot.path}');
      return ResolvedAgent(
        executable: nodeInRoot.path,
        prefixArgs: [indexInRoot.path],
      );
    }

    final versionsDir = Directory('$installDir${Platform.pathSeparator}versions');
    final latest = pickLatestVersionDirectory(versionsDir);
    if (latest == null) return null;
    final node = File('${latest.path}${Platform.pathSeparator}node.exe');
    final index = File('${latest.path}${Platform.pathSeparator}index.js');
    if (!node.existsSync() || !index.existsSync()) return null;
    Logger.info('[ACP] Using Cursor Agent ${latest.path}');
    return ResolvedAgent(
      executable: node.path,
      prefixArgs: [index.path],
    );
  }

  @visibleForTesting
  static Directory? pickLatestVersionDirectory(Directory versionsDir) {
    if (!versionsDir.existsSync()) return null;
    final dirs = versionsDir
        .listSync()
        .whereType<Directory>()
        .where((dir) => _versionDirPattern.hasMatch(_basename(dir.path)))
        .toList()
      ..sort((a, b) {
        final byKey = (versionSortKey(_basename(a.path)) ?? 0)
            .compareTo(versionSortKey(_basename(b.path)) ?? 0);
        if (byKey != 0) return byKey;
        return _basename(a.path).compareTo(_basename(b.path));
      });
    return dirs.isEmpty ? null : dirs.last;
  }

  @visibleForTesting
  static int? versionSortKey(String name) {
    final datePart = name.split('-').first;
    final parts = datePart.split('.');
    if (parts.length != 3) return null;
    final year = parts[0];
    final month = parts[1].padLeft(2, '0');
    final day = parts[2].padLeft(2, '0');
    return int.tryParse('$year$month$day');
  }

  static bool _looksLikePath(String command) {
    return command.contains('\\') ||
        command.contains('/') ||
        command.endsWith('.cmd') ||
        command.endsWith('.ps1') ||
        command.endsWith('.bat') ||
        command.endsWith('.exe');
  }

  static ResolvedAgent _fromPath(String path) {
    final file = File(path);
    final installDir = file.parent.path;
    final unwrapped = resolveFromInstallDir(installDir);
    if (unwrapped != null) return unwrapped;

    final inVersionDir = resolveFromInstallDir(file.parent.parent.path);
    if (inVersionDir != null && _basename(file.parent.path) != 'cursor-agent') {
      final siblingNode = File('$installDir${Platform.pathSeparator}node.exe');
      if (siblingNode.existsSync()) {
        return resolveFromInstallDir(installDir) ?? inVersionDir;
      }
    }

    final lower = path.toLowerCase();
    if (lower.endsWith('.ps1')) {
      return ResolvedAgent(
        executable: Platform.isWindows ? 'powershell.exe' : 'pwsh',
        prefixArgs: [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          path,
        ],
      );
    }
    if (lower.endsWith('.cmd') || lower.endsWith('.bat')) {
      // Last resort: cmd wrapping still breaks ACP stdin. Prefer node unwrap.
      return ResolvedAgent(executable: path, runInShell: true);
    }
    return ResolvedAgent(executable: path);
  }

  static String _basename(String path) {
    return path.split(RegExp(r'[\\/]')).last;
  }

  static Future<String?> _which(String command) async {
    try {
      final result = await Process.run(
        Platform.isWindows ? 'where' : 'which',
        [command],
        runInShell: true,
      );
      if (result.exitCode != 0) return null;
      final stdout = result.stdout.toString().trim();
      if (stdout.isEmpty) return null;
      final line = stdout.split(RegExp(r'\r?\n')).first.trim();
      return line.isEmpty ? null : line;
    } catch (error) {
      Logger.warning('[ACP] Failed to resolve $command on PATH: $error');
      return null;
    }
  }
}
