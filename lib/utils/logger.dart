import 'package:flutter/foundation.dart';

class Logger {
  static void debug(String message, [dynamic error]) {
    if (kDebugMode) {
      _print('DEBUG', message, error);
    }
  }

  static void info(String message, [dynamic error]) {
    _print('INFO', message, error);
  }

  static void warning(String message, [dynamic error]) {
    _print('WARN', message, error);
  }

  static void error(String message, [dynamic error, StackTrace? stackTrace]) {
    _print('ERROR', message, error);
    if (stackTrace != null) {
      _print('STACK', stackTrace.toString(), null);
    }
  }

  static void _print(String level, String message, dynamic error) {
    final buffer = StringBuffer()..write('[$level] ')..write(message);
    if (error != null) {
      buffer.write(' - $error');
    }
    print(buffer.toString());
  }
}
