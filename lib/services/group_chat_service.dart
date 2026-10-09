import 'dart:async';
import 'package:pocket_bot/models/group_chat.dart';
import 'package:pocket_bot/models/ai_contact_config.dart';
import 'package:pocket_bot/services/database_service.dart';
import 'package:pocket_bot/services/contact_agent_linker.dart';
import 'package:pocket_bot/utils/logger.dart';

/// 群聊服务 - 处理@提及解析和AI触发逻辑
class GroupChatService {
  static final GroupChatService _instance = GroupChatService._internal();
  factory GroupChatService() => _instance;
  GroupChatService._internal();

  final DatabaseService _db = DatabaseService();
  /// Set at startup; resolves AI members to their agent connections.
  ContactAgentLinker? linker;

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

  /// Members that should answer [message]: AI members mentioned by @name,
  /// plus AI members set to reply to every message. Never the sender.
  static List<GroupMember> agentTargets({
    required GroupMessage message,
    required List<GroupMember> members,
    required Map<String, AIContactConfig> configs,
    required List<AtInfo> mentions,
  }) {
    final mentioned = mentions
        .map((at) => at.atName?.toLowerCase())
        .whereType<String>()
        .toSet();
    final targets = <GroupMember>[];
    for (final member in members) {
      final config = configs[member.userId];
      if (config == null || member.userId == message.senderId) continue;
      final names = {
        member.atName?.toLowerCase(),
        member.userName.toLowerCase(),
      }.whereType<String>();
      final isMentioned = names.any(mentioned.contains);
      if (isMentioned || config.autoReply) targets.add(member);
    }
    return targets;
  }

  static String groupPrompt(GroupChat group, GroupMessage message) =>
      '群聊「${group.name}」中，${message.senderName} 说：\n${message.content}';

  /// Sends [message] to every agent that should answer it and stores each
  /// reply as a group message. [onStatus] reports who is thinking or failed.
  Future<List<GroupMessage>> dispatchToAgents(
    GroupChat group,
    GroupMessage message, {
    void Function(String memberName, String? error)? onStatus,
  }) async {
    final linker = this.linker;
    if (linker == null) {
      Logger.warning('[GroupChat] No agent linker, skipping AI replies');
      return const [];
    }
    final configs = <String, AIContactConfig>{};
    for (final member in group.members) {
      final config = await linker.configFor(member.userId);
      if (config != null) configs[member.userId] = config;
    }
    final targets = agentTargets(
      message: message,
      members: group.members,
      configs: configs,
      mentions: parseAtMentionsSync(message.content),
    );

    final replies = await Future.wait(targets.map((member) async {
      final config = configs[member.userId]!;
      onStatus?.call(member.userName, null);
      try {
        final service = await linker.serviceFor(config);
        final sessionKey = await linker.sessionFor(
          service: service,
          contactId: member.userId,
          groupId: group.id,
          title: '${group.name} · ${member.userName}',
        );
        final text = await service.sendMessageAndWait(
          groupPrompt(group, message),
          sessionKey: sessionKey,
        );
        if (text.trim().isEmpty) return null;
        final reply = GroupMessage(
          id: 'msg_${DateTime.now().microsecondsSinceEpoch}_${member.userId}',
          groupId: group.id,
          senderId: member.userId,
          senderName: member.userName,
          senderAvatar: member.userAvatar,
          content: text,
          timestamp: DateTime.now(),
        );
        await sendGroupMessage(reply);
        return reply;
      } catch (error) {
        Logger.warning('[GroupChat] ${member.userName} failed: $error');
        onStatus?.call(
          member.userName,
          error.toString().replaceFirst('Exception: ', ''),
        );
        return null;
      }
    }));
    return replies.whereType<GroupMessage>().toList();
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
