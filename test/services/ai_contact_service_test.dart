import 'package:pocket_bot/models/ai_contact_config.dart';
import 'package:pocket_bot/models/contact_session_mapping.dart';
import 'package:pocket_bot/services/ai_contact_service.dart';
import 'package:test/test.dart';

void main() {
  group('AIContactService Tests', () {
    // 注意：由于 AIContactService 依赖真实的 DatabaseService 和 ContactService，
    // 这里主要测试模型层的序列化和业务逻辑，数据库操作需要在集成测试中进行

    test('AIContactConfig serialization roundtrip', () {
      final config = AIContactConfig(
        id: 'cfg_001',
        contactId: 'contact_123',
        agentId: 'agent_456',
        model: 'gpt-4',
        systemPrompt: 'You are helpful.',
        autoReply: true,
        keywords: ['help', 'test'],
      );

      // Test JSON serialization/deserialization
      final json = config.toJson();
      final restored = AIContactConfig.fromJson(json);

      expect(restored.id, config.id);
      expect(restored.contactId, config.contactId);
      expect(restored.agentId, config.agentId);
      expect(restored.model, config.model);
      expect(restored.systemPrompt, config.systemPrompt);
      expect(restored.autoReply, config.autoReply);
      expect(restored.keywords, config.keywords);
    });

    test('AIContactConfig database map roundtrip', () {
      final config = AIContactConfig(
        id: 'cfg_001',
        contactId: 'contact_123',
        agentId: 'agent_456',
        model: 'gpt-4',
        systemPrompt: 'You are helpful.',
        autoReply: true,
        keywords: ['help', 'test'],
        tools: {'search': {'description': 'Search'}},
      );

      // Test database map serialization/deserialization
      final dbMap = config.toDbMap();
      final restored = AIContactConfig.fromDbMap(dbMap);

      expect(restored.id, config.id);
      expect(restored.contactId, config.contactId);
      expect(restored.agentId, config.agentId);
      expect(restored.model, config.model);
      expect(restored.systemPrompt, config.systemPrompt);
      expect(restored.autoReply, config.autoReply);
      expect(restored.keywords, config.keywords);
    });

    test('ContactSessionMapping serialization roundtrip', () {
      final mapping = ContactSessionMapping(
        id: 'mapping_001',
        contactId: 'contact_123',
        groupId: 'group_456',
        sessionKey: 'session_789',
        messageCount: 10,
      );

      // Test JSON serialization/deserialization
      final json = mapping.toJson();
      final restored = ContactSessionMapping.fromJson(json);

      expect(restored.id, mapping.id);
      expect(restored.contactId, mapping.contactId);
      expect(restored.groupId, mapping.groupId);
      expect(restored.sessionKey, mapping.sessionKey);
      expect(restored.messageCount, mapping.messageCount);
    });

    test('ContactSessionMapping database map roundtrip', () {
      final mapping = ContactSessionMapping(
        id: 'mapping_001',
        contactId: 'contact_123',
        groupId: 'group_456',
        sessionKey: 'session_789',
        messageCount: 10,
      );

      // Test database map serialization/deserialization
      final dbMap = mapping.toDbMap();
      final restored = ContactSessionMapping.fromDbMap(dbMap);

      expect(restored.id, mapping.id);
      expect(restored.contactId, mapping.contactId);
      expect(restored.groupId, mapping.groupId);
      expect(restored.sessionKey, mapping.sessionKey);
      expect(restored.messageCount, mapping.messageCount);
    });

    test('AIContactConfig copyWith preserves data', () {
      final original = AIContactConfig(
        id: 'cfg_001',
        contactId: 'contact_123',
        agentId: 'agent_456',
        model: 'gpt-3.5',
        autoReply: false,
      );

      final updated = original.copyWith(
        model: 'gpt-4',
        autoReply: true,
      );

      expect(updated.id, 'cfg_001');
      expect(updated.contactId, 'contact_123');
      expect(updated.agentId, 'agent_456');
      expect(updated.model, 'gpt-4');
      expect(updated.autoReply, true);
    });

    test('ContactSessionMapping copyWith preserves data', () {
      final original = ContactSessionMapping(
        id: 'mapping_001',
        contactId: 'contact_123',
        groupId: 'group_456',
        sessionKey: 'session_789',
        messageCount: 5,
      );

      final updated = original.copyWith(
        sessionKey: 'new_session',
        messageCount: 10,
      );

      expect(updated.id, 'mapping_001');
      expect(updated.contactId, 'contact_123');
      expect(updated.groupId, 'group_456');
      expect(updated.sessionKey, 'new_session');
      expect(updated.messageCount, 10);
    });

    // 边界情况测试
    test('AIContactConfig handles null optional fields', () {
      final config = AIContactConfig(
        contactId: 'contact_123',
        agentId: 'agent_456',
      );

      expect(config.model, isNull);
      expect(config.systemPrompt, isNull);
      expect(config.tools, isNull);
      expect(config.keywords, isNull);
    });

    test('AIContactConfig handles empty keywords list', () {
      final config = AIContactConfig(
        contactId: 'contact_123',
        agentId: 'agent_456',
        keywords: [],
      );

      expect(config.keywords, isEmpty);
    });

    test('ContactSessionMapping handles zero message count', () {
      final mapping = ContactSessionMapping(
        contactId: 'contact_123',
        groupId: 'group_456',
        sessionKey: 'session_789',
        messageCount: 0,
      );

      expect(mapping.messageCount, 0);
    });

    test('ContactSessionMapping equality based on contactId and groupId', () {
      final mapping1 = ContactSessionMapping(
        contactId: 'contact_123',
        groupId: 'group_456',
        sessionKey: 'session_1',
      );

      final mapping2 = ContactSessionMapping(
        contactId: 'contact_123',
        groupId: 'group_456',
        sessionKey: 'session_2',
      );

      expect(mapping1, equals(mapping2));
    });

    test('AIContactConfig equality based on id', () {
      final config1 = AIContactConfig(
        id: 'cfg_001',
        contactId: 'contact_123',
        agentId: 'agent_1',
      );

      final config2 = AIContactConfig(
        id: 'cfg_001',
        contactId: 'contact_123',
        agentId: 'agent_2',
      );

      expect(config1, equals(config2));
    });

    // 工具测试
    test('AIContactConfig handles complex tools structure', () {
      final tools = {
        'search': {
          'name': 'Search',
          'description': 'Search the web',
          'parameters': {
            'type': 'object',
            'properties': {
              'query': {'type': 'string'}
            },
            'required': ['query']
          }
        },
        'calculator': {
          'name': 'Calculator',
          'description': 'Perform calculations',
        }
      };

      final config = AIContactConfig(
        contactId: 'contact_123',
        agentId: 'agent_456',
        tools: tools,
      );

      expect(config.tools, isNotNull);
      expect(config.tools!['search'], isNotNull);
      expect(config.tools!['calculator'], isNotNull);
    });

    test('AIContactConfig database map serializes tools to JSON', () {
      final tools = {'search': {'description': 'Search'}};
      final config = AIContactConfig(
        contactId: 'contact_123',
        agentId: 'agent_456',
        tools: tools,
      );

      final dbMap = config.toDbMap();

      expect(dbMap['tools'], isA<String>());
    });

    test('ContactSessionMapping increments message count', () {
      final original = ContactSessionMapping(
        contactId: 'contact_123',
        groupId: 'group_456',
        sessionKey: 'session_789',
        messageCount: 5,
      );

      final updated = original.copyWith(
        messageCount: original.messageCount + 1,
        lastActiveAt: DateTime.now(),
      );

      expect(updated.messageCount, 6);
    });

    test('ContactSessionMapping lastActiveAt updates', () {
      final originalTime = DateTime(2024, 1, 1);
      final original = ContactSessionMapping(
        contactId: 'contact_123',
        groupId: 'group_456',
        sessionKey: 'session_789',
        lastActiveAt: originalTime,
      );

      final newTime = DateTime(2024, 1, 2);
      final updated = original.copyWith(lastActiveAt: newTime);

      expect(updated.lastActiveAt, newTime);
    });

    test('AIContactConfig autoReply serializes correctly to db', () {
      final configTrue = AIContactConfig(
        contactId: 'contact_123',
        agentId: 'agent_456',
        autoReply: true,
      );

      final configFalse = AIContactConfig(
        contactId: 'contact_123',
        agentId: 'agent_456',
        autoReply: false,
      );

      final dbMapTrue = configTrue.toDbMap();
      final dbMapFalse = configFalse.toDbMap();

      expect(dbMapTrue['auto_reply'], 1);
      expect(dbMapFalse['auto_reply'], 0);
    });

    test('AIContactConfig deserializes autoReply from db correctly', () {
      final dbMapTrue = {
        'id': 'cfg_001',
        'contact_id': 'contact_123',
        'agent_id': 'agent_456',
        'auto_reply': 1,
        'created_at': '2024-01-01T00:00:00.000',
        'updated_at': '2024-01-01T00:00:00.000',
      };

      final dbMapFalse = {
        'id': 'cfg_001',
        'contact_id': 'contact_123',
        'agent_id': 'agent_456',
        'auto_reply': 0,
        'created_at': '2024-01-01T00:00:00.000',
        'updated_at': '2024-01-01T00:00:00.000',
      };

      final configTrue = AIContactConfig.fromDbMap(dbMapTrue);
      final configFalse = AIContactConfig.fromDbMap(dbMapFalse);

      expect(configTrue.autoReply, true);
      expect(configFalse.autoReply, false);
    });

    test('ContactSessionMapping can be created with custom timestamps', () {
      final createdAt = DateTime(2024, 1, 1);
      final lastActiveAt = DateTime(2024, 1, 15);

      final mapping = ContactSessionMapping(
        contactId: 'contact_123',
        groupId: 'group_456',
        sessionKey: 'session_789',
        createdAt: createdAt,
        lastActiveAt: lastActiveAt,
      );

      expect(mapping.createdAt, createdAt);
      expect(mapping.lastActiveAt, lastActiveAt);
    });

    test('AIContactConfig can be created with custom timestamps', () {
      final createdAt = DateTime(2024, 1, 1);
      final updatedAt = DateTime(2024, 1, 15);

      final config = AIContactConfig(
        contactId: 'contact_123',
        agentId: 'agent_456',
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      expect(config.createdAt, createdAt);
      expect(config.updatedAt, updatedAt);
    });

    test('Keywords serialize correctly to database format', () {
      final keywords = ['help', 'support', 'test'];
      final config = AIContactConfig(
        contactId: 'contact_123',
        agentId: 'agent_456',
        keywords: keywords,
      );

      final dbMap = config.toDbMap();

      expect(dbMap['keywords'], isA<String>());
      expect(dbMap['keywords'], contains('help'));
    });

    test('Multiple ContactSessionMappings for same contact different groups', () {
      final mapping1 = ContactSessionMapping(
        contactId: 'contact_123',
        groupId: 'group_1',
        sessionKey: 'session_1',
      );

      final mapping2 = ContactSessionMapping(
        contactId: 'contact_123',
        groupId: 'group_2',
        sessionKey: 'session_2',
      );

      // They should not be equal since groupId differs
      expect(mapping1, isNot(equals(mapping2)));
    });
  });
}
