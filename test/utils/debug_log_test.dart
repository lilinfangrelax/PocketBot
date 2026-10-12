import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_bot/utils/debug_log.dart';
import 'package:pocket_bot/utils/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory dir;
  late DebugLog log;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('debug_log_test');
    log = DebugLog(capacity: 5, maxFileBytes: 200);
    await log.init(directory: dir);
  });

  tearDown(() async {
    log.dispose();
    await dir.delete(recursive: true);
  });

  test('keeps debug entries only while enabled', () async {
    log.add(LogLevel.debug, 'hidden');
    log.add(LogLevel.info, 'shown');
    expect(log.entries.map((e) => e.message), ['shown']);

    await log.setEnabled(true);
    log.add(LogLevel.debug, 'detail');
    expect(log.entries.last.message, 'detail');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(DebugLog.prefsKey), isTrue);
  });

  test('restores the saved switch', () async {
    SharedPreferences.setMockInitialValues({DebugLog.prefsKey: true});
    final restored = DebugLog();
    await restored.init(directory: dir);
    expect(restored.enabled, isTrue);
    restored.dispose();
  });

  test('memory is a ring buffer of capacity entries', () {
    for (var i = 0; i < 8; i++) {
      log.add(LogLevel.info, 'm$i');
    }
    expect(log.entries.map((e) => e.message), ['m3', 'm4', 'm5', 'm6', 'm7']);
  });

  test('writes, rotates, exports and clears the log file', () async {
    for (var i = 0; i < 10; i++) {
      log.add(LogLevel.warn, 'line $i ${'x' * 30}');
      await log.flush();
    }
    expect(await log.file!.exists(), isTrue);
    expect(await File('${log.file!.path}.1').exists(), isTrue);
    expect(await log.file!.length(), lessThanOrEqualTo(200));

    final text = await log.exportText(header: 'App: test');
    expect(text, contains('App: test'));
    expect(text, contains('[WARN] line 9'));

    final exported = await log.exportFile(directory: dir);
    expect(await exported.readAsString(), contains('line 9'));

    await log.clear();
    expect(log.entries, isEmpty);
    expect(await log.file!.exists(), isFalse);
  });

  test('redacts secrets', () {
    final out = DebugLog.redact(
      '{"password":"hunter2","sshPassphrase":"p","api_key":"k",'
      '"env":[{"name":"GITHUB_TOKEN","value":"ghp_abc"}],'
      '"headers":[{"name":"Authorization","value":"Bearer abcdefghijk"}]} '
      'Authorization: Bearer abcdefghijklmnop token=xyz '
      '-----BEGIN OPENSSH PRIVATE KEY-----\nAAAA\n-----END OPENSSH PRIVATE KEY-----',
    );
    for (final secret in [
      'hunter2',
      '"p"',
      '"k"',
      'ghp_abc',
      'abcdefghijk',
      'xyz',
      'AAAA',
    ]) {
      expect(out, isNot(contains(secret)), reason: secret);
    }
    expect(out, contains('"name":"GITHUB_TOKEN"'));
    expect(out, contains('[PEM redacted]'));
  });

  test('truncates long messages', () {
    final text = DebugLog.truncate('a' * 50, 10);
    expect(text, startsWith('a' * 10));
    expect(text, contains('40 more chars'));
  });

  test('Logger records into the shared log with stack traces', () async {
    final previous = DebugLog.instance;
    DebugLog.instance = log;
    try {
      Logger.error('boom', 'oops', StackTrace.current);
      expect(log.entries.last.level, LogLevel.error);
      expect(log.entries.last.message, contains('boom - oops'));
      expect(log.entries.last.message, contains('debug_log_test.dart'));

      await log.setEnabled(true);
      expect(Logger.isVerbose, isTrue);
      Logger.debug('details');
      expect(log.entries.last.message, 'details');
    } finally {
      DebugLog.instance = previous;
    }
  });
}
