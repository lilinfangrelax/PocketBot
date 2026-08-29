import 'dart:async';
import 'package:pocket_bot/models/group_chat.dart';
import 'package:pocket_bot/models/contact.dart';
import 'package:pocket_bot/services/database_service.dart';
import 'package:pocket_bot/services/contact_service.dart';
import 'package:pocket_bot/services/websocket_service.dart';
import 'package:pocket_bot/utils/logger.dart';

/// 群聊服务 - 处理@提及解析和AI触发逻辑
class GroupChatService {
  static final GroupChatService _instance = GroupChatService._internal();
  factory GroupChatService() => _instance;
  GroupChatService._internal();

  final DatabaseService _db = DatabaseService();
  final ContactService _contactService = ContactService();
  WebSocketService? _wsService;

  /// 设置 WebSocketService（需要在连接成功后调用）
  void setWebSocketService(WebSocketService wsService) {
    _wsService = wsService;
  }

  /// 从文本中解析@提及
  /// 返回匹配到的 AtInfo 列表
  /// 注意: 实际匹配需要调用方提供联系人列表进行验证
  List<AtInfo> parseAtMentionsSync(String text) {
    final List<AtInfo> atList = [];
    
    // 查找@匹配
    // 支持的格式: @atName
    final atPattern = RegExp(r'@(\S+)');
    final matches = atPattern.allMatches(text);
    
    for (final match in matches) {
      final atName = match.group(1);
      if (atName == null || atName.isEmpty) continue;
      
      // 创建 AtInfo（实际的联系人验证由调用方负责）
      atList.add(AtInfo(
        userId: '', // 待填充
        userName: '', // 待填充
        atName: atName,
        position: match.start,
        length: match.group(0)!.length,
      ));
    }
    
    return atList;
  }

  /// 处理群消息
  /// 如果消息中有@提及，触发AI响应
  Future<void> processGroupMessage(GroupMessage message) async {
    // 解析@提及
    final atList = parseAtMentionsSync(message.content);
    
    if (atList.isEmpty) return; // 没有@任何人
    
    // 为消息添加@信息
    final messageWithAt = message.copyWith(atList: atList);
    
    // 保存消息到数据库
    await _saveGroupMessage(messageWithAt);
    
    // 触发AI响应（TODO: 实现具体的AI调用逻辑）
    for (final atInfo in atList) {
      await triggerAIResponse(atInfo, message.groupId, messageWithAt);
    }
  }

  /// 触发AI响应
  /// 注意: 需要根据 atInfo.userId 获取联系人信息来构建prompt
  Future<void> triggerAIResponse(
    AtInfo atInfo,
    String groupId,
    GroupMessage message,
  ) async {
    // 检查WebSocket服务是否可用
    if (_wsService == null) {
      Logger.warning('[GroupChat] WebSocketService not initialized, cannot trigger AI response');
      return;
    }

    // 1. 通过 atName 在群成员中查找
    final atName = atInfo.atName;
    if (atName == null || atName.isEmpty) {
      Logger.debug('[GroupChat] atName is empty, cannot find member');
      return;
    }
    final member = await _db.getMemberByAtName(groupId, atName);
    if (member == null) {
      Logger.debug('[GroupChat] Member with atName $atName not found in group $groupId');
      return;
    }

    // 2. 获取联系人信息，确认是AI
    final contact = await _contactService.getContact(member.userId);
    if (contact == null || !contact.isAI) {
      Logger.debug('[GroupChat] Contact ${member.userId} is not an AI contact');
      return;
    }

    // 3. 跳过AI自己发送的消息，避免无限循环
    if (message.senderId == contact.id) {
      Logger.debug('[GroupChat] Skipping AI self-message to avoid infinite loop');
      return;
    }

    Logger.info('[GroupChat] Triggering AI response for ${contact.name} in group $groupId');

    // 4. 获取或创建群聊专属 session
    final sessionKey = 'group_${groupId}_ai_${contact.id}';
    _wsService!.selectSession(sessionKey, agentId: contact.id);

    // 5. 监听AI响应并保存到群消息
    _listenForAIResponse(sessionKey, groupId, contact);

    // 6. 发送消息给AI
    try {
      await _wsService!.sendMessage(message.content, sessionKey: sessionKey);
    } catch (e) {
      Logger.error('[GroupChat] Failed to send message to AI: $e');
    }
  }

  /// 监听AI响应并保存到群消息
  void _listenForAIResponse(String sessionKey, String groupId, Contact contact) {
    final session = _wsService?.getSession(sessionKey);
    if (session == null) {
      Logger.warning('[GroupChat] Session $sessionKey not found');
      return;
    }

    // 监听会话消息流
    session.messageStream.listen((msg) async {
      if (!msg.isUser && msg.text.isNotEmpty) {
        Logger.info('[GroupChat] Received AI response: ${msg.text.substring(0, msg.text.length > 50 ? 50 : msg.text.length)}...');

        // 创建AI响应消息
        final aiMessage = GroupMessage(
          id: msg.id,
          groupId: groupId,
          senderId: contact.id,
          senderName: contact.name,
          senderAvatar: contact.avatar,
          content: msg.text,
          timestamp: msg.timestamp,
          isDeleted: false,
        );

        // 保存到数据库
        await _saveGroupMessage(aiMessage);
      }
    });
  }

  /// 保存群消息到数据库
  Future<void> _saveGroupMessage(GroupMessage message) async {
    await sendGroupMessage(message);
  }

  /// 发送群消息（公开方法）
  Future<void> sendGroupMessage(GroupMessage message) async {
    final db = await _db.database;
    await db.insert(
      'group_messages',
      {
        'id': message.id,
        'group_id': message.groupId,
        'sender_id': message.senderId,
        'sender_name': message.senderName,
        'sender_avatar': message.senderAvatar,
        'content': message.content,
        'at_list': message.atList.map((a) => a.toJson()).toList().toString(),
        'timestamp': message.timestamp.toIso8601String(),
        'is_deleted': message.isDeleted ? 1 : 0,
      },
    );
    
    // 更新群的更新时间
    await db.update(
      'groups',
      {'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [message.groupId],
    );
  }

  /// 获取群聊消息历史
  Future<List<GroupMessage>> getGroupMessages(String groupId, {int limit = 50}) async {
    final db = await _db.database;
    final results = await db.query(
      'group_messages',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    
    return results.map((row) {
      return GroupMessage(
        id: row['id'] as String,
        groupId: row['group_id'] as String,
        senderId: row['sender_id'] as String,
        senderName: row['sender_name'] as String,
        senderAvatar: row['sender_avatar'] as String?,
        content: row['content'] as String,
        timestamp: DateTime.parse(row['timestamp'] as String),
        isDeleted: (row['is_deleted'] as int) == 1,
      );
    }).toList();
  }

  /// 创建群聊
  Future<GroupChat> createGroup(String name, List<String> memberIds) async {
    final db = await _db.database;
    final now = DateTime.now();
    final groupId = 'group_${now.millisecondsSinceEpoch}';
    
    // 创建群聊记录
    await db.insert('groups', {
      'id': groupId,
      'name': name,
      'avatar': null,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'is_active': 1,
    });
    
    // 获取联系人信息并添加群成员
    final members = <GroupMember>[];
    for (int i = 0; i < memberIds.length; i++) {
      final memberId = memberIds[i];
      
      // 从 contacts 表获取联系人信息
      final contactResults = await db.query(
        'contacts',
        where: 'id = ?',
        whereArgs: [memberId],
        limit: 1,
      );
      
      String userName = 'Member $i';
      String? userAvatar;
      String? atName;
      
      if (contactResults.isNotEmpty) {
        final contact = contactResults.first;
        userName = contact['name'] as String? ?? userName;
        userAvatar = contact['avatar'] as String?;
        atName = contact['atName'] as String?;
      }
      
      await db.insert('group_members', {
        'id': 'member_${now.millisecondsSinceEpoch}_$i',
        'group_id': groupId,
        'user_id': memberId,
        'user_name': userName,
        'user_avatar': userAvatar,
        'at_name': atName,
        'role': i == 0 ? 'owner' : 'member',
        'joined_at': now.toIso8601String(),
        'is_active': 1,
      });
      
      // 添加到 members 列表
      members.add(GroupMember(
        id: 'member_${now.millisecondsSinceEpoch}_$i',
        groupId: groupId,
        userId: memberId,
        userName: userName,
        userAvatar: userAvatar,
        atName: atName,
        role: i == 0 ? GroupMemberRole.owner : GroupMemberRole.member,
        joinedAt: now,
        isActive: true,
      ));
    }
    
    return GroupChat(
      id: groupId,
      name: name,
      members: members,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// 获取用户所在的群聊列表
  Future<List<GroupChat>> getUserGroups(String userId) async {
    final db = await _db.database;
    final results = await db.rawQuery('''
      SELECT g.* FROM groups g
      INNER JOIN group_members gm ON g.id = gm.group_id
      WHERE gm.user_id = ? AND g.is_active = 1 AND gm.is_active = 1
      ORDER BY g.updated_at DESC
    ''', [userId]);
    
    final List<GroupChat> groups = [];
    for (final row in results) {
      final members = await _getGroupMembers(row['id'] as String);
      groups.add(GroupChat(
        id: row['id'] as String,
        name: row['name'] as String,
        avatar: row['avatar'] as String?,
        members: members,
        createdAt: DateTime.parse(row['created_at'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
        isActive: (row['is_active'] as int) == 1,
        showInSessionList: (row['show_in_session_list'] as int?) == 1,
      ));
    }
    
    return groups;
  }

  /// 获取所有群聊（可选择是否在会话列表显示）
  Future<List<GroupChat>> getAllGroups({bool? showInSessionList}) async {
    final db = await _db.database;
    String? where;
    List<dynamic>? whereArgs;
    
    if (showInSessionList != null) {
      where = 'is_active = 1 AND show_in_session_list = ?';
      whereArgs = [showInSessionList ? 1 : 0];
    } else {
      where = 'is_active = 1';
    }
    
    final results = await db.query(
      'groups',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'updated_at DESC',
    );
    
    final List<GroupChat> groups = [];
    for (final row in results) {
      final members = await _getGroupMembers(row['id'] as String);
      groups.add(GroupChat(
        id: row['id'] as String,
        name: row['name'] as String,
        avatar: row['avatar'] as String?,
        members: members,
        createdAt: DateTime.parse(row['created_at'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
        isActive: (row['is_active'] as int) == 1,
        showInSessionList: (row['show_in_session_list'] as int?) == 1,
      ));
    }
    
    return groups;
  }

  /// 隐藏群聊（从会话列表中移除）
  Future<void> hideGroupFromSessionList(String groupId) async {
    await _db.updateGroupShowInSessionList(groupId, false);
  }

  /// 显示群聊（恢复到会话列表）
  Future<void> showGroupInSessionList(String groupId) async {
    await _db.updateGroupShowInSessionList(groupId, true);
  }

  /// 获取群聊的最后一条消息
  Future<GroupMessage?> getGroupLastMessage(String groupId) async {
    final db = await _db.database;
    final results = await db.query(
      'group_messages',
      where: 'group_id = ? AND is_deleted = 0',
      whereArgs: [groupId],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    
    if (results.isEmpty) return null;
    
    final row = results.first;
    return GroupMessage(
      id: row['id'] as String,
      groupId: row['group_id'] as String,
      senderId: row['sender_id'] as String,
      senderName: row['sender_name'] as String,
      senderAvatar: row['sender_avatar'] as String?,
      content: row['content'] as String,
      timestamp: DateTime.parse(row['timestamp'] as String),
      isDeleted: (row['is_deleted'] as int) == 1,
    );
  }

  /// 获取群成员列表
  Future<List<GroupMember>> _getGroupMembers(String groupId) async {
    final db = await _db.database;
    final results = await db.query(
      'group_members',
      where: 'group_id = ? AND is_active = 1',
      whereArgs: [groupId],
    );
    
    return results.map((row) {
      return GroupMember(
        id: row['id'] as String,
        groupId: row['group_id'] as String,
        userId: row['user_id'] as String,
        userName: row['user_name'] as String,
        userAvatar: row['user_avatar'] as String?,
        atName: row['at_name'] as String?,
        role: GroupMemberRole.values.firstWhere(
          (e) => e.toString() == 'GroupMemberRole.${row['role']}',
          orElse: () => GroupMemberRole.member,
        ),
        joinedAt: DateTime.parse(row['joined_at'] as String),
        isActive: (row['is_active'] as int) == 1,
      );
    }).toList();
  }
}
