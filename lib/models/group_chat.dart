/// 群聊模型
class GroupChat {
  final String id;
  final String name;
  final String? avatar;
  final List<GroupMember> members;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isActive;
  final bool showInSessionList; // 是否在会话列表显示

  GroupChat({
    required this.id,
    required this.name,
    this.avatar,
    required this.members,
    required this.createdAt,
    required this.updatedAt,
    this.isActive = true,
    this.showInSessionList = true,
  });

  factory GroupChat.fromJson(Map<String, dynamic> json) {
    return GroupChat(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      avatar: json['avatar'],
      members: (json['members'] as List?)
              ?.map((m) => GroupMember.fromJson(m))
              .toList() ??
          [],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : DateTime.now(),
      isActive: json['isActive'] ?? true,
      showInSessionList: json['showInSessionList'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'avatar': avatar,
      'members': members.map((m) => m.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isActive': isActive,
      'showInSessionList': showInSessionList,
    };
  }

  GroupChat copyWith({
    String? id,
    String? name,
    String? avatar,
    List<GroupMember>? members,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isActive,
    bool? showInSessionList,
  }) {
    return GroupChat(
      id: id ?? this.id,
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      members: members ?? this.members,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isActive: isActive ?? this.isActive,
      showInSessionList: showInSessionList ?? this.showInSessionList,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GroupChat && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

/// 群成员模型
class GroupMember {
  final String id;
  final String groupId;
  final String userId;
  final String userName;
  final String? userAvatar;
  final String? atName; // @名称，用于群聊中@他人
  final GroupMemberRole role;
  final DateTime joinedAt;
  final bool isActive;
  final bool isAI; // 是否是AI联系人
  final String? agentId; // AI联系人对应的agent ID

  GroupMember({
    required this.id,
    required this.groupId,
    required this.userId,
    required this.userName,
    this.userAvatar,
    this.atName,
    required this.role,
    required this.joinedAt,
    this.isActive = true,
    this.isAI = false,
    this.agentId,
  });

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      id: json['id'] ?? '',
      groupId: json['groupId'] ?? '',
      userId: json['userId'] ?? '',
      userName: json['userName'] ?? '',
      userAvatar: json['userAvatar'],
      atName: json['atName'],
      role: GroupMemberRole.values.firstWhere(
        (e) => e.toString() == 'GroupMemberRole.${json['role']}',
        orElse: () => GroupMemberRole.member,
      ),
      joinedAt: json['joinedAt'] != null
          ? DateTime.parse(json['joinedAt'])
          : DateTime.now(),
      isActive: json['isActive'] ?? true,
      isAI: json['isAI'] ?? false,
      agentId: json['agentId'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'groupId': groupId,
      'userId': userId,
      'userName': userName,
      'userAvatar': userAvatar,
      'atName': atName,
      'role': role.toString().split('.').last,
      'joinedAt': joinedAt.toIso8601String(),
      'isActive': isActive,
      'isAI': isAI,
      'agentId': agentId,
    };
  }

  GroupMember copyWith({
    String? id,
    String? groupId,
    String? userId,
    String? userName,
    String? userAvatar,
    String? atName,
    GroupMemberRole? role,
    DateTime? joinedAt,
    bool? isActive,
    bool? isAI,
    String? agentId,
  }) {
    return GroupMember(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userAvatar: userAvatar ?? this.userAvatar,
      atName: atName ?? this.atName,
      role: role ?? this.role,
      joinedAt: joinedAt ?? this.joinedAt,
      isActive: isActive ?? this.isActive,
      isAI: isAI ?? this.isAI,
      agentId: agentId ?? this.agentId,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GroupMember && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

enum GroupMemberRole {
  owner,   // 群主
  admin,   // 管理员
  member,  // 普通成员
}

/// 群消息模型
class GroupMessage {
  final String id;
  final String groupId;
  final String senderId;
  final String senderName;
  final String? senderAvatar;
  final String content;
  final List<AtInfo> atList; // @信息列表
  final DateTime timestamp;
  final bool isDeleted;

  GroupMessage({
    required this.id,
    required this.groupId,
    required this.senderId,
    required this.senderName,
    this.senderAvatar,
    required this.content,
    this.atList = const [],
    required this.timestamp,
    this.isDeleted = false,
  });

  factory GroupMessage.fromJson(Map<String, dynamic> json) {
    return GroupMessage(
      id: json['id'] ?? '',
      groupId: json['groupId'] ?? '',
      senderId: json['senderId'] ?? '',
      senderName: json['senderName'] ?? '',
      senderAvatar: json['senderAvatar'],
      content: json['content'] ?? '',
      atList: (json['atList'] as List?)
              ?.map((a) => AtInfo.fromJson(a))
              .toList() ??
          [],
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
      isDeleted: json['isDeleted'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'groupId': groupId,
      'senderId': senderId,
      'senderName': senderName,
      'senderAvatar': senderAvatar,
      'content': content,
      'atList': atList.map((a) => a.toJson()).toList(),
      'timestamp': timestamp.toIso8601String(),
      'isDeleted': isDeleted,
    };
  }

  GroupMessage copyWith({
    String? id,
    String? groupId,
    String? senderId,
    String? senderName,
    String? senderAvatar,
    String? content,
    List<AtInfo>? atList,
    DateTime? timestamp,
    bool? isDeleted,
  }) {
    return GroupMessage(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      senderAvatar: senderAvatar ?? this.senderAvatar,
      content: content ?? this.content,
      atList: atList ?? this.atList,
      timestamp: timestamp ?? this.timestamp,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GroupMessage && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

/// @信息模型
class AtInfo {
  final String userId;
  final String userName;
  final String? atName; // @名称
  final int position; // @在消息中的位置
  final int length; // @名称的长度

  AtInfo({
    required this.userId,
    required this.userName,
    this.atName,
    required this.position,
    required this.length,
  });

  factory AtInfo.fromJson(Map<String, dynamic> json) {
    return AtInfo(
      userId: json['userId'] ?? '',
      userName: json['userName'] ?? '',
      atName: json['atName'],
      position: json['position'] ?? 0,
      length: json['length'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'userName': userName,
      'atName': atName,
      'position': position,
      'length': length,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AtInfo &&
        other.userId == userId &&
        other.position == position;
  }

  @override
  int get hashCode => userId.hashCode ^ position.hashCode;
}
