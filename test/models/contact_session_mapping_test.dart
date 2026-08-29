import 'package:pocket_bot/models/contact_session_mapping.dart';
import 'package:test/test.dart';

void main() {
  group('ContactSessionMapping Model Tests', () {
    // 基本功能测试
    test('should create ContactSessionMapping with required fields', () {
      final mapping = ContactSessionMapping(
        contactId: 'contact_123',
        groupId: 'group_456',
        sessionKey: 'session_789',
      );

      expect(mapping.contactId, 'contact_123');
      expect(mapping.groupId, 'group_456');
      expect(mapping.sessionKey, 'session_789');
      expect(mapping.id, '');
      expect(mapping.messageCount, 0);
    });

    test('should create ContactSessionMapping with all fields', () {
      final now = DateTime.now();
      final mapping = ContactSessionMapping(
        id: 'mapping_001',
        contactId: 'contact_123',
        groupId: 'group_456',
        sessionKey: 'session_789',
        createdAt: now,
        lastActiveAt: now,
        messageCount: 10,
      );

      expect(mapping.id, 'mapping_001');
      expect(mapping.contactId, 'contact_123');
      expect(mapping.groupId, 'group_456');
      expect(mapping.sessionKey, 'session_789');
      expect(mapping.messageCount, 10);
      expect(mapping.createdAt, now);
      expect(mapping.lastActiveAt, now);
    });

    test('should serialize to JSON correctly', () {
      final now = DateTime(2024, 1, 1, 12, 0, 0);
      final mapping = ContactSessionMapping(
        id: 'mapping_001',
        contactId: 'contact_123',
        groupId: 'group_456',
        sessionKey: 'session_789',
        createdAt: now,
        lastActiveAt: now,
        messageCount: 5,
      );

      final json = mapping.toJson();

      expect(json['id'], 'mapping_001');
      expect(json['contactId'], 'contact_123');
      expect(json['groupId'], 'group_456');
      expect(json['sessionKey'], 'session_789');
      expect(json['messageCount'], 5);
    });

    test('should deserialize from JSON correctly', () {
      final json = {
        'id': 'mapping_001',
        'contactId': 'contact_123',
        'groupId': 'group_456',
        'sessionKey': 'session_789',
        'createdAt': '2024-01-01T12:00:00.000',
        'lastActiveAt': '2024-01-01T12:00:00.000',
        'messageCount': 5,
      };

      final mapping = ContactSessionMapping.fromJson(json);

      expect(mapping.id, 'mapping_001');
      expect(mapping.contactId, 'contact_123');
      expect(mapping.groupId, 'group_456');
      expect(mapping.sessionKey, 'session_789');
      expect(mapping.messageCount, 5);
    });

    test('should handle null values in JSON deserialization', () {
      final json = {
        'id': 'mapping_001',
        'contactId': null,
        'groupId': null,
        'sessionKey': null,
        'createdAt': null,
        'lastActiveAt': null,
        'messageCount': null,
      };

      final mapping = ContactSessionMapping.fromJson(json);

      expect(mapping.id, 'mapping_001');
      expect(mapping.contactId, '');
      expect(mapping.groupId, '');
      expect(mapping.sessionKey, '');
      expect(mapping.messageCount, 0);
    });

    test('should convert to database map correctly', () {
      final now = DateTime(2024, 1, 1, 12, 0, 0);
      final mapping = ContactSessionMapping(
        id: 'mapping_001',
        contactId: 'contact_123',
        groupId: 'group_456',
        sessionKey: 'session_789',
        createdAt: now,
        lastActiveAt: now,
        messageCount: 5,
      );

      final dbMap = mapping.toDbMap();

      expect(dbMap['id'], 'mapping_001');
      expect(dbMap['contact_id'], 'contact_123');
      expect(dbMap['group_id'], 'group_456');
      expect(dbMap['session_key'], 'session_789');
      expect(dbMap['message_count'], 5);
    });

    test('should create from database map correctly', () {
      final dbMap = {
        'id': 'mapping_001',
        'contact_id': 'contact_123',
        'group_id': 'group_456',
        'session_key': 'session_789',
        'created_at': '2024-01-01T12:00:00.000',
        'last_active_at': '2024-01-02T12:00:00.000',
        'message_count': 10,
      };

      final mapping = ContactSessionMapping.fromDbMap(dbMap);

      expect(mapping.id, 'mapping_001');
      expect(mapping.contactId, 'contact_123');
      expect(mapping.groupId, 'group_456');
      expect(mapping.sessionKey, 'session_789');
      expect(mapping.messageCount, 10);
    });

    test('should handle null values in database map', () {
      final dbMap = {
        'id': 'mapping_001',
        'contact_id': null,
        'group_id': null,
        'session_key': null,
        'created_at': null,
        'last_active_at': null,
        'message_count': null,
      };

      final mapping = ContactSessionMapping.fromDbMap(dbMap);

      expect(mapping.contactId, '');
      expect(mapping.groupId, '');
      expect(mapping.sessionKey, '');
      expect(mapping.messageCount, 0);
    });

    test('copyWith should update specified fields', () {
      final original = ContactSessionMapping(
        id: 'mapping_001',
        contactId: 'contact_123',
        groupId: 'group_456',
        sessionKey: 'session_789',
        messageCount: 5,
      );

      final updated = original.copyWith(
        sessionKey: 'new_session_key',
        messageCount: 10,
      );

      expect(updated.id, 'mapping_001');
      expect(updated.contactId, 'contact_123');
      expect(updated.groupId, 'group_456');
      expect(updated.sessionKey, 'new_session_key');
      expect(updated.messageCount, 10);
    });

    test('copyWith should preserve original values when not specified', () {
      final now = DateTime.now();
      final original = ContactSessionMapping(
        id: 'mapping_001',
        contactId: 'contact_123',
        groupId: 'group_456',
        sessionKey: 'session_789',
        createdAt: now,
        lastActiveAt: now,
        messageCount: 5,
      );

      final updated = original.copyWith(messageCount: 20);

      expect(updated.id, 'mapping_001');
      expect(updated.contactId, 'contact_123');
      expect(updated.groupId, 'group_456');
      expect(updated.sessionKey, 'session_789');
      expect(updated.createdAt, now);
      expect(updated.lastActiveAt, now);
      expect(updated.messageCount, 20);
    });

    test('equality should be based on contactId and groupId', () {
      final mapping1 = ContactSessionMapping(
        contactId: 'contact_123',
        groupId: 'group_456',
        sessionKey: 'session_789',
      );

      final mapping2 = ContactSessionMapping(
        contactId: 'contact_123',
        groupId: 'group_456',
        sessionKey: 'different_session',
      );

      final mapping3 = ContactSessionMapping(
        contactId: 'contact_999',
        groupId: 'group_456',
        sessionKey: 'session_789',
      );

      expect(mapping1, equals(mapping2));
      expect(mapping1, isNot(equals(mapping3)));
    });

    test('hashCode should be based on contactId and groupId', () {
      final mapping1 = ContactSessionMapping(
        contactId: 'contact_123',
        groupId: 'group_456',
        sessionKey: 'session_789',
      );

      final mapping2 = ContactSessionMapping(
        contactId: 'contact_123',
        groupId: 'group_456',
        sessionKey: 'different',
      );

      expect(mapping1.hashCode, equals(mapping2.hashCode));
    });

    // 边界情况测试
    test('should handle empty strings', () {
      final mapping = ContactSessionMapping(
        contactId: '',
        groupId: '',
        sessionKey: '',
      );

      expect(mapping.contactId, '');
      expect(mapping.groupId, '');
      expect(mapping.sessionKey, '');
    });

    test('should handle zero message count', () {
      final mapping = ContactSessionMapping(
        contactId: 'contact_123',
        groupId: 'group_456',
        sessionKey: 'session_789',
        messageCount: 0,
      );

      expect(mapping.messageCount, 0);
    });

    test('should handle very large message count', () {
      final mapping = ContactSessionMapping(
        contactId: 'contact_123',
        groupId: 'group_456',
        sessionKey: 'session_789',
        messageCount: 999999999,
      );

      expect(mapping.messageCount, 999999999);
    });

    test('should handle special characters in session key', () {
      final mapping = ContactSessionMapping(
        contactId: 'contact_123',
        groupId: 'group_456',
        sessionKey: 'session/key+with=special!chars',
      );

      expect(mapping.sessionKey, 'session/key+with=special!chars');
    });

    test('should handle unicode characters', () {
      final mapping = ContactSessionMapping(
        contactId: '联系人123',
        groupId: '群组456',
        sessionKey: '会话789',
      );

      expect(mapping.contactId, '联系人123');
      expect(mapping.groupId, '群组456');
      expect(mapping.sessionKey, '会话789');
    });

    test('should handle long IDs', () {
      final longId = 'a' * 100;
      final mapping = ContactSessionMapping(
        id: longId,
        contactId: longId,
        groupId: longId,
        sessionKey: longId,
      );

      expect(mapping.id.length, 100);
      expect(mapping.contactId.length, 100);
      expect(mapping.groupId.length, 100);
      expect(mapping.sessionKey.length, 100);
    });

    test('should handle future dates', () {
      final futureDate = DateTime(2100, 12, 31);
      final mapping = ContactSessionMapping(
        contactId: 'contact_123',
        groupId: 'group_456',
        sessionKey: 'session_789',
        createdAt: futureDate,
        lastActiveAt: futureDate,
      );

      expect(mapping.createdAt.year, 2100);
      expect(mapping.lastActiveAt.year, 2100);
    });

    test('should handle past dates', () {
      final pastDate = DateTime(2000, 1, 1);
      final mapping = ContactSessionMapping(
        contactId: 'contact_123',
        groupId: 'group_456',
        sessionKey: 'session_789',
        createdAt: pastDate,
        lastActiveAt: pastDate,
      );

      expect(mapping.createdAt.year, 2000);
      expect(mapping.lastActiveAt.year, 2000);
    });

    test('should handle JSON with different date formats', () {
      final json = {
        'id': 'mapping_001',
        'contactId': 'contact_123',
        'groupId': 'group_456',
        'sessionKey': 'session_789',
        'createdAt': '2024-01-01T12:00:00+00:00',
        'lastActiveAt': '2024-01-01T12:00:00.000Z',
        'messageCount': 5,
      };

      final mapping = ContactSessionMapping.fromJson(json);

      expect(mapping.createdAt, isA<DateTime>());
      expect(mapping.lastActiveAt, isA<DateTime>());
    });

    test('copyWith should update lastActiveAt', () {
      final original = ContactSessionMapping(
        contactId: 'contact_123',
        groupId: 'group_456',
        sessionKey: 'session_789',
      );

      final newTime = DateTime(2025, 1, 1);
      final updated = original.copyWith(lastActiveAt: newTime);

      expect(updated.lastActiveAt, newTime);
    });
  });
}
