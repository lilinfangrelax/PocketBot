import 'package:flutter/foundation.dart';

/// 联系人模型
class Contact {
  final String id;
  final String name;
  final String? atName;
  final String? avatar;
  final bool isActive;
  final bool isAI;
  final DateTime createdAt;
  final DateTime updatedAt;

  Contact({
    required this.id,
    required this.name,
    this.atName,
    this.avatar,
    this.isActive = true,
    this.isAI = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Contact.fromJson(Map<String, dynamic> json) {
    return Contact(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      atName: json['atName'],
      avatar: json['avatar'],
      isActive: json['isActive'] ?? true,
      isAI: json['isAI'] ?? false,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'atName': atName,
      'avatar': avatar,
      'isActive': isActive,
      'isAI': isAI,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  Contact copyWith({
    String? id,
    String? name,
    String? atName,
    String? avatar,
    bool? isActive,
    bool? isAI,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Contact(
      id: id ?? this.id,
      name: name ?? this.name,
      atName: atName ?? this.atName,
      avatar: avatar ?? this.avatar,
      isActive: isActive ?? this.isActive,
      isAI: isAI ?? this.isAI,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Contact && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

/// 联系人变更日志
class ContactChangeLog {
  final String id;
  final String contactId;
  final ContactChangeType changeType;
  final String? oldValue;
  final String? newValue;
  final DateTime createdAt;

  ContactChangeLog({
    required this.id,
    required this.contactId,
    required this.changeType,
    this.oldValue,
    this.newValue,
    required this.createdAt,
  });

  factory ContactChangeLog.fromJson(Map<String, dynamic> json) {
    return ContactChangeLog(
      id: json['id'] ?? '',
      contactId: json['contactId'] ?? '',
      changeType: ContactChangeType.values.firstWhere(
        (e) => e.toString() == 'ContactChangeType.${json['changeType']}',
        orElse: () => ContactChangeType.created,
      ),
      oldValue: json['oldValue'],
      newValue: json['newValue'],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'contactId': contactId,
      'changeType': changeType.toString().split('.').last,
      'oldValue': oldValue,
      'newValue': newValue,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

enum ContactChangeType {
  created,
  updated,
  deleted,
  nameChanged,
  avatarChanged,
  statusChanged,
}
