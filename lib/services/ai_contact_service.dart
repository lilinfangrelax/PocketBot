import 'dart:convert';
import 'package:pocket_bot/models/ai_contact_config.dart';
import 'package:pocket_bot/models/contact_session_mapping.dart';
import 'package:pocket_bot/models/contact.dart';
import 'package:pocket_bot/services/database_service.dart';
import 'package:pocket_bot/services/contact_service.dart';

/// AI 联系人服务
/// 负责 AI 联系人的配置管理和会话映射
class AIContactService {
  final DatabaseService _db = DatabaseService();
  final ContactService _contactService = ContactService();

  AIContactService();

  /// 初始化数据库表
  Future<void> initTables() async {
    // 创建 AI 联系人配置表
    await _db.execute('''
      CREATE TABLE IF NOT EXISTS ai_contact_configs (
        id TEXT PRIMARY KEY,
        contact_id TEXT NOT NULL,
        agent_id TEXT NOT NULL,
        model TEXT,
        system_prompt TEXT,
        tools TEXT,
        auto_reply INTEGER DEFAULT 0,
        keywords TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // 创建联系人-会话映射表
    await _db.execute('''
      CREATE TABLE IF NOT EXISTS contact_session_mappings (
        id TEXT PRIMARY KEY,
        contact_id TEXT NOT NULL,
        group_id TEXT NOT NULL,
        session_key TEXT NOT NULL,
        created_at TEXT NOT NULL,
        last_active_at TEXT NOT NULL,
        message_count INTEGER DEFAULT 0,
        UNIQUE(contact_id, group_id)
      )
    ''');
  }

  /// 创建 AI 联系人
  Future<AIContactConfig> createAIContact({
    required String name,
    required String agentId,
    String? atName,
    String? model,
    String? systemPrompt,
    Map<String, dynamic>? tools,
    bool autoReply = false,
    List<String>? keywords,
  }) async {
    // 创建联系人
    final contact = await _contactService.createContact(
      name: name,
      atName: atName,
      isAI: true,
    );

    // 创建 AI 配置
    final now = DateTime.now();
    final config = AIContactConfig(
      id: 'aicfg_${now.millisecondsSinceEpoch}',
      contactId: contact.id,
      agentId: agentId,
      model: model,
      systemPrompt: systemPrompt,
      tools: tools,
      autoReply: autoReply,
      keywords: keywords,
      createdAt: now,
      updatedAt: now,
    );

    // 保存配置到数据库
    await _db.insert('ai_contact_configs', config.toDbMap());

    return config;
  }

  /// 获取 AI 联系人配置
  Future<AIContactConfig?> getConfig(String contactId) async {
    final results = await _db.query(
      'ai_contact_configs',
      where: 'contact_id = ?',
      whereArgs: [contactId],
    );

    if (results.isEmpty) return null;
    return AIContactConfig.fromDbMap(results.first);
  }

  /// 获取所有 AI 联系人配置
  Future<List<AIContactConfig>> getAllConfigs() async {
    final results = await _db.query('ai_contact_configs');
    return results.map((e) => AIContactConfig.fromDbMap(e)).toList();
  }

  /// 更新 AI 联系人配置
  Future<AIContactConfig?> updateConfig({
    required String contactId,
    String? agentId,
    String? model,
    String? systemPrompt,
    Map<String, dynamic>? tools,
    bool? autoReply,
    List<String>? keywords,
  }) async {
    final existing = await getConfig(contactId);
    if (existing == null) return null;

    final updated = existing.copyWith(
      agentId: agentId,
      model: model,
      systemPrompt: systemPrompt,
      tools: tools,
      autoReply: autoReply,
      keywords: keywords,
    );

    await _db.update(
      'ai_contact_configs',
      updated.toDbMap(),
      where: 'contact_id = ?',
      whereArgs: [contactId],
    );

    return updated;
  }

  /// 删除 AI 联系人配置
  Future<bool> deleteConfig(String contactId) async {
    final result = await _db.delete(
      'ai_contact_configs',
      where: 'contact_id = ?',
      whereArgs: [contactId],
    );
    return result > 0;
  }

  /// 创建或更新会话映射
  Future<ContactSessionMapping> createOrUpdateMapping({
    required String contactId,
    required String groupId,
    required String sessionKey,
  }) async {
    // 查询是否已存在映射
    final existing = await getMapping(contactId, groupId);

    if (existing != null) {
      // 更新映射
      final updated = existing.copyWith(
        sessionKey: sessionKey,
        lastActiveAt: DateTime.now(),
        messageCount: existing.messageCount + 1,
      );

      await _db.update(
        'contact_session_mappings',
        updated.toDbMap(),
        where: 'contact_id = ? AND group_id = ?',
        whereArgs: [contactId, groupId],
      );

      return updated;
    }

    // 创建新映射
    final now = DateTime.now();
    final mapping = ContactSessionMapping(
      id: 'mapping_${now.millisecondsSinceEpoch}',
      contactId: contactId,
      groupId: groupId,
      sessionKey: sessionKey,
      createdAt: now,
      lastActiveAt: now,
      messageCount: 1,
    );

    await _db.insert('contact_session_mappings', mapping.toDbMap());
    return mapping;
  }

  /// 获取会话映射
  Future<ContactSessionMapping?> getMapping(String contactId, String groupId) async {
    final results = await _db.query(
      'contact_session_mappings',
      where: 'contact_id = ? AND group_id = ?',
      whereArgs: [contactId, groupId],
    );

    if (results.isEmpty) return null;
    return ContactSessionMapping.fromDbMap(results.first);
  }

  /// 获取联系人的所有映射
  Future<List<ContactSessionMapping>> getMappingsForContact(String contactId) async {
    final results = await _db.query(
      'contact_session_mappings',
      where: 'contact_id = ?',
      whereArgs: [contactId],
    );

    return results.map((e) => ContactSessionMapping.fromDbMap(e)).toList();
  }

  /// 获取群聊的所有 AI 联系人映射
  Future<List<ContactSessionMapping>> getMappingsForGroup(String groupId) async {
    final results = await _db.query(
      'contact_session_mappings',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );

    return results.map((e) => ContactSessionMapping.fromDbMap(e)).toList();
  }

  /// 删除会话映射
  Future<bool> deleteMapping(String contactId, String groupId) async {
    final result = await _db.delete(
      'contact_session_mappings',
      where: 'contact_id = ? AND group_id = ?',
      whereArgs: [contactId, groupId],
    );
    return result > 0;
  }

  /// 更新消息计数
  Future<void> incrementMessageCount(String contactId, String groupId) async {
    final mapping = await getMapping(contactId, groupId);
    if (mapping != null) {
      await _db.execute(
        'UPDATE contact_session_mappings SET message_count = message_count + 1, last_active_at = ? WHERE contact_id = ? AND group_id = ?',
        [DateTime.now().toIso8601String(), contactId, groupId],
      );
    }
  }

  /// 获取所有 AI 联系人
  Future<List<Contact>> getAIContacts() async {
    return await _contactService.getAIContacts();
  }

  /// 检查联系人是否是 AI 联系人
  Future<bool> isAIContact(String contactId) async {
    final contact = await _contactService.getContact(contactId);
    return contact?.isAI ?? false;
  }

  /// 通过 atName 查找 AI 联系人
  Future<Contact?> findAIContactByAtName(String atName) async {
    final contacts = await _contactService.searchContacts(atName);
    return contacts.where((c) => c.isAI).firstOrNull;
  }
}
