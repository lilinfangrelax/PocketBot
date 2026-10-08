import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;

class CachedAgent {
  final List<String> argv;

  const CachedAgent(this.argv);
}

/// Download and unpack a registry binary distribution into [root].
Future<CachedAgent> ensureCachedAgent({
  required Directory root,
  required String agentId,
  required String version,
  required String archiveUrl,
  required String? sha256,
  required String command,
  required List<String> args,
  required Future<List<int>> Function(Uri url) download,
}) async {
  final folder = Directory(
    '${root.path}${Platform.pathSeparator}agents${Platform.pathSeparator}$agentId${Platform.pathSeparator}$version',
  );
  final marker = File('${folder.path}${Platform.pathSeparator}.ready');
  final executable = _resolveCommand(folder.path, command);
  if (marker.existsSync() && File(executable).existsSync()) {
    return CachedAgent([executable, ...args]);
  }
  if (folder.existsSync()) folder.deleteSync(recursive: true);
  folder.createSync(recursive: true);

  final bytes = await download(Uri.parse(archiveUrl));
  final expected = sha256?.trim().toLowerCase();
  if (expected != null && expected.isNotEmpty) {
    final actual = crypto.sha256.convert(bytes).toString();
    if (actual != expected) {
      throw Exception('sha256 mismatch for $agentId');
    }
  }
  _extract(bytes, archiveUrl, folder);
  final resolved = _resolveCommand(folder.path, command);
  if (!File(resolved).existsSync()) {
    throw Exception('archive for $agentId did not contain $command');
  }
  if (!Platform.isWindows) {
    await Process.run('chmod', ['+x', resolved]);
  }
  marker.writeAsStringSync(agentId);
  return CachedAgent([resolved, ...args]);
}

String _resolveCommand(String root, String command) {
  final relative = command.replaceAll('\\', '/').replaceFirst(RegExp(r'^\./'), '');
  final parts = relative.split('/').where((part) => part.isNotEmpty);
  return [root, ...parts].join(Platform.pathSeparator);
}

void _extract(List<int> bytes, String url, Directory dest) {
  final lower = url.toLowerCase().split('?').first;
  final Archive archive;
  if (lower.endsWith('.zip')) {
    archive = ZipDecoder().decodeBytes(bytes);
  } else if (lower.endsWith('.tar.gz') || lower.endsWith('.tgz')) {
    archive = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
  } else if (lower.endsWith('.tar')) {
    archive = TarDecoder().decodeBytes(bytes);
  } else {
    throw Exception('unsupported archive $url');
  }

  for (final file in archive) {
    final name = file.name.replaceAll('\\', '/');
    if (name.isEmpty || name.startsWith('/') || name.split('/').contains('..')) {
      continue;
    }
    final outPath = [dest.path, ...name.split('/')].join(Platform.pathSeparator);
    if (file.isFile) {
      final out = File(outPath);
      out.parent.createSync(recursive: true);
      out.writeAsBytesSync(List<int>.from(file.content as List));
    } else {
      Directory(outPath).createSync(recursive: true);
    }
  }
}

/// Use a downloaded registry archive, or the already installed command.
Future<List<String>> resolveLaunchArgv({
  required List<String> argv,
  required String? archiveUrl,
  required Future<List<String>> Function() install,
  List<String> legacyArgv = const [],
}) async {
  if (archiveUrl == null || archiveUrl.trim().isEmpty) return argv;
  try {
    return await install();
  } catch (error) {
    if (legacyArgv.isNotEmpty) return legacyArgv;
    throw Exception('无法下载代理: $error');
  }
}
