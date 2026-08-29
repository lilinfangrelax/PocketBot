import 'package:pocket_bot/utils/logger.dart';
import 'package:test/test.dart';

void main() {
  group('Logger Tests', () {
    test('info prints message', () {
      // In test mode, info should print to stdout
      Logger.info('Test info message');
      Logger.info('Test info with data', 'extra data');
    });

    test('warning prints message', () {
      Logger.warning('Test warning message');
      Logger.warning('Warning with error', 'some error');
    });

    test('error prints message', () {
      Logger.error('Test error message');
      Logger.error('Error with exception', 'exception details');
    });

    test('error with stackTrace prints stack', () {
      Logger.error(
        'Error with stack trace',
        'stack trace details',
        StackTrace.fromString('test stack trace'),
      );
    });

    test('Message with error appends error info', () {
      Logger.info('Info with error attached', 'attached error info');
      Logger.warning('Warning with exception', Exception('test exception'));
    });

    test('Empty message handling', () {
      Logger.info('');
      Logger.warning('');
      Logger.error('');
    });

    test('Message with special characters', () {
      Logger.info('Message with special chars: at pound star percent');
      Logger.info('Multi-line\nmessage\ntest');
      Logger.info('Quotes: double and single');
    });

    test('Message with unicode characters', () {
      Logger.info('Unicode test: Chinese characters');
      Logger.info('Emojis: rocket party computer');
    });

    test('Long message handling', () {
      Logger.info('A' * 1000);
    });

    test('debug mode check does not throw', () {
      Logger.debug('Debug message');
      Logger.debug('Debug with data', {'key': 'value'});
    });
  });
}
