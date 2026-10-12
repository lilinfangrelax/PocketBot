/// The folder a group chat works in: a saved host and a path on it. Every AI
/// member answers there, each in its own ACP session.
class GroupWorkspace {
  final String groupId;

  /// [GatewayInfo.hostId] of the saved host.
  final String hostId;
  final String workingDirectory;
  final DateTime updatedAt;

  GroupWorkspace({
    required this.groupId,
    required this.hostId,
    required this.workingDirectory,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  bool get isSet => hostId.isNotEmpty && workingDirectory.trim().isNotEmpty;

  Map<String, dynamic> toDbMap() => {
        'group_id': groupId,
        'host_id': hostId,
        'working_directory': workingDirectory,
        'updated_at': updatedAt.toIso8601String(),
      };

  factory GroupWorkspace.fromDbMap(Map<String, dynamic> map) {
    return GroupWorkspace(
      groupId: map['group_id'] as String? ?? '',
      hostId: map['host_id'] as String? ?? '',
      workingDirectory: map['working_directory'] as String? ?? '',
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String)
          : null,
    );
  }
}
