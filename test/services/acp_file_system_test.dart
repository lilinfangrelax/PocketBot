import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_bot/services/acp_file_system.dart';

void main() {
  group('SftpAcpFileSystem.resolve', () {
    late SftpAcpFileSystem fs;

    setUp(() {
      fs = SftpAcpFileSystem(_UnusedClient());
    });

    test('keeps absolute POSIX paths', () {
      expect(fs.resolve('/etc/hosts', '/home/me'), '/etc/hosts');
    });

    test('joins relative paths onto the remote working directory', () {
      expect(fs.resolve('lib/main.dart', '/home/me/app'),
          '/home/me/app/lib/main.dart');
      expect(fs.resolve('../x', '/home/me/app'), '/home/me/x');
    });

    test('keeps Windows drive paths and joins with backslashes', () {
      expect(fs.resolve(r'C:\repo\a.txt', r'C:\repo'), r'C:\repo\a.txt');
      expect(fs.resolve(r'src\a.txt', r'D:\work'), r'D:\work\src\a.txt');
    });

    test('empty path means the working directory', () {
      expect(fs.resolve('', '/srv'), '/srv');
    });
  });

  group('LocalAcpFileSystem', () {
    test('creates parent folders when writing and reports missing files',
        () async {
      final dir = await Directory.systemTemp.createTemp('acp-fs');
      addTearDown(() => dir.delete(recursive: true));
      const fs = LocalAcpFileSystem();
      final path = fs.resolve('nested/a.txt', dir.path);
      await fs.writeText(path, 'hello');
      expect(await fs.readText(path), 'hello');
      expect(
        () => fs.readText(fs.resolve('missing.txt', dir.path)),
        throwsA(isA<AcpFileNotFound>()),
      );
    });
  });
}

class _UnusedClient implements SSHClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('SSH is not used by resolve()');
}
