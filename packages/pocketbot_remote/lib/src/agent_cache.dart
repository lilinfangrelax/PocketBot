import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart' as crypto;

class CachedAgent {
  final List<String> argv;

  const CachedAgent(this.argv);
}

typedef ArchiveDownload = Future<void> Function(Uri url, File destination);

/// Download and unpack a registry binary distribution into [root].
///
/// The archive is streamed to disk and extracted entry by entry, so small
/// hosts do not have to hold the whole package in memory.
Future<CachedAgent> ensureCachedAgent({
  required Directory root,
  required String agentId,
  required String version,
  required String archiveUrl,
  required String? sha256,
  required String command,
  required List<String> args,
  required ArchiveDownload download,
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

  final staging = File('${folder.path}.download');
  final executables = <String>[];
  try {
    await download(Uri.parse(archiveUrl), staging);
    final expected = sha256?.trim().toLowerCase();
    if (expected != null && expected.isNotEmpty) {
      final actual = await _sha256OfFile(staging);
      if (actual != expected) {
        throw Exception('sha256 mismatch for $agentId');
      }
    }
    executables.addAll(await _extract(staging, archiveUrl, folder));
  } finally {
    if (staging.existsSync()) staging.deleteSync();
  }
  final resolved = _resolveCommand(folder.path, command);
  if (!File(resolved).existsSync()) {
    throw Exception('archive for $agentId did not contain $command');
  }
  if (!Platform.isWindows) {
    await _makeExecutable([resolved, ...executables]);
  }
  marker.writeAsStringSync(agentId);
  return CachedAgent([resolved, ...args]);
}

Future<String> _sha256OfFile(File file) async {
  final digest = await crypto.sha256.bind(file.openRead()).first;
  return digest.toString();
}

String _resolveCommand(String root, String command) {
  final relative =
      command.replaceAll('\\', '/').replaceFirst(RegExp(r'^\./'), '');
  final parts = relative.split('/').where((part) => part.isNotEmpty);
  return [root, ...parts].join(Platform.pathSeparator);
}

Future<List<String>> _extract(
  File archive,
  String url,
  Directory dest,
) async {
  final lower = url.toLowerCase().split('?').first;
  final executables = <String>[];
  if (lower.endsWith('.zip')) {
    final input = InputFileStream(archive.path);
    try {
      _extractZip(ZipDecoder().decodeBuffer(input), dest, executables);
    } finally {
      await input.close();
    }
  } else if (lower.endsWith('.tar.gz') || lower.endsWith('.tgz')) {
    await _extractTar(
      archive.openRead().transform(gzip.decoder),
      dest,
      executables,
    );
  } else if (lower.endsWith('.tar')) {
    await _extractTar(archive.openRead(), dest, executables);
  } else {
    throw Exception('unsupported archive $url');
  }
  return executables;
}

void _extractZip(
  Archive archive,
  Directory dest,
  List<String> executables,
) {
  for (final file in archive) {
    final parts = _safeParts(file.name);
    if (parts == null) continue;
    final outPath = _join(dest.path, parts);
    if (file.isSymbolicLink) {
      _createLink(dest, parts, file.nameOfLinkedFile);
      continue;
    }
    if (!file.isFile) {
      Directory(outPath).createSync(recursive: true);
      continue;
    }
    final out = File(outPath);
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(List<int>.from(file.content as List), flush: false);
    if (_isExecutableMode(file.mode)) executables.add(outPath);
  }
}

Future<void> _extractTar(
  Stream<List<int>> stream,
  Directory dest,
  List<String> executables,
) async {
  final reader = _TarReader(stream);
  String? pendingName;
  String? pendingLink;
  try {
    while (true) {
      final header = await reader.read(512);
      if (header == null || header.every((byte) => byte == 0)) break;
      var name = _tarText(header, 0, 100);
      final mode = _tarNumber(header, 100, 8);
      final size = _tarNumber(header, 124, 12);
      final type = header[156];
      var link = _tarText(header, 157, 100);
      if (_tarText(header, 257, 6).startsWith('ustar')) {
        final prefix = _tarText(header, 345, 155);
        if (prefix.isNotEmpty) name = '$prefix/$name';
      }
      if (pendingName != null) {
        name = pendingName;
        pendingName = null;
      }
      if (pendingLink != null) {
        link = pendingLink;
        pendingLink = null;
      }

      var consumed = false;
      if (type == 0x4C) {
        pendingName = await reader.readText(size);
        consumed = true;
      } else if (type == 0x4B) {
        pendingLink = await reader.readText(size);
        consumed = true;
      } else if (type == 0x78) {
        final pax = _parsePax(await reader.readText(size));
        pendingName = pax['path'];
        pendingLink = pax['linkpath'];
        consumed = true;
      } else if (type == 0x67) {
        consumed = true;
      } else {
        final parts = _safeParts(name);
        if (parts != null) {
          final outPath = _join(dest.path, parts);
          if (type == 0x35) {
            Directory(outPath).createSync(recursive: true);
          } else if (type == 0x32) {
            _createLink(dest, parts, link);
          } else if (type == 0x30 || type == 0x00 || type == 0x37) {
            final out = File(outPath);
            out.parent.createSync(recursive: true);
            final sink = out.openWrite();
            try {
              await reader.copy(sink, size);
            } finally {
              await sink.close();
            }
            consumed = true;
            if (_isExecutableMode(mode)) executables.add(outPath);
          }
        }
      }
      if (!consumed) await reader.skip(size);
      await reader.skip(_padding(size));
    }
  } finally {
    await reader.cancel();
  }
}

List<String>? _safeParts(String name) {
  final normalized = name.replaceAll('\\', '/');
  if (normalized.isEmpty ||
      normalized.startsWith('/') ||
      RegExp(r'^[a-zA-Z]:').hasMatch(normalized)) {
    return null;
  }
  final parts = normalized
      .split('/')
      .where((part) => part.isNotEmpty && part != '.')
      .toList();
  if (parts.isEmpty || parts.contains('..')) return null;
  return parts;
}

bool _createLink(Directory dest, List<String> parts, String target) {
  if (target.isEmpty) return false;
  final normalized = target.replaceAll('\\', '/');
  if (normalized.startsWith('/') ||
      RegExp(r'^[a-zA-Z]:').hasMatch(normalized)) {
    return false;
  }
  final stack = parts.sublist(0, parts.length - 1).toList();
  for (final part in normalized.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (stack.isEmpty) return false;
      stack.removeLast();
    } else {
      stack.add(part);
    }
  }
  final path = _join(dest.path, parts);
  _removeExisting(path);
  final link = Link(path);
  link.parent.createSync(recursive: true);
  try {
    link.createSync(normalized);
    return true;
  } on FileSystemException {
    return false;
  }
}

void _removeExisting(String path) {
  final type = FileSystemEntity.typeSync(path, followLinks: false);
  if (type == FileSystemEntityType.notFound) return;
  if (type == FileSystemEntityType.directory) {
    Directory(path).deleteSync(recursive: true);
  } else if (type == FileSystemEntityType.link) {
    Link(path).deleteSync();
  } else {
    File(path).deleteSync();
  }
}

String _join(String root, List<String> parts) =>
    [root, ...parts].join(Platform.pathSeparator);

bool _isExecutableMode(int mode) => mode & 0x49 != 0;

Future<void> _makeExecutable(Iterable<String> paths) async {
  final all = paths.toSet().toList();
  for (var start = 0; start < all.length; start += 100) {
    final end = start + 100 > all.length ? all.length : start + 100;
    try {
      final result = await Process.run(
        'chmod',
        ['+x', ...all.sublist(start, end)],
      );
      if (result.exitCode != 0) {
        throw Exception('chmod failed: ${result.stderr.toString().trim()}');
      }
    } on ProcessException catch (error) {
      throw Exception('chmod failed: ${error.message}');
    }
  }
}

int _padding(int size) => size % 512 == 0 ? 0 : 512 - size % 512;

String _tarText(Uint8List header, int offset, int length) {
  var end = offset;
  final limit = offset + length;
  while (end < limit && header[end] != 0) {
    end++;
  }
  return utf8.decode(
    Uint8List.sublistView(header, offset, end),
    allowMalformed: true,
  );
}

int _tarNumber(Uint8List header, int offset, int length) {
  if (header[offset] & 0x80 != 0) {
    var value = header[offset] & 0x7f;
    for (var i = 1; i < length; i++) {
      value = (value << 8) | header[offset + i];
    }
    return value;
  }
  var end = offset;
  final limit = offset + length;
  while (end < limit && header[end] != 0) {
    end++;
  }
  final text = String.fromCharCodes(header.sublist(offset, end)).trim();
  if (text.isEmpty) return 0;
  return int.tryParse(text, radix: 8) ?? 0;
}

Map<String, String> _parsePax(String text) {
  final result = <String, String>{};
  for (final line in const LineSplitter().convert(text)) {
    final space = line.indexOf(' ');
    if (space <= 0) continue;
    final pair = line.substring(space + 1);
    final equals = pair.indexOf('=');
    if (equals <= 0) continue;
    result[pair.substring(0, equals)] = pair.substring(equals + 1);
  }
  return result;
}

class _TarReader {
  _TarReader(Stream<List<int>> stream) : _iterator = StreamIterator(stream);

  final StreamIterator<List<int>> _iterator;
  Uint8List _chunk = Uint8List(0);
  int _offset = 0;

  Future<Uint8List?> read(int length) async {
    final result = BytesBuilder(copy: false);
    var remaining = length;
    while (remaining > 0) {
      if (_offset >= _chunk.length) {
        if (!await _next()) {
          if (result.length == 0) return null;
          throw const FormatException('truncated tar archive');
        }
        continue;
      }
      final available = _chunk.length - _offset;
      final take = remaining < available ? remaining : available;
      result.add(Uint8List.sublistView(_chunk, _offset, _offset + take));
      _offset += take;
      remaining -= take;
    }
    return result.takeBytes();
  }

  Future<String> readText(int length) async {
    if (length == 0) return '';
    final bytes = await read(length);
    return utf8
        .decode(bytes!, allowMalformed: true)
        .split('\u0000')
        .first
        .trimRight();
  }

  Future<void> copy(IOSink sink, int length) async {
    var remaining = length;
    while (remaining > 0) {
      if (_offset >= _chunk.length) {
        if (!await _next())
          throw const FormatException('truncated tar archive');
        continue;
      }
      final available = _chunk.length - _offset;
      final take = remaining < available ? remaining : available;
      sink.add(Uint8List.sublistView(_chunk, _offset, _offset + take));
      _offset += take;
      remaining -= take;
    }
  }

  Future<void> skip(int length) async {
    var remaining = length;
    while (remaining > 0) {
      if (_offset >= _chunk.length) {
        if (!await _next())
          throw const FormatException('truncated tar archive');
        continue;
      }
      final available = _chunk.length - _offset;
      final take = remaining < available ? remaining : available;
      _offset += take;
      remaining -= take;
    }
  }

  Future<bool> _next() async {
    while (await _iterator.moveNext()) {
      final data = _iterator.current;
      if (data.isEmpty) continue;
      _chunk = data is Uint8List ? data : Uint8List.fromList(data);
      _offset = 0;
      return true;
    }
    return false;
  }

  Future<void> cancel() => _iterator.cancel();
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
