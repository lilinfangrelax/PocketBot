import 'package:uuid/uuid.dart';

enum ChangeType {
  joined,
  left,
  removed,
  promoted,
}

class MemberChangeLog {
  final String id;
  final String groupId;
  final ChangeType changeType;
  final String memberId;
  final String? operatorId;
  final DateTime timestamp;

  MemberChangeLog({
    String? id,
    required this.groupId,
    required this.changeType,
    required this.memberId,
    this.operatorId,
    DateTime? timestamp,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'groupId': groupId,
      'changeType': changeType.toString().split('.').last,
      'memberId': memberId,
      'operatorId': operatorId,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory MemberChangeLog.fromMap(Map<String, dynamic> map) {
    return MemberChangeLog(
      id: map['id'],
      groupId: map['groupId'],
      changeType: ChangeType.values.firstWhere(
        (e) => e.toString() == 'ChangeType.${map['changeType']}',
        orElse: () => ChangeType.joined,
      ),
      memberId: map['memberId'],
      operatorId: map['operatorId'],
      timestamp: DateTime.parse(map['timestamp']),
    );
  }

  MemberChangeLog copyWith({
    String? id,
    String? groupId,
    ChangeType? changeType,
    String? memberId,
    String? operatorId,
    DateTime? timestamp,
  }) {
    return MemberChangeLog(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      changeType: changeType ?? this.changeType,
      memberId: memberId ?? this.memberId,
      operatorId: operatorId ?? this.operatorId,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MemberChangeLog && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
