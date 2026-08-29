/// AI 联系人 + 群聊 → Session 映射
class ContactSessionMapping {
  final String id;
  final String contactId; // AI 联系人 ID
  final String groupId; // 群聊 ID
  final String sessionKey; // Corresponding ACP sessionId
  final DateTime createdAt;
  final DateTime lastActiveAt;
  final int messageCount; // 累计消息数

  ContactSessionMapping({
    this.id = '',
    required this.contactId,
    required this.groupId,
    required this.sessionKey,
    DateTime? createdAt,
    DateTime? lastActiveAt,
    this.messageCount = 0,
  })  : createdAt = createdAt ?? DateTime.now(),
        lastActiveAt = lastActiveAt ?? DateTime.now();

  factory ContactSessionMapping.fromJson(Map<String, dynamic> json) {
    return ContactSessionMapping(
      id: json['id'] ?? '',
      contactId: json['contactId'] ?? '',
      groupId: json['groupId'] ?? '',
      sessionKey: json['sessionKey'] ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      lastActiveAt: json['lastActiveAt'] != null
          ? DateTime.parse(json['lastActiveAt'])
          : DateTime.now(),
      messageCount: json['messageCount'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'contactId': contactId,
      'groupId': groupId,
      'sessionKey': sessionKey,
      'createdAt': createdAt.toIso8601String(),
      'lastActiveAt': lastActiveAt.toIso8601String(),
      'messageCount': messageCount,
    };
  }

  /// 转换为数据库存储格式
  Map<String, dynamic> toDbMap() {
    return {
      'id': id,
      'contact_id': contactId,
      'group_id': groupId,
      'session_key': sessionKey,
      'created_at': createdAt.toIso8601String(),
      'last_active_at': lastActiveAt.toIso8601String(),
      'message_count': messageCount,
    };
  }

  /// 从数据库格式创建
  factory ContactSessionMapping.fromDbMap(Map<String, dynamic> map) {
    return ContactSessionMapping(
      id: map['id'] ?? '',
      contactId: map['contact_id'] ?? '',
      groupId: map['group_id'] ?? '',
      sessionKey: map['session_key'] ?? '',
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'])
          : DateTime.now(),
      lastActiveAt: map['last_active_at'] != null
          ? DateTime.parse(map['last_active_at'])
          : DateTime.now(),
      messageCount: map['message_count'] ?? 0,
    );
  }

  ContactSessionMapping copyWith({
    String? id,
    String? contactId,
    String? groupId,
    String? sessionKey,
    DateTime? createdAt,
    DateTime? lastActiveAt,
    int? messageCount,
  }) {
    return ContactSessionMapping(
      id: id ?? this.id,
      contactId: contactId ?? this.contactId,
      groupId: groupId ?? this.groupId,
      sessionKey: sessionKey ?? this.sessionKey,
      createdAt: createdAt ?? this.createdAt,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      messageCount: messageCount ?? this.messageCount,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ContactSessionMapping &&
        other.contactId == contactId &&
        other.groupId == groupId;
  }

  @override
  int get hashCode => contactId.hashCode ^ groupId.hashCode;
}
