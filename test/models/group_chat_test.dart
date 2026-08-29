import 'package:pocket_bot/models/group_chat.dart';
import 'package:test/test.dart';

void main() {
  group('GroupChat Model Tests', () {
    test('Create group chat with all fields', () {
      final now = DateTime.now();
      final members = [
        GroupMember(
          id: 'member-1',
          groupId: 'group-1',
          userId: 'user-1',
          userName: 'Alice',
          role: GroupMemberRole.owner,
          joinedAt: now,
        ),
      ];

      final group = GroupChat(
        id: 'group-1',
        name: 'Test Group',
        avatar: 'https://example.com/avatar.png',
        members: members,
        createdAt: now,
        updatedAt: now,
        isActive: true,
      );

      expect(group.id, 'group-1');
      expect(group.name, 'Test Group');
      expect(group.avatar, 'https://example.com/avatar.png');
      expect(group.members.length, 1);
      expect(group.isActive, true);
    });

    test('GroupChat to JSON', () {
      final now = DateTime(2024, 1, 1, 12, 0, 0);
      final group = GroupChat(
        id: 'group-1',
        name: 'Test Group',
        members: [],
        createdAt: now,
        updatedAt: now,
      );

      final json = group.toJson();

      expect(json['id'], 'group-1');
      expect(json['name'], 'Test Group');
      expect(json['isActive'], true);
    });

    test('GroupChat from JSON', () {
      final json = {
        'id': 'group-1',
        'name': 'Test Group',
        'avatar': 'https://example.com/avatar.png',
        'members': [],
        'createdAt': '2024-01-01T12:00:00.000',
        'updatedAt': '2024-01-01T12:00:00.000',
        'isActive': true,
      };

      final group = GroupChat.fromJson(json);

      expect(group.id, 'group-1');
      expect(group.name, 'Test Group');
      expect(group.avatar, 'https://example.com/avatar.png');
      expect(group.isActive, true);
    });

    test('GroupChat copyWith', () {
      final now = DateTime.now();
      final group = GroupChat(
        id: 'group-1',
        name: 'Original Name',
        members: [],
        createdAt: now,
        updatedAt: now,
      );

      final updated = group.copyWith(name: 'New Name');

      expect(updated.name, 'New Name');
      expect(updated.id, 'group-1'); // unchanged
    });

    test('GroupChat equality', () {
      final now = DateTime.now();
      final group1 = GroupChat(
        id: 'group-1',
        name: 'Group',
        members: [],
        createdAt: now,
        updatedAt: now,
      );

      final group2 = GroupChat(
        id: 'group-1',
        name: 'Different Name',
        members: [],
        createdAt: now,
        updatedAt: now,
      );

      expect(group1, equals(group2)); // same id
    });
  });

  group('GroupMember Model Tests', () {
    test('Create group member with all fields', () {
      final now = DateTime.now();
      final member = GroupMember(
        id: 'member-1',
        groupId: 'group-1',
        userId: 'user-1',
        userName: 'Alice',
        userAvatar: 'https://example.com/alice.png',
        atName: 'alice',
        role: GroupMemberRole.admin,
        joinedAt: now,
        isActive: true,
      );

      expect(member.id, 'member-1');
      expect(member.userName, 'Alice');
      expect(member.atName, 'alice');
      expect(member.role, GroupMemberRole.admin);
    });

    test('GroupMember to JSON', () {
      final now = DateTime(2024, 1, 1, 12, 0, 0);
      final member = GroupMember(
        id: 'member-1',
        groupId: 'group-1',
        userId: 'user-1',
        userName: 'Alice',
        role: GroupMemberRole.member,
        joinedAt: now,
      );

      final json = member.toJson();

      expect(json['id'], 'member-1');
      expect(json['userName'], 'Alice');
      expect(json['role'], 'member');
    });

    test('GroupMember from JSON', () {
      final json = {
        'id': 'member-1',
        'groupId': 'group-1',
        'userId': 'user-1',
        'userName': 'Alice',
        'userAvatar': null,
        'atName': 'alice',
        'role': 'admin',
        'joinedAt': '2024-01-01T12:00:00.000',
        'isActive': true,
      };

      final member = GroupMember.fromJson(json);

      expect(member.userName, 'Alice');
      expect(member.atName, 'alice');
      expect(member.role, GroupMemberRole.admin);
    });

    test('GroupMember copyWith', () {
      final now = DateTime.now();
      final member = GroupMember(
        id: 'member-1',
        groupId: 'group-1',
        userId: 'user-1',
        userName: 'Alice',
        role: GroupMemberRole.member,
        joinedAt: now,
      );

      final updated = member.copyWith(role: GroupMemberRole.admin);

      expect(updated.role, GroupMemberRole.admin);
      expect(updated.userName, 'Alice'); // unchanged
    });
  });

  group('GroupMessage Model Tests', () {
    test('Create group message with all fields', () {
      final now = DateTime.now();
      final atList = [
        AtInfo(
          userId: 'user-1',
          userName: 'Alice',
          atName: 'alice',
          position: 0,
          length: 6,
        ),
      ];

      final message = GroupMessage(
        id: 'msg-1',
        groupId: 'group-1',
        senderId: 'user-2',
        senderName: 'Bob',
        senderAvatar: 'https://example.com/bob.png',
        content: '@alice Hello!',
        atList: atList,
        timestamp: now,
        isDeleted: false,
      );

      expect(message.id, 'msg-1');
      expect(message.groupId, 'group-1');
      expect(message.senderName, 'Bob');
      expect(message.atList.length, 1);
    });

    test('GroupMessage to JSON', () {
      final now = DateTime(2024, 1, 1, 12, 0, 0);
      final message = GroupMessage(
        id: 'msg-1',
        groupId: 'group-1',
        senderId: 'user-1',
        senderName: 'Alice',
        content: 'Hello',
        timestamp: now,
      );

      final json = message.toJson();

      expect(json['id'], 'msg-1');
      expect(json['groupId'], 'group-1');
      expect(json['senderName'], 'Alice');
      expect(json['isDeleted'], false);
    });

    test('GroupMessage from JSON', () {
      final json = {
        'id': 'msg-1',
        'groupId': 'group-1',
        'senderId': 'user-1',
        'senderName': 'Alice',
        'senderAvatar': null,
        'content': 'Hello',
        'atList': [],
        'timestamp': '2024-01-01T12:00:00.000',
        'isDeleted': false,
      };

      final message = GroupMessage.fromJson(json);

      expect(message.id, 'msg-1');
      expect(message.content, 'Hello');
    });

    test('GroupMessage copyWith', () {
      final now = DateTime.now();
      final message = GroupMessage(
        id: 'msg-1',
        groupId: 'group-1',
        senderId: 'user-1',
        senderName: 'Alice',
        content: 'Original',
        timestamp: now,
      );

      final updated = message.copyWith(content: 'Updated');

      expect(updated.content, 'Updated');
      expect(updated.id, 'msg-1'); // unchanged
    });
  });

  group('AtInfo Model Tests', () {
    test('Create AtInfo with all fields', () {
      final atInfo = AtInfo(
        userId: 'user-1',
        userName: 'Alice',
        atName: 'alice',
        position: 5,
        length: 6,
      );

      expect(atInfo.userId, 'user-1');
      expect(atInfo.atName, 'alice');
      expect(atInfo.position, 5);
      expect(atInfo.length, 6);
    });

    test('AtInfo to JSON', () {
      final atInfo = AtInfo(
        userId: 'user-1',
        userName: 'Alice',
        atName: 'alice',
        position: 5,
        length: 6,
      );

      final json = atInfo.toJson();

      expect(json['userId'], 'user-1');
      expect(json['atName'], 'alice');
      expect(json['position'], 5);
    });

    test('AtInfo from JSON', () {
      final json = {
        'userId': 'user-1',
        'userName': 'Alice',
        'atName': 'alice',
        'position': 5,
        'length': 6,
      };

      final atInfo = AtInfo.fromJson(json);

      expect(atInfo.userId, 'user-1');
      expect(atInfo.position, 5);
    });

    test('AtInfo equality', () {
      final atInfo1 = AtInfo(
        userId: 'user-1',
        userName: 'Alice',
        position: 5,
        length: 6,
      );

      final atInfo2 = AtInfo(
        userId: 'user-1',
        userName: 'Alice',
        position: 5,
        length: 10,
      );

      expect(atInfo1, equals(atInfo2)); // same userId and position
    });
  });

  group('GroupMemberRole Tests', () {
    test('GroupMemberRole values exist', () {
      expect(GroupMemberRole.values.length, 3);
      expect(GroupMemberRole.values.contains(GroupMemberRole.owner), true);
      expect(GroupMemberRole.values.contains(GroupMemberRole.admin), true);
      expect(GroupMemberRole.values.contains(GroupMemberRole.member), true);
    });
  });

  group('GroupMember isAI Tests', () {
    test('should create GroupMember with isAI true', () {
      final now = DateTime.now();
      final member = GroupMember(
        id: 'member-1',
        groupId: 'group-1',
        userId: 'ai-assistant',
        userName: 'AI助手',
        role: GroupMemberRole.member,
        joinedAt: now,
        isAI: true,
        agentId: 'agent-123',
      );

      expect(member.isAI, true);
      expect(member.agentId, 'agent-123');
    });

    test('should serialize isAI and agentId to JSON', () {
      final now = DateTime.now();
      final member = GroupMember(
        id: 'member-1',
        groupId: 'group-1',
        userId: 'ai-user',
        userName: 'AI User',
        role: GroupMemberRole.member,
        joinedAt: now,
        isAI: true,
        agentId: 'agent-456',
      );

      final json = member.toJson();

      expect(json['isAI'], true);
      expect(json['agentId'], 'agent-456');
    });

    test('should deserialize isAI and agentId from JSON', () {
      final json = {
        'id': 'member-1',
        'groupId': 'group-1',
        'userId': 'ai-user',
        'userName': 'AI User',
        'role': 'member',
        'joinedAt': '2024-01-01T00:00:00.000',
        'isAI': true,
        'agentId': 'agent-789',
      };

      final member = GroupMember.fromJson(json);

      expect(member.isAI, true);
      expect(member.agentId, 'agent-789');
    });

    test('copyWith should update isAI and agentId', () {
      final now = DateTime.now();
      final original = GroupMember(
        id: 'member-1',
        groupId: 'group-1',
        userId: 'user-1',
        userName: 'User',
        role: GroupMemberRole.member,
        joinedAt: now,
      );

      final updated = original.copyWith(isAI: true, agentId: 'agent-999');

      expect(updated.isAI, true);
      expect(updated.agentId, 'agent-999');
    });
  });
}
