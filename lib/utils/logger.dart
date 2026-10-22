import 'package:flutter/foundation.dart';
import 'package:pocket_bot/utils/debug_log.dart';

class Logger {
  static bool get isVerbose => kDebugMode || DebugLog.verbose;

  static void debug(String message, [dynamic error]) {
    if (isVerbose) {
      _print(LogLevel.debug, message, error);
    }
  }

  static void info(String message, [dynamic error]) {
    _print(LogLevel.info, message, error);
  }

  static void warning(String message, [dynamic error]) {
    _print(LogLevel.warn, message, error);
  }

  static void error(String message, [dynamic error, StackTrace? stackTrace]) {
    _print(LogLevel.error, message, error, stackTrace);
  }

  static void _print(
    LogLevel level,
    String message,
    dynamic error, [
    StackTrace? stackTrace,
  ]) {
    final buffer = StringBuffer(message);
    if (error != null) {
      buffer.write(' - $error');
    }
    if (stackTrace != null) {
      buffer
        ..write('\n')
        ..write(stackTrace);
    }
    final text = buffer.toString();
    print('[${level.label}] $text');
    DebugLog.instance.add(level, text);
  }
}
