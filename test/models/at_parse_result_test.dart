import 'package:pocket_bot/models/at_parse_result.dart';
import 'package:test/test.dart';

void main() {
  group('AtParseResult Model Tests', () {
    // 基本功能测试
    test('should create AtParseResult with required fields', () {
      final result = AtParseResult(
        hasAt: true,
        contactIds: ['contact_1'],
        atNames: ['John'],
        messageContent: 'Hello',
        originalContent: '@John Hello',
        atInfos: [AtInfo(name: 'John', startIndex: 0, endIndex: 5)],
      );

      expect(result.hasAt, true);
      expect(result.contactIds, ['contact_1']);
      expect(result.atNames, ['John']);
      expect(result.messageContent, 'Hello');
      expect(result.originalContent, '@John Hello');
      expect(result.atInfos.length, 1);
    });

    test('should create AtParseResult.none correctly', () {
      final result = AtParseResult.none();

      expect(result.hasAt, false);
      expect(result.contactIds, isEmpty);
      expect(result.atNames, isEmpty);
      expect(result.messageContent, '');
      expect(result.originalContent, '');
      expect(result.atInfos, isEmpty);
    });

    test('should parse message without @', () {
      final result = AtParseResult.fromMessage('Hello world');

      expect(result.hasAt, false);
      expect(result.atNames, isEmpty);
      expect(result.contactIds, isEmpty);
      expect(result.messageContent, 'Hello world');
      expect(result.originalContent, 'Hello world');
      expect(result.atInfos, isEmpty);
    });

    test('should parse message with single @', () {
      final result = AtParseResult.fromMessage('@John Hello');

      expect(result.hasAt, true);
      expect(result.atNames, ['John']);
      expect(result.contactIds, isEmpty);
      expect(result.messageContent, 'Hello');
      expect(result.originalContent, '@John Hello');
      expect(result.atInfos.length, 1);
      expect(result.atInfos[0].name, 'John');
      expect(result.atInfos[0].startIndex, 0);
      expect(result.atInfos[0].endIndex, 5);
    });

    test('should parse message with multiple @', () {
      final result = AtParseResult.fromMessage('@John @Jane Hello');

      expect(result.hasAt, true);
      expect(result.atNames, ['John', 'Jane']);
      expect(result.messageContent, 'Hello');
    });

    test('should parse message with @ at end', () {
      final result = AtParseResult.fromMessage('Hello @John');

      expect(result.hasAt, true);
      expect(result.atNames, ['John']);
      expect(result.messageContent, 'Hello');
    });

    test('should handle duplicate @ names', () {
      final result = AtParseResult.fromMessage('@John @John Hello');

      expect(result.hasAt, true);
      expect(result.atNames.length, 1);
      expect(result.atNames, contains('John'));
    });

    test('should remove @ and trim whitespace', () {
      final result = AtParseResult.fromMessage('  @John  @Jane  test  ');

      expect(result.hasAt, true);
      expect(result.messageContent, 'test');
    });

    test('should handle @ with no name', () {
      final result = AtParseResult.fromMessage('@ Hello');

      expect(result.hasAt, false);
      expect(result.atNames, isEmpty);
      expect(result.messageContent, '@ Hello');
    });

    test('should handle empty message', () {
      final result = AtParseResult.fromMessage('');

      expect(result.hasAt, false);
      expect(result.messageContent, '');
    });

    test('should handle message with only @ names', () {
      final result = AtParseResult.fromMessage('@John @Jane');

      expect(result.hasAt, true);
      expect(result.atNames, ['John', 'Jane']);
      expect(result.messageContent, '');
    });

    test('should parse @ with complex names', () {
      final result = AtParseResult.fromMessage('@John_Doe @Jane-123 Hello');

      expect(result.hasAt, true);
      expect(result.atNames, ['John_Doe', 'Jane-123']);
    });

    test('should handle @ followed by punctuation', () {
      final result = AtParseResult.fromMessage('@John, @Jane! How are you?');

      expect(result.hasAt, true);
      expect(result.atNames.length, 2);
    });

    test('should handle @ with numbers', () {
      final result = AtParseResult.fromMessage('@User123 Hello');

      expect(result.hasAt, true);
      expect(result.atNames, ['User123']);
    });

    test('should handle consecutive @ symbols', () {
      final result = AtParseResult.fromMessage('@@John Hello');

      // Should match @John
      expect(result.hasAt, true);
      expect(result.atNames, contains('John'));
    });

    // AtInfo 边界情况测试
    test('should create AtInfo with correct indices', () {
      final info = AtInfo(name: 'Test', startIndex: 5, endIndex: 10);

      expect(info.name, 'Test');
      expect(info.startIndex, 5);
      expect(info.endIndex, 10);
    });

    test('AtInfo toString should return correct format', () {
      final info = AtInfo(name: 'John', startIndex: 0, endIndex: 5);

      expect(info.toString(), 'AtInfo(name: John, start: 0, end: 5)');
    });

    // copyWith 测试
    test('copyWith should update contactIds', () {
      final original = AtParseResult.fromMessage('@John Hello');
      final updated = original.copyWith(contactIds: ['contact_123']);

      expect(updated.hasAt, true);
      expect(updated.atNames, ['John']);
      expect(updated.contactIds, ['contact_123']);
    });

    test('copyWith should update messageContent', () {
      final original = AtParseResult.fromMessage('@John Hello');
      final updated = original.copyWith(messageContent: 'Updated content');

      expect(updated.messageContent, 'Updated content');
      expect(updated.atNames, ['John']);
    });

    test('copyWith should preserve original values when not specified', () {
      final original = AtParseResult(
        hasAt: true,
        contactIds: ['contact_1'],
        atNames: ['John'],
        messageContent: 'Hello',
        originalContent: '@John Hello',
        atInfos: [AtInfo(name: 'John', startIndex: 0, endIndex: 5)],
      );

      final updated = original.copyWith(contactIds: ['contact_2']);

      expect(updated.hasAt, true);
      expect(updated.contactIds, ['contact_2']);
      expect(updated.atNames, ['John']);
      expect(updated.messageContent, 'Hello');
    });

    // toString 测试
    test('toString should return correct format', () {
      final result = AtParseResult(
        hasAt: true,
        contactIds: ['contact_1'],
        atNames: ['John'],
        messageContent: 'Hello',
        originalContent: '@John Hello',
        atInfos: [],
      );

      final str = result.toString();

      expect(str.contains('AtParseResult'), true);
      expect(str.contains('hasAt: true'), true);
      expect(str.contains('atNames: [John]'), true);
    });

    // 边界情况测试
    test('should handle very long message', () {
      final longMessage = '@User ' + 'a' * 10000;
      final result = AtParseResult.fromMessage(longMessage);

      expect(result.hasAt, true);
      expect(result.atNames, ['User']);
    });

    test('should handle unicode @ names', () {
      final result = AtParseResult.fromMessage('@用户名 Hello');

      expect(result.hasAt, true);
      expect(result.atNames, ['用户名']);
    });

    test('should handle emoji in @ names', () {
      final result = AtParseResult.fromMessage('@用户👋 Hello');

      // Emoji is not part of valid @ name, so only match up to emoji
      expect(result.hasAt, true);
      expect(result.atNames, ['用户']);
    });

    test('should handle multiple spaces between @ and name', () {
      final result = AtParseResult.fromMessage('@  John Hello');

      // Multiple spaces after @ is not a valid @ mention pattern
      expect(result.hasAt, false);
    });

    test('should handle @ at start with newline', () {
      final result = AtParseResult.fromMessage('@John\nHello');

      expect(result.hasAt, true);
      expect(result.atNames, ['John']);
    });

    test('should handle tab after @', () {
      final result = AtParseResult.fromMessage('@John\tHello');

      expect(result.hasAt, true);
      expect(result.atNames, ['John']);
    });

    test('should handle mixed whitespace after @', () {
      final result = AtParseResult.fromMessage('@John\t\n Hello');

      expect(result.hasAt, true);
      expect(result.atNames, ['John']);
    });

    test('should preserve original content with all @ mentions', () {
      final result = AtParseResult.fromMessage('@John and @Jane say hello');

      expect(result.originalContent, '@John and @Jane say hello');
      expect(result.messageContent, 'and say hello');
    });

    test('should handle AtInfo indices for multiple @', () {
      final result = AtParseResult.fromMessage('Hey @John and @Jane!');

      expect(result.atInfos.length, 2);
      expect(result.atInfos[0].name, 'John');
      expect(result.atInfos[1].name, 'Jane');
      // First @John starts at index 4
      expect(result.atInfos[0].startIndex, 4);
      // Second @Jane starts at index 14 (after "Hey @John and ")
      expect(result.atInfos[1].startIndex, 14);
    });

    // 简体中文标点符号测试
    test('should parse @ with Chinese punctuation - comma', () {
      final result = AtParseResult.fromMessage('@张三，你好');

      expect(result.hasAt, true);
      expect(result.atNames, ['张三']);
    });

    test('should parse @ with Chinese punctuation - exclamation', () {
      final result = AtParseResult.fromMessage('@李四！有空吗');

      expect(result.hasAt, true);
      expect(result.atNames, ['李四']);
    });

    test('should parse @ with Chinese punctuation - question', () {
      final result = AtParseResult.fromMessage('@王五？方便吗');

      expect(result.hasAt, true);
      expect(result.atNames, ['王五']);
    });

    test('should parse @ with Chinese punctuation - period', () {
      final result = AtParseResult.fromMessage('@赵六。走了');

      expect(result.hasAt, true);
      expect(result.atNames, ['赵六']);
    });

    test('should parse @ with Chinese punctuation - mixed', () {
      final result = AtParseResult.fromMessage('@张三，@李四！讨论一下？');

      expect(result.hasAt, true);
      expect(result.atNames, ['张三', '李四']);
    });

    test('should parse @ with Chinese characters and numbers', () {
      final result = AtParseResult.fromMessage('@用户123 你好');

      expect(result.hasAt, true);
      expect(result.atNames, ['用户123']);
    });

    test('should parse @ with Chinese underscore', () {
      final result = AtParseResult.fromMessage('@测试_用户 你好');

      expect(result.hasAt, true);
      expect(result.atNames, ['测试_用户']);
    });

    // isValid 和 isSelfAt 字段测试
    test('should have isValid default true', () {
      final result = AtParseResult.fromMessage('@John Hello');
      expect(result.isValid, true);
    });

    test('should have isSelfAt default false', () {
      final result = AtParseResult.fromMessage('@John Hello');
      expect(result.isSelfAt, false);
    });

    test('copyWith should update isValid', () {
      final result = AtParseResult.fromMessage('@John Hello');
      final updated = result.copyWith(isValid: false);
      expect(updated.isValid, false);
      expect(updated.hasAt, true);
    });

    test('copyWith should update isSelfAt', () {
      final result = AtParseResult.fromMessage('@John Hello');
      final updated = result.copyWith(isSelfAt: true);
      expect(updated.isSelfAt, true);
      expect(updated.hasAt, true);
    });

    test('AtParseResult.none should have isValid true and isSelfAt false', () {
      final result = AtParseResult.none();
      expect(result.isValid, true);
      expect(result.isSelfAt, false);
    });
  });
}
