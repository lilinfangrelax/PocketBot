import 'package:uuid/uuid.dart';

enum AckType {
  received,  // 已收到
  read,      // 已读
  emoji,     // 表情确认
  quoted,    // 引用回复
}

class MessageAck {
  final String id;
  final String messageId;
  final String memberId;
  final AckType type;
  final String? emoji;
  final DateTime createdAt;

  MessageAck({
    String? id,
    required this.messageId,
    required this.memberId,
    required this.type,
    this.emoji,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'messageId': messageId,
      'memberId': memberId,
      'type': type.toString().split('.').last,
      'emoji': emoji,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory MessageAck.fromMap(Map<String, dynamic> map) {
    return MessageAck(
      id: map['id'],
      messageId: map['messageId'],
      memberId: map['memberId'],
      type: AckType.values.firstWhere(
        (e) => e.toString() == 'AckType.${map['type']}',
        orElse: () => AckType.received,
      ),
      emoji: map['emoji'],
      createdAt: DateTime.parse(map['createdAt']),
    );
  }

  MessageAck copyWith({
    String? id,
    String? messageId,
    String? memberId,
    AckType? type,
    String? emoji,
    DateTime? createdAt,
  }) {
    return MessageAck(
      id: id ?? this.id,
      messageId: messageId ?? this.messageId,
      memberId: memberId ?? this.memberId,
      type: type ?? this.type,
      emoji: emoji ?? this.emoji,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MessageAck && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
