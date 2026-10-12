import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LogLevel { debug, info, warn, error }

extension LogLevelLabel on LogLevel {
  String get label => switch (this) {
        LogLevel.debug => 'DEBUG',
        LogLevel.info => 'INFO',
        LogLevel.warn => 'WARN',
        LogLevel.error => 'ERROR',
      };
}

class LogEntry {
  const LogEntry(this.time, this.level, this.message);

  final DateTime time;
  final LogLevel level;
  final String message;

  String format() => '${_timestamp(time)} [${level.label}] $message';
}

/// In-app log store behind [Logger].
///
/// Info, warnings and errors are always kept in memory and in the log file;
/// debug entries only while [enabled] (the 调试模式 switch). Everything is
/// passed through [redact] first, so exported logs can be shared.
class DebugLog extends ChangeNotifier {
  DebugLog({this.capacity = 2000, this.maxFileBytes = 1024 * 1024});

  static DebugLog instance = DebugLog();

  static bool get verbose => instance.enabled;

  static const prefsKey = 'debug_logging';
  static const fileName = 'pocketbot.log';
  static const maxMessageLength = 4000;

  final int capacity;
  final int maxFileBytes;

  final Queue<LogEntry> _entries = Queue<LogEntry>();
  final StringBuffer _pending = StringBuffer();
  bool _enabled = false;
  Directory? _directory;
  Timer? _flushTimer;
  Timer? _notifyTimer;
  Future<void> _writing = Future.value();

  bool get enabled => _enabled;
  List<LogEntry> get entries => List.unmodifiable(_entries);
  File? get file =>
      _directory == null ? null : File('${_directory!.path}/$fileName');
  File? get _previousFile =>
      _directory == null ? null : File('${_directory!.path}/$fileName.1');

  /// Loads the saved switch and opens the log folder. Logging works before
  /// this finishes; entries are written once the folder is known.
  Future<void> init({Directory? directory}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(prefsKey) ?? false;
    } catch (_) {}
    try {
      _directory = directory ??
          Directory('${(await getApplicationSupportDirectory()).path}/logs');
      await _directory!.create(recursive: true);
    } catch (_) {
      _directory = null;
    }
    _scheduleFlush();
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    add(LogLevel.info, '[DebugLog] 调试模式${value ? '已开启' : '已关闭'}');
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefsKey, value);
    } catch (_) {}
  }

  void add(LogLevel level, String message) {
    if (level == LogLevel.debug && !_enabled) return;
    final entry = LogEntry(DateTime.now(), level, redact(truncate(message)));
    _entries.addLast(entry);
    while (_entries.length > capacity) {
      _entries.removeFirst();
    }
    _pending.writeln(entry.format());
    _scheduleFlush();
    if (!hasListeners) return;
    _notifyTimer ??= Timer(const Duration(milliseconds: 250), () {
      _notifyTimer = null;
      notifyListeners();
    });
  }

  void _scheduleFlush() {
    if (_directory == null || _pending.isEmpty) return;
    _flushTimer ??= Timer(const Duration(seconds: 1), () {
      _flushTimer = null;
      flush();
    });
  }

  /// Writes buffered entries to the log file, rotating it at [maxFileBytes].
  Future<void> flush() {
    _flushTimer?.cancel();
    _flushTimer = null;
    final target = file;
    if (target == null || _pending.isEmpty) return _writing;
    final chunk = _pending.toString();
    _pending.clear();
    return _writing = _writing.then((_) async {
      try {
        if (await target.exists() &&
            await target.length() + chunk.length > maxFileBytes) {
          final previous = _previousFile!;
          if (await previous.exists()) await previous.delete();
          await target.rename(previous.path);
        }
        await target.writeAsString(chunk, mode: FileMode.append, flush: true);
      } catch (_) {}
    });
  }

  /// Clears memory and log files.
  Future<void> clear() async {
    _entries.clear();
    _pending.clear();
    await _writing;
    for (final f in [file, _previousFile]) {
      try {
        if (f != null && await f.exists()) await f.delete();
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Full log text with a device header: previous runs from the log files,
  /// or the in-memory entries when no file is available.
  Future<String> exportText({String header = ''}) async {
    await flush();
    await _writing;
    final buffer = StringBuffer()
      ..writeln('PocketBot debug log')
      ..writeln('Exported: ${_timestamp(DateTime.now())}')
      ..writeln('Platform: ${Platform.operatingSystem} '
          '${Platform.operatingSystemVersion}')
      ..writeln('Debug mode: ${_enabled ? 'on' : 'off'}');
    if (header.isNotEmpty) buffer.writeln(header);
    buffer.writeln('-' * 40);
    var fromFiles = false;
    for (final f in [_previousFile, file]) {
      try {
        if (f != null && await f.exists()) {
          buffer.write(await f.readAsString());
          fromFiles = true;
        }
      } catch (_) {}
    }
    if (!fromFiles) {
      for (final entry in _entries) {
        buffer.writeln(entry.format());
      }
    }
    return buffer.toString();
  }

  /// Saves [exportText] to a standalone file and returns it.
  Future<File> exportFile({String header = '', Directory? directory}) async {
    final dir = directory ?? _directory ?? await getTemporaryDirectory();
    final stamp = _timestamp(DateTime.now())
        .replaceAll(RegExp(r'[^0-9]'), '')
        .substring(0, 14);
    final out = File('${dir.path}/pocketbot-log-$stamp.txt');
    await out.writeAsString(await exportText(header: header));
    return out;
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    _notifyTimer?.cancel();
    super.dispose();
  }

  static String truncate(String text, [int max = maxMessageLength]) {
    if (text.length <= max) return text;
    return '${text.substring(0, max)}…(${text.length - max} more chars)';
  }

  static final List<(RegExp, String Function(Match))> _rules = [
    (
      RegExp(r'-----BEGIN [A-Z0-9 ]+-----[\s\S]*?(-----END [A-Z0-9 ]+-----|$)'),
      (_) => '[PEM redacted]',
    ),
    (
      RegExp(
        r'"([A-Za-z_]*(?:password|passphrase|passwd|token|secret|apikey|api_key|privatekey|private_key|authorization|cookie)[A-Za-z_]*)"(\s*:\s*)"(?:[^"\\]|\\.)*"',
        caseSensitive: false,
      ),
      (m) => '"${m[1]}"${m[2]}"***"',
    ),
    (
      RegExp(
          r'("name"\s*:\s*"(?:[^"\\]|\\.)*"\s*,\s*"value"\s*:\s*)"(?:[^"\\]|\\.)*"'),
      (m) => '${m[1]}"***"',
    ),
    (
      RegExp(r'\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]{8,}',
          caseSensitive: false),
      (m) => '${m[1]} ***',
    ),
    (
      RegExp(
        r'\b(password|passphrase|passwd|token|secret|api_key|apikey)=[^\s&"]+',
        caseSensitive: false,
      ),
      (m) => '${m[1]}=***',
    ),
  ];

  /// Masks passwords, tokens, private keys and MCP env/header values.
  static String redact(String text) {
    var result = text;
    for (final (pattern, replace) in _rules) {
      result = result.replaceAllMapped(pattern, replace);
    }
    return result;
  }
}

String _timestamp(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  final ms = t.millisecond.toString().padLeft(3, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.$ms';
}
