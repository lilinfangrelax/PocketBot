import 'package:pocket_bot/models/ai_contact_config.dart';
import 'package:test/test.dart';

void main() {
  group('AIContactConfig Model Tests', () {
    // 基本功能测试
    test('should create AIContactConfig with required fields', () {
      final config = AIContactConfig(
        contactId: 'contact_123',
        agentId: 'agent_456',
      );

      expect(config.contactId, 'contact_123');
      expect(config.agentId, 'agent_456');
      expect(config.id, '');
      expect(config.autoReply, false);
      expect(config.model, isNull);
      expect(config.systemPrompt, isNull);
      expect(config.tools, isNull);
      expect(config.keywords, isNull);
    });

    test('should create AIContactConfig with all fields', () {
      final now = DateTime.now();
      final tools = {'tool1': {'name': 'test'}};
      final keywords = ['hello', 'help'];

      final config = AIContactConfig(
        id: 'cfg_001',
        contactId: 'contact_123',
        agentId: 'agent_456',
        model: 'gpt-4',
        systemPrompt: 'You are a helpful assistant.',
        tools: tools,
        autoReply: true,
        keywords: keywords,
        createdAt: now,
        updatedAt: now,
      );

      expect(config.id, 'cfg_001');
      expect(config.contactId, 'contact_123');
      expect(config.agentId, 'agent_456');
      expect(config.model, 'gpt-4');
      expect(config.systemPrompt, 'You are a helpful assistant.');
      expect(config.tools, tools);
      expect(config.autoReply, true);
      expect(config.keywords, keywords);
    });

    test('should serialize to JSON correctly', () {
      final now = DateTime(2024, 1, 1, 12, 0, 0);
      final config = AIContactConfig(
        id: 'cfg_001',
        contactId: 'contact_123',
        agentId: 'agent_456',
        model: 'gpt-4',
        systemPrompt: 'Test prompt',
        autoReply: true,
        keywords: ['hi', 'hey'],
        createdAt: now,
        updatedAt: now,
      );

      final json = config.toJson();

      expect(json['id'], 'cfg_001');
      expect(json['contactId'], 'contact_123');
      expect(json['agentId'], 'agent_456');
      expect(json['model'], 'gpt-4');
      expect(json['systemPrompt'], 'Test prompt');
      expect(json['autoReply'], true);
      expect(json['keywords'], ['hi', 'hey']);
    });

    test('should deserialize from JSON correctly', () {
      final json = {
        'id': 'cfg_001',
        'contactId': 'contact_123',
        'agentId': 'agent_456',
        'model': 'gpt-4',
        'systemPrompt': 'Test prompt',
        'autoReply': true,
        'keywords': ['hi', 'hey'],
        'createdAt': '2024-01-01T12:00:00.000',
        'updatedAt': '2024-01-01T12:00:00.000',
      };

      final config = AIContactConfig.fromJson(json);

      expect(config.id, 'cfg_001');
      expect(config.contactId, 'contact_123');
      expect(config.agentId, 'agent_456');
      expect(config.model, 'gpt-4');
      expect(config.systemPrompt, 'Test prompt');
      expect(config.autoReply, true);
      expect(config.keywords, ['hi', 'hey']);
    });

    test('should handle null values in JSON deserialization', () {
      final json = {
        'id': 'cfg_001',
        'contactId': 'contact_123',
        'agentId': 'agent_456',
        'model': null,
        'systemPrompt': null,
        'tools': null,
        'autoReply': false,
        'keywords': null,
        'createdAt': null,
        'updatedAt': null,
      };

      final config = AIContactConfig.fromJson(json);

      expect(config.id, 'cfg_001');
      expect(config.model, isNull);
      expect(config.systemPrompt, isNull);
      expect(config.tools, isNull);
      expect(config.keywords, isNull);
    });

    test('should serialize tools as Map in JSON', () {
      final tools = {'search': {'description': 'Search the web'}};
      final config = AIContactConfig(
        contactId: 'contact_123',
        agentId: 'agent_456',
        tools: tools,
      );

      final json = config.toJson();

      expect(json['tools'], tools);
    });

    test('should deserialize tools from JSON', () {
      final json = {
        'id': 'cfg_001',
        'contactId': 'contact_123',
        'agentId': 'agent_456',
        'tools': {'search': {'description': 'Search'}},
        'autoReply': false,
        'createdAt': '2024-01-01T12:00:00.000',
        'updatedAt': '2024-01-01T12:00:00.000',
      };

      final config = AIContactConfig.fromJson(json);

      expect(config.tools, isNotNull);
      expect(config.tools!['search'], {'description': 'Search'});
    });

    test('should convert to database map correctly', () {
      final now = DateTime(2024, 1, 1, 12, 0, 0);
      final config = AIContactConfig(
        id: 'cfg_001',
        contactId: 'contact_123',
        agentId: 'agent_456',
        model: 'gpt-4',
        autoReply: true,
        keywords: ['hi', 'hey'],
        createdAt: now,
        updatedAt: now,
      );

      final dbMap = config.toDbMap();

      expect(dbMap['id'], 'cfg_001');
      expect(dbMap['contact_id'], 'contact_123');
      expect(dbMap['agent_id'], 'agent_456');
      expect(dbMap['model'], 'gpt-4');
      expect(dbMap['auto_reply'], 1);
    });

    test('should create from database map correctly', () {
      final dbMap = {
        'id': 'cfg_001',
        'contact_id': 'contact_123',
        'agent_id': 'agent_456',
        'model': 'gpt-4',
        'system_prompt': 'Test prompt',
        'tools': '{"search": {"desc": "search"}}',
        'auto_reply': 1,
        'keywords': '["hi", "hey"]',
        'created_at': '2024-01-01T12:00:00.000',
        'updated_at': '2024-01-01T12:00:00.000',
      };

      final config = AIContactConfig.fromDbMap(dbMap);

      expect(config.id, 'cfg_001');
      expect(config.contactId, 'contact_123');
      expect(config.agentId, 'agent_456');
      expect(config.model, 'gpt-4');
      expect(config.systemPrompt, 'Test prompt');
      expect(config.autoReply, true);
      expect(config.keywords, ['hi', 'hey']);
    });

    test('copyWith should update specified fields', () {
      final original = AIContactConfig(
        id: 'cfg_001',
        contactId: 'contact_123',
        agentId: 'agent_456',
        autoReply: false,
      );

      final updated = original.copyWith(
        autoReply: true,
        model: 'gpt-4',
      );

      expect(updated.id, 'cfg_001');
      expect(updated.contactId, 'contact_123');
      expect(updated.agentId, 'agent_456');
      expect(updated.autoReply, true);
      expect(updated.model, 'gpt-4');
    });

    test('copyWith should preserve original values when not specified', () {
      final original = AIContactConfig(
        id: 'cfg_001',
        contactId: 'contact_123',
        agentId: 'agent_456',
        model: 'gpt-3.5',
        systemPrompt: 'Original prompt',
        autoReply: true,
      );

      final updated = original.copyWith(agentId: 'agent_789');

      expect(updated.id, 'cfg_001');
      expect(updated.contactId, 'contact_123');
      expect(updated.agentId, 'agent_789');
      expect(updated.model, 'gpt-3.5');
      expect(updated.systemPrompt, 'Original prompt');
      expect(updated.autoReply, true);
    });

    test('equality should be based on id', () {
      final config1 = AIContactConfig(
        id: 'cfg_001',
        contactId: 'contact_123',
        agentId: 'agent_456',
      );

      final config2 = AIContactConfig(
        id: 'cfg_001',
        contactId: 'contact_123',
        agentId: 'agent_456',
      );

      final config3 = AIContactConfig(
        id: 'cfg_002',
        contactId: 'contact_123',
        agentId: 'agent_456',
      );

      expect(config1, equals(config2));
      expect(config1, isNot(equals(config3)));
    });

    test('hashCode should be based on id', () {
      final config1 = AIContactConfig(
        id: 'cfg_001',
        contactId: 'contact_123',
        agentId: 'agent_456',
      );

      final config2 = AIContactConfig(
        id: 'cfg_001',
        contactId: 'contact_123',
        agentId: 'agent_456',
      );

      expect(config1.hashCode, equals(config2.hashCode));
    });

    // 边界情况测试
    test('should handle empty string id', () {
      final config = AIContactConfig(
        id: '',
        contactId: 'contact_123',
        agentId: 'agent_456',
      );

      expect(config.id, '');
      expect(config.autoReply, false);
    });

    test('should handle empty keywords list', () {
      final config = AIContactConfig(
        contactId: 'contact_123',
        agentId: 'agent_456',
        keywords: [],
      );

      expect(config.keywords, isEmpty);
    });

    test('should handle special characters in keywords', () {
      final config = AIContactConfig(
        contactId: 'contact_123',
        agentId: 'agent_456',
        keywords: ['hello!', 'what?', 'test(1)'],
      );

      expect(config.keywords!.length, 3);
      expect(config.keywords, contains('hello!'));
    });

    test('should handle unicode characters in system prompt', () {
      final config = AIContactConfig(
        contactId: 'contact_123',
        agentId: 'agent_456',
        systemPrompt: '你好世界 🌍',
      );

      expect(config.systemPrompt, '你好世界 🌍');
    });

    test('should handle large tools map', () {
      final largeTools = <String, dynamic>{};
      for (int i = 0; i < 100; i++) {
        largeTools['tool_$i'] = {'name': 'Tool $i', 'description': 'Description $i'};
      }

      final config = AIContactConfig(
        contactId: 'contact_123',
        agentId: 'agent_456',
        tools: largeTools,
      );

      expect(config.tools!.length, 100);
    });

    test('should handle null autoReply in JSON', () {
      final json = {
        'id': 'cfg_001',
        'contactId': 'contact_123',
        'agentId': 'agent_456',
        'autoReply': null,
        'createdAt': '2024-01-01T12:00:00.000',
        'updatedAt': '2024-01-01T12:00:00.000',
      };

      final config = AIContactConfig.fromJson(json);

      expect(config.autoReply, false);
    });

    test('should handle invalid tools format in JSON', () {
      final json = {
        'id': 'cfg_001',
        'contactId': 'contact_123',
        'agentId': 'agent_456',
        'tools': 'invalid',
        'createdAt': '2024-01-01T12:00:00.000',
        'updatedAt': '2024-01-01T12:00:00.000',
      };

      final config = AIContactConfig.fromJson(json);

      expect(config.tools, isNull);
    });

    test('should handle invalid keywords format in JSON', () {
      final json = {
        'id': 'cfg_001',
        'contactId': 'contact_123',
        'agentId': 'agent_456',
        'keywords': 'invalid',
        'createdAt': '2024-01-01T12:00:00.000',
        'updatedAt': '2024-01-01T12:00:00.000',
      };

      final config = AIContactConfig.fromJson(json);

      expect(config.keywords, isNull);
    });
  });
}
