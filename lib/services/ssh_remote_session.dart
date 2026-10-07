import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:pocket_bot/models/message.dart';
import 'package:pocket_bot/services/acp_transport.dart';
import 'package:pocket_bot/utils/logger.dart';

/// Turns a dropped Tailscale/SSH socket into a short message.
String friendlyDirectoryError(Object error) {
  final text = error.toString().replaceFirst('Exception: ', '');
  final lower = text.toLowerCase();
  if (lower.contains('连接已中断') ||
      lower.contains('sshsocketerror') ||
      lower.contains('connection abort') ||
      lower.contains('connection reset') ||
      lower.contains('broken pipe')) {
    return 'SSH 连接已中断，请返回后重新登录';
  }
  if (text.startsWith('无法列出目录')) return text;
  return '无法列出目录: $text';
}

bool isSshSocketFailure(Object error) {
  final lower = error.toString().toLowerCase();
  return lower.contains('sshsocketerror') ||
      lower.contains('connection abort') ||
      lower.contains('connection reset') ||
      lower.contains('broken pipe') ||
      lower.contains('connection closed') ||
      lower.contains('errno = 103') ||
      lower.contains('errno = 104');
}

class SshRemoteEntry {
  final String name;
  final bool isDirectory;

  const SshRemoteEntry({
    required this.name,
    required this.isDirectory,
  });
}

/// Lists remote directories after SSH login, before ACP is started.
abstract class RemoteDirectorySource {
  Future<String> resolveStartPath(String preferred);

  Future<List<SshRemoteEntry>> listDirectory(String path);
}

/// SSH login plus SFTP (or shell) directory listing. The same [SSHClient]
/// is later reused to spawn `agent acp` in the chosen working directory.
class SshRemoteSession implements RemoteDirectorySource {
  SshRemoteSession._(this._client, this._target);

  SSHClient? _client;
  SftpClient? _sftp;
  final GatewayInfo _target;
  bool _ownsClient = true;

  SSHClient get client {
    final value = _client;
    if (value == null) {
      throw Exception('CONNECTION_CLOSED:SSH 连接已关闭');
    }
    return value;
  }

  static Future<SshRemoteSession> connect(GatewayInfo target) async {
    final client = await openSshClient(target);
    return SshRemoteSession._(client, target);
  }

  @override
  Future<String> resolveStartPath(String preferred) async {
    final home = await _homeDirectory();
    final candidate = preferred.trim();
    if (candidate.isEmpty || candidate == '.') {
      return home;
    }
    try {
      await listDirectory(candidate);
      return candidate;
    } catch (_) {
      return home;
    }
  }

  Future<String> _homeDirectory() async {
    try {
      final sftp = await _ensureSftp();
      final home = await sftp.absolute('.');
      if (home.trim().isNotEmpty) return home;
    } catch (error) {
      Logger.debug('[SSH] SFTP home lookup failed: $error');
    }
    try {
      final output = utf8.decode(await client.run('pwd')).trim();
      if (output.isNotEmpty) return output.split('\n').first.trim();
    } catch (_) {}
    try {
      final output =
          utf8.decode(await client.run('echo %USERPROFILE%')).trim();
      if (output.isNotEmpty && !output.contains('%USERPROFILE%')) {
        return output.split('\n').first.trim();
      }
    } catch (_) {}
    return '.';
  }

  @override
  Future<List<SshRemoteEntry>> listDirectory(String path) async {
    try {
      return await _listViaSftp(path);
    } catch (error) {
      Logger.debug('[SSH] SFTP listdir failed for $path: $error');
      _sftp = null;
      if (isSshSocketFailure(error)) {
        if (!await _reconnect()) {
          throw Exception('SSH 连接已中断，请返回后重新登录');
        }
        try {
          return await _listViaSftp(path);
        } catch (retry) {
          Logger.debug('[SSH] SFTP listdir retry failed for $path: $retry');
          _sftp = null;
          if (isSshSocketFailure(retry)) {
            throw Exception('SSH 连接已中断，请返回后重新登录');
          }
          return _listViaShell(path);
        }
      }
      return _listViaShell(path);
    }
  }

  Future<List<SshRemoteEntry>> _listViaSftp(String path) async {
    final sftp = await _ensureSftp();
    final items = await sftp.listdir(toSftpPath(path));
    final entries = <SshRemoteEntry>[];
    for (final item in items) {
      final name = item.filename;
      if (name.isEmpty || name == '.' || name == '..') continue;
      if (item.attr.isFile) continue;
      entries.add(SshRemoteEntry(name: name, isDirectory: true));
    }
    entries.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return entries;
  }

  Future<List<SshRemoteEntry>> _listViaShell(String path) async {
    final windows = opensshPathToWindows(path);
    if (looksLikeWindowsPath(windows)) {
      var dirPath = windows.replaceAll('"', '');
      if (RegExp(r'^[a-zA-Z]:\\$').hasMatch(dirPath)) {
        dirPath = dirPath.substring(0, 2);
      }
      final output = utf8.decode(
        await client.run('cmd /c "dir /b /ad $dirPath"'),
      );
      return _parseDir(output);
    }
    final quoted = shQuote(path);
    try {
      final output = utf8.decode(
        await client.run('ls -1A -p $quoted'),
      );
      return _parseLs(output);
    } catch (_) {}
    final escaped = path.replaceAll('"', '');
    final output = utf8.decode(
      await client.run('cmd /c "dir /b /ad $escaped"'),
    );
    return _parseDir(output);
  }

  List<SshRemoteEntry> _parseLs(String output) {
    final entries = <SshRemoteEntry>[];
    for (final raw in output.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line == '.' || line == '..') continue;
      final isDir = line.endsWith('/');
      if (!isDir) continue;
      entries.add(
        SshRemoteEntry(
          name: line.substring(0, line.length - 1),
          isDirectory: true,
        ),
      );
    }
    entries.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return entries;
  }

  List<SshRemoteEntry> _parseDir(String output) {
    final entries = <SshRemoteEntry>[];
    for (final raw in output.split('\n')) {
      final name = raw.trim();
      if (name.isEmpty || name == '.' || name == '..') continue;
      entries.add(SshRemoteEntry(name: name, isDirectory: true));
    }
    entries.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return entries;
  }

  Future<SftpClient> _ensureSftp() async {
    _sftp ??= await client.sftp();
    return _sftp!;
  }

  Future<bool> _reconnect() async {
    if (!_ownsClient) return false;
    try {
      _client?.close();
    } catch (_) {}
    _client = null;
    _sftp = null;
    try {
      _client = await openSshClient(_target);
      return true;
    } catch (error) {
      Logger.debug('[SSH] Reconnect failed: $error');
      return false;
    }
  }

  Future<SshStdioTransport> startAgent(GatewayInfo target) async {
    final transport = await SshStdioTransport.attach(
      client: client,
      target: target,
    );
    _ownsClient = false;
    return transport;
  }

  Future<void> close() async {
    _sftp = null;
    if (_ownsClient) {
      try {
        _client?.close();
      } catch (_) {}
    }
    _client = null;
  }
}
