import 'package:uuid/uuid.dart';

class MessageReaction {
  final String id;
  final String messageId;
  final String memberId;
  final String emoji;
  final DateTime createdAt;

  MessageReaction({
    String? id,
    required this.messageId,
    required this.memberId,
    required this.emoji,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'messageId': messageId,
      'memberId': memberId,
      'emoji': emoji,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory MessageReaction.fromMap(Map<String, dynamic> map) {
    return MessageReaction(
      id: map['id'],
      messageId: map['messageId'],
      memberId: map['memberId'],
      emoji: map['emoji'],
      createdAt: DateTime.parse(map['createdAt']),
    );
  }

  MessageReaction copyWith({
    String? id,
    String? messageId,
    String? memberId,
    String? emoji,
    DateTime? createdAt,
  }) {
    return MessageReaction(
      id: id ?? this.id,
      messageId: messageId ?? this.messageId,
      memberId: memberId ?? this.memberId,
      emoji: emoji ?? this.emoji,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MessageReaction && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
