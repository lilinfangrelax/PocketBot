import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:pocket_bot/models/group_chat.dart';
import 'package:pocket_bot/models/contact.dart';

/// SQLite数据库服务
class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  static Database? _database;

  factory DatabaseService() => _instance;

  DatabaseService._internal();

  /// 获取数据库实例
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // ========== 通用 CRUD 方法 ==========

  /// 执行 SQL 语句
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    final db = await database;
    await db.execute(sql, arguments);
  }

  /// 插入数据
  Future<int> insert(String table, Map<String, dynamic> values) async {
    final db = await database;
    return await db.insert(table, values);
  }

  /// 查询数据
  Future<List<Map<String, dynamic>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final db = await database;
    return await db.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  /// 更新数据
  Future<int> update(
    String table,
    Map<String, dynamic> values, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final db = await database;
    return await db.update(table, values, where: where, whereArgs: whereArgs);
  }

  /// 删除数据
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final db = await database;
    return await db.delete(table, where: where, whereArgs: whereArgs);
  }

  /// 执行原始 SQL 查询
  Future<List<Map<String, dynamic>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    final db = await database;
    return await db.rawQuery(sql, arguments);
  }

  /// 执行原始 SQL 语句 (用于 UPDATE/DELETE/INSERT)
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) async {
    final db = await database;
    return await db.rawUpdate(sql, arguments);
  }

  /// 执行原始 SQL 语句 (用于 DELETE)
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) async {
    final db = await database;
    return await db.rawDelete(sql, arguments);
  }

  // ========== 初始化数据库 ==========

  /// 初始化数据库
  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'pocket_bot.db');

    return await openDatabase(
      path,
      version: 2, // 升级版本号
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// 创建数据库表
  Future<void> _onCreate(Database db, int version) async {
    // 群聊表
    await db.execute('''
      CREATE TABLE groups (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        avatar TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        show_in_session_list INTEGER NOT NULL DEFAULT 1
      )
    ''');

    // 群成员表
    await db.execute('''
      CREATE TABLE group_members (
        id TEXT PRIMARY KEY,
        group_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        user_name TEXT NOT NULL,
        user_avatar TEXT,
        at_name TEXT,
        role TEXT NOT NULL,
        joined_at TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (group_id) REFERENCES groups (id) ON DELETE CASCADE,
        UNIQUE (group_id, user_id)
      )
    ''');

    // 群消息表
    await db.execute('''
      CREATE TABLE group_messages (
        id TEXT PRIMARY KEY,
        group_id TEXT NOT NULL,
        sender_id TEXT NOT NULL,
        sender_name TEXT NOT NULL,
        sender_avatar TEXT,
        content TEXT NOT NULL,
        at_list TEXT,
        timestamp TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (group_id) REFERENCES groups (id) ON DELETE CASCADE
      )
    ''');

    // 联系人表
    await db.execute('''
      CREATE TABLE contacts (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        at_name TEXT,
        avatar TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        is_ai INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // 创建索引
    await db.execute(
        'CREATE INDEX idx_group_members_group_id ON group_members (group_id)');
    await db.execute(
        'CREATE INDEX idx_group_messages_group_id ON group_messages (group_id)');
    await db.execute(
        'CREATE INDEX idx_group_messages_timestamp ON group_messages (timestamp)');
  }

  /// 升级数据库
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // 从版本1升级到版本2：添加 show_in_session_list 字段
    if (oldVersion < 2) {
      try {
        await db.execute('ALTER TABLE groups ADD COLUMN show_in_session_list INTEGER NOT NULL DEFAULT 1');
      } catch (e) {
        // 字段可能已存在，忽略错误
      }
    }
  }

  // ==================== 群聊操作 ====================

  /// 插入群聊
  Future<void> insertGroup(GroupChat group) async {
    final db = await database;
    await db.insert(
      'groups',
      {
        'id': group.id,
        'name': group.name,
        'avatar': group.avatar,
        'created_at': group.createdAt.toIso8601String(),
        'updated_at': group.updatedAt.toIso8601String(),
        'is_active': group.isActive ? 1 : 0,
        'show_in_session_list': group.showInSessionList ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 获取所有群聊
  Future<List<GroupChat>> getAllGroups({bool? showInSessionList}) async {
    final db = await database;
    String? where;
    List<dynamic>? whereArgs;
    
    if (showInSessionList != null) {
      where = 'is_active = ? AND show_in_session_list = ?';
      whereArgs = [1, showInSessionList ? 1 : 0];
    } else {
      where = 'is_active = ?';
      whereArgs = [1];
    }
    
    final List<Map<String, dynamic>> maps = await db.query(
      'groups',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'updated_at DESC',
    );

    final groups = <GroupChat>[];
    for (final map in maps) {
      final members = await getGroupMembers(map['id']);
      groups.add(GroupChat(
        id: map['id'],
        name: map['name'],
        avatar: map['avatar'],
        members: members,
        createdAt: DateTime.parse(map['created_at']),
        updatedAt: DateTime.parse(map['updated_at']),
        isActive: map['is_active'] == 1,
        showInSessionList: map['show_in_session_list'] == 1,
      ));
    }
    return groups;
  }

  /// 获取单个群聊
  Future<GroupChat?> getGroup(String groupId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'groups',
      where: 'id = ?',
      whereArgs: [groupId],
    );

    if (maps.isEmpty) return null;

    final map = maps.first;
    final members = await getGroupMembers(groupId);
    return GroupChat(
      id: map['id'],
      name: map['name'],
      avatar: map['avatar'],
      members: members,
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
      isActive: map['is_active'] == 1,
      showInSessionList: map['show_in_session_list'] == 1,
    );
  }

  /// 更新群聊
  Future<void> updateGroup(GroupChat group) async {
    final db = await database;
    await db.update(
      'groups',
      {
        'name': group.name,
        'avatar': group.avatar,
        'updated_at': DateTime.now().toIso8601String(),
        'is_active': group.isActive ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [group.id],
    );
  }

  /// 删除群聊（软删除）
  Future<void> deleteGroup(String groupId) async {
    final db = await database;
    await db.update(
      'groups',
      {
        'is_active': 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [groupId],
    );
  }

  /// 更新群聊在会话列表中的显示状态
  Future<void> updateGroupShowInSessionList(String groupId, bool showInSessionList) async {
    final db = await database;
    await db.update(
      'groups',
      {
        'show_in_session_list': showInSessionList ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [groupId],
    );
  }

  // ==================== 群成员操作 ====================

  /// 插入群成员
  Future<void> insertGroupMember(GroupMember member) async {
    final db = await database;
    await db.insert(
      'group_members',
      {
        'id': member.id,
        'group_id': member.groupId,
        'user_id': member.userId,
        'user_name': member.userName,
        'user_avatar': member.userAvatar,
        'at_name': member.atName,
        'role': member.role.toString().split('.').last,
        'joined_at': member.joinedAt.toIso8601String(),
        'is_active': member.isActive ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 批量插入群成员
  Future<void> insertGroupMembers(List<GroupMember> members) async {
    final db = await database;
    final batch = db.batch();
    for (final member in members) {
      batch.insert(
        'group_members',
        {
          'id': member.id,
          'group_id': member.groupId,
          'user_id': member.userId,
          'user_name': member.userName,
          'user_avatar': member.userAvatar,
          'at_name': member.atName,
          'role': member.role.toString().split('.').last,
          'joined_at': member.joinedAt.toIso8601String(),
          'is_active': member.isActive ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// 获取群成员列表
  Future<List<GroupMember>> getGroupMembers(String groupId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'group_members',
      where: 'group_id = ? AND is_active = ?',
      whereArgs: [groupId, 1],
      orderBy: 'joined_at ASC',
    );

    return maps.map((map) => _parseGroupMember(map)).toList();
  }

  /// 根据atName获取群成员
  Future<GroupMember?> getMemberByAtName(
      String groupId, String atName) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'group_members',
      where: 'group_id = ? AND at_name = ? AND is_active = ?',
      whereArgs: [groupId, atName, 1],
    );

    if (maps.isEmpty) return null;
    return _parseGroupMember(maps.first);
  }

  /// 更新群成员
  Future<void> updateGroupMember(GroupMember member) async {
    final db = await database;
    await db.update(
      'group_members',
      {
        'user_name': member.userName,
        'user_avatar': member.userAvatar,
        'at_name': member.atName,
        'role': member.role.toString().split('.').last,
        'is_active': member.isActive ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [member.id],
    );
  }

  /// 删除群成员
  Future<void> deleteGroupMember(String memberId) async {
    final db = await database;
    await db.update(
      'group_members',
      {'is_active': 0},
      where: 'id = ?',
      whereArgs: [memberId],
    );
  }

  GroupMember _parseGroupMember(Map<String, dynamic> map) {
    return GroupMember(
      id: map['id'],
      groupId: map['group_id'],
      userId: map['user_id'],
      userName: map['user_name'],
      userAvatar: map['user_avatar'],
      atName: map['at_name'],
      role: GroupMemberRole.values.firstWhere(
        (e) => e.toString() == 'GroupMemberRole.${map['role']}',
        orElse: () => GroupMemberRole.member,
      ),
      joinedAt: DateTime.parse(map['joined_at']),
      isActive: map['is_active'] == 1,
    );
  }

  // ==================== 群消息操作 ====================

  /// 插入群消息
  Future<void> insertGroupMessage(GroupMessage message) async {
    final db = await database;
    await db.insert(
      'group_messages',
      {
        'id': message.id,
        'group_id': message.groupId,
        'sender_id': message.senderId,
        'sender_name': message.senderName,
        'sender_avatar': message.senderAvatar,
        'content': message.content,
        'at_list': jsonEncode(message.atList.map((a) => a.toJson()).toList()),
        'timestamp': message.timestamp.toIso8601String(),
        'is_deleted': message.isDeleted ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 获取群消息列表
  Future<List<GroupMessage>> getGroupMessages(
    String groupId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'group_messages',
      where: 'group_id = ? AND is_deleted = ?',
      whereArgs: [groupId, 0],
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );

    return maps.map((map) => _parseGroupMessage(map)).toList();
  }

  /// 获取群消息
  Future<GroupMessage?> getGroupMessage(String messageId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'group_messages',
      where: 'id = ?',
      whereArgs: [messageId],
    );

    if (maps.isEmpty) return null;
    return _parseGroupMessage(maps.first);
  }

  /// 删除群消息（软删除）
  Future<void> deleteGroupMessage(String messageId) async {
    final db = await database;
    await db.update(
      'group_messages',
      {'is_deleted': 1},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  GroupMessage _parseGroupMessage(Map<String, dynamic> map) {
    List<AtInfo> atList = [];
    if (map['at_list'] != null && map['at_list'].toString().isNotEmpty) {
      final atListJson = jsonDecode(map['at_list']) as List;
      atList = atListJson.map((a) => AtInfo.fromJson(a)).toList();
    }

    return GroupMessage(
      id: map['id'],
      groupId: map['group_id'],
      senderId: map['sender_id'],
      senderName: map['sender_name'],
      senderAvatar: map['sender_avatar'],
      content: map['content'],
      atList: atList,
      timestamp: DateTime.parse(map['timestamp']),
      isDeleted: map['is_deleted'] == 1,
    );
  }

  // ==================== 联系人操作 ====================

  /// 插入联系人
  Future<void> insertContact(Contact contact) async {
    final db = await database;
    await db.insert(
      'contacts',
      {
        'id': contact.id,
        'name': contact.name,
        'at_name': contact.atName,
        'avatar': contact.avatar,
        'is_active': contact.isActive ? 1 : 0,
        'is_ai': contact.isAI ? 1 : 0,
        'created_at': contact.createdAt.toIso8601String(),
        'updated_at': contact.updatedAt.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 获取所有联系人
  Future<List<Contact>> getAllContacts() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'contacts',
      where: 'is_active = ?',
      whereArgs: [1],
      orderBy: 'created_at DESC',
    );

    return maps.map((map) => _parseContact(map)).toList();
  }

  /// 获取单个联系人
  Future<Contact?> getContact(String id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'contacts',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isEmpty) return null;
    return _parseContact(maps.first);
  }

  /// 更新联系人
  Future<void> updateContact(Contact contact) async {
    final db = await database;
    await db.update(
      'contacts',
      {
        'name': contact.name,
        'at_name': contact.atName,
        'avatar': contact.avatar,
        'is_active': contact.isActive ? 1 : 0,
        'is_ai': contact.isAI ? 1 : 0,
        'updated_at': contact.updatedAt.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [contact.id],
    );
  }

  /// 删除联系人（软删除）
  Future<void> deleteContact(String id) async {
    final db = await database;
    await db.update(
      'contacts',
      {
        'is_active': 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Contact _parseContact(Map<String, dynamic> map) {
    return Contact(
      id: map['id'],
      name: map['name'],
      atName: map['at_name'],
      avatar: map['avatar'],
      isActive: map['is_active'] == 1,
      isAI: map['is_ai'] == 1,
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }

  /// 关闭数据库
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
