import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;
import 'package:pocket_bot/services/acp_transport.dart';

class AcpFileNotFound implements Exception {
  AcpFileNotFound(this.path);

  final String path;

  @override
  String toString() => 'File not found: $path';
}

/// Backs the ACP `fs/*` client methods on the machine where the agent runs.
abstract class AcpFileSystem {
  String resolve(String path, String workingDirectory);

  Future<String> readText(String path);

  Future<void> writeText(String path, String content);
}

class LocalAcpFileSystem implements AcpFileSystem {
  const LocalAcpFileSystem();

  @override
  String resolve(String path, String workingDirectory) {
    if (path.isEmpty) return workingDirectory;
    if (p.isAbsolute(path)) return p.normalize(path);
    return p.normalize(p.join(workingDirectory, path));
  }

  @override
  Future<String> readText(String path) async {
    final file = File(path);
    if (!await file.exists()) throw AcpFileNotFound(path);
    return file.readAsString();
  }

  @override
  Future<void> writeText(String path, String content) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }
}

/// Reads and writes files on the SSH host, not on this device.
class SftpAcpFileSystem implements AcpFileSystem {
  SftpAcpFileSystem(this._client);

  final SSHClient _client;
  SftpClient? _sftp;

  Future<SftpClient> _ensureSftp() async => _sftp ??= await _client.sftp();

  @override
  String resolve(String path, String workingDirectory) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return workingDirectory;
    if (trimmed.startsWith('/') || looksLikeWindowsPath(trimmed)) {
      return trimmed;
    }
    var resolved = workingDirectory;
    for (final part in trimmed.split(RegExp(r'[\\/]+'))) {
      resolved = joinRemotePath(resolved, part);
    }
    return resolved;
  }

  @override
  Future<String> readText(String path) async {
    final sftp = await _ensureSftp();
    SftpFile file;
    try {
      file = await sftp.open(toSftpPath(path));
    } on SftpStatusError catch (error) {
      if (error.code == SftpStatusCode.noSuchFile) throw AcpFileNotFound(path);
      rethrow;
    }
    try {
      return utf8.decode(await file.readBytes(), allowMalformed: true);
    } finally {
      await file.close();
    }
  }

  @override
  Future<void> writeText(String path, String content) async {
    final sftp = await _ensureSftp();
    await _createParents(sftp, path);
    final file = await sftp.open(
      toSftpPath(path),
      mode: SftpFileOpenMode.create |
          SftpFileOpenMode.truncate |
          SftpFileOpenMode.write,
    );
    try {
      await file.writeBytes(Uint8List.fromList(utf8.encode(content)));
    } finally {
      await file.close();
    }
  }

  Future<void> _createParents(SftpClient sftp, String path) async {
    final missing = <String>[];
    var dir = parentRemotePath(path);
    while (!isRemoteRoot(dir) && missing.length < 64) {
      try {
        await sftp.stat(toSftpPath(dir));
        break;
      } on SftpStatusError catch (error) {
        if (error.code != SftpStatusCode.noSuchFile) rethrow;
        missing.add(dir);
        dir = parentRemotePath(dir);
      }
    }
    for (final item in missing.reversed) {
      await sftp.mkdir(toSftpPath(item));
    }
  }
}
