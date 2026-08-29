import 'package:pocket_bot/models/contact.dart';
import 'package:pocket_bot/models/group_chat.dart';
import 'package:pocket_bot/services/contact_service.dart';
import 'package:test/test.dart';

void main() {
  group('ContactChangeLog Tests', () {
    test('should create ContactChangeLog with all fields', () {
      final now = DateTime.now();
      final log = ContactChangeLog(
        id: 'log-1',
        contactId: 'contact-1',
        changeType: ContactChangeType.nameChanged,
        oldValue: 'Old Name',
        newValue: 'New Name',
        createdAt: now,
      );

      expect(log.id, 'log-1');
      expect(log.contactId, 'contact-1');
      expect(log.changeType, ContactChangeType.nameChanged);
      expect(log.oldValue, 'Old Name');
      expect(log.newValue, 'New Name');
    });

    test('should serialize ContactChangeLog to JSON', () {
      final now = DateTime(2024, 1, 1);
      final log = ContactChangeLog(
        id: 'log-1',
        contactId: 'contact-1',
        changeType: ContactChangeType.created,
        newValue: 'Test Contact',
        createdAt: now,
      );

      final json = log.toJson();

      expect(json['id'], 'log-1');
      expect(json['changeType'], 'created');
    });

    test('should deserialize ContactChangeLog from JSON', () {
      final json = {
        'id': 'log-1',
        'contactId': 'contact-1',
        'changeType': 'nameChanged',
        'oldValue': 'Old',
        'newValue': 'New',
        'createdAt': '2024-01-01T00:00:00.000',
      };

      final log = ContactChangeLog.fromJson(json);

      expect(log.changeType, ContactChangeType.nameChanged);
      expect(log.oldValue, 'Old');
      expect(log.newValue, 'New');
    });

    test('should handle unknown change type', () {
      final json = {
        'id': 'log-1',
        'contactId': 'contact-1',
        'changeType': 'unknownType',
        'createdAt': '2024-01-01T00:00:00.000',
      };

      final log = ContactChangeLog.fromJson(json);

      expect(log.changeType, ContactChangeType.created); // default
    });
  });

  group('ContactChangeType Enum Tests', () {
    test('should have all expected change types', () {
      expect(ContactChangeType.values.length, 6);
      expect(ContactChangeType.values, contains(ContactChangeType.created));
      expect(ContactChangeType.values, contains(ContactChangeType.updated));
      expect(ContactChangeType.values, contains(ContactChangeType.deleted));
      expect(ContactChangeType.values, contains(ContactChangeType.nameChanged));
      expect(ContactChangeType.values, contains(ContactChangeType.avatarChanged));
      expect(ContactChangeType.values, contains(ContactChangeType.statusChanged));
    });
  });

  group('Contact Model Extended Tests', () {
    test('should create contact with all fields', () {
      final now = DateTime.now();
      final contact = Contact(
        id: 'contact-1',
        name: 'Test User',
        atName: 'testuser',
        avatar: 'https://example.com/avatar.png',
        isActive: true,
        isAI: false,
        createdAt: now,
        updatedAt: now,
      );

      expect(contact.id, 'contact-1');
      expect(contact.name, 'Test User');
      expect(contact.atName, 'testuser');
      expect(contact.avatar, 'https://example.com/avatar.png');
      expect(contact.isActive, true);
      expect(contact.isAI, false);
    });

    test('should serialize and deserialize contact with all fields', () {
      final now = DateTime(2024, 1, 1);
      final original = Contact(
        id: 'contact-1',
        name: 'Test User',
        atName: 'testuser',
        avatar: 'https://example.com/avatar.png',
        isActive: true,
        isAI: true,
        createdAt: now,
        updatedAt: now,
      );

      final json = original.toJson();
      final restored = Contact.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.atName, original.atName);
      expect(restored.avatar, original.avatar);
      expect(restored.isActive, original.isActive);
      expect(restored.isAI, original.isAI);
    });

    test('copyWith should work with all fields', () {
      final now = DateTime.now();
      final original = Contact(
        id: 'contact-1',
        name: 'Original Name',
        atName: 'original',
        isAI: false,
        createdAt: now,
        updatedAt: now,
      );

      final copied = original.copyWith(
        name: 'New Name',
        atName: 'new',
        isAI: true,
        isActive: false,
      );

      expect(copied.id, original.id); // unchanged
      expect(copied.name, 'New Name');
      expect(copied.atName, 'new');
      expect(copied.isAI, true);
      expect(copied.isActive, false);
    });

    test('equality should be based on id', () {
      final now = DateTime.now();
      final contact1 = Contact(
        id: 'contact-1',
        name: 'Name 1',
        createdAt: now,
        updatedAt: now,
      );
      final contact2 = Contact(
        id: 'contact-1',
        name: 'Name 2', // different name
        createdAt: now,
        updatedAt: now,
      );
      final contact3 = Contact(
        id: 'contact-2',
        name: 'Name 1',
        createdAt: now,
        updatedAt: now,
      );

      expect(contact1 == contact2, true); // same id
      expect(contact1 == contact3, false); // different id
    });

    test('hashCode should be based on id', () {
      final now = DateTime.now();
      final contact1 = Contact(
        id: 'contact-1',
        name: 'Name 1',
        createdAt: now,
        updatedAt: now,
      );
      final contact2 = Contact(
        id: 'contact-1',
        name: 'Name 2',
        createdAt: now,
        updatedAt: now,
      );

      expect(contact1.hashCode, contact2.hashCode);
    });
  });

  group('GroupMemberRole Enum Tests', () {
    test('should have all expected roles', () {
      expect(GroupMemberRole.values.length, 3);
      expect(GroupMemberRole.values, contains(GroupMemberRole.owner));
      expect(GroupMemberRole.values, contains(GroupMemberRole.admin));
      expect(GroupMemberRole.values, contains(GroupMemberRole.member));
    });

    test('role toString should return correct format', () {
      expect(GroupMemberRole.owner.toString(), 'GroupMemberRole.owner');
      expect(GroupMemberRole.admin.toString(), 'GroupMemberRole.admin');
      expect(GroupMemberRole.member.toString(), 'GroupMemberRole.member');
    });
  });

  group('GroupMember Model Tests', () {
    test('should create group member with all fields', () {
      final now = DateTime.now();
      final member = GroupMember(
        id: 'member-1',
        groupId: 'group-1',
        userId: 'user-1',
        userName: 'Alice',
        userAvatar: 'https://example.com/alice.png',
        atName: 'alice',
        role: GroupMemberRole.owner,
        joinedAt: now,
        isActive: true,
      );

      expect(member.id, 'member-1');
      expect(member.groupId, 'group-1');
      expect(member.userId, 'user-1');
      expect(member.userName, 'Alice');
      expect(member.atName, 'alice');
      expect(member.role, GroupMemberRole.owner);
      expect(member.isActive, true);
    });

    test('should serialize and deserialize group member', () {
      final now = DateTime(2024, 1, 1);
      final original = GroupMember(
        id: 'member-1',
        groupId: 'group-1',
        userId: 'user-1',
        userName: 'Alice',
        atName: 'alice',
        role: GroupMemberRole.admin,
        joinedAt: now,
        isActive: true,
      );

      final json = original.toJson();
      final restored = GroupMember.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.userName, original.userName);
      expect(restored.atName, original.atName);
      expect(restored.role, GroupMemberRole.admin);
    });

    test('should handle unknown role in JSON', () {
      final json = {
        'id': 'member-1',
        'groupId': 'group-1',
        'userId': 'user-1',
        'userName': 'Alice',
        'role': 'unknownRole',
        'joinedAt': '2024-01-01T00:00:00.000',
        'isActive': true,
      };

      final member = GroupMember.fromJson(json);

      expect(member.role, GroupMemberRole.member); // default
    });

    test('copyWith should work correctly', () {
      final now = DateTime.now();
      final original = GroupMember(
        id: 'member-1',
        groupId: 'group-1',
        userId: 'user-1',
        userName: 'Alice',
        role: GroupMemberRole.member,
        joinedAt: now,
      );

      final copied = original.copyWith(
        role: GroupMemberRole.admin,
        atName: 'alice_admin',
      );

      expect(copied.role, GroupMemberRole.admin);
      expect(copied.atName, 'alice_admin');
      expect(copied.userName, 'Alice'); // unchanged
    });
  });

  group('GroupChat Model Tests', () {
    test('should create group with members', () {
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
        GroupMember(
          id: 'member-2',
          groupId: 'group-1',
          userId: 'user-2',
          userName: 'Bob',
          role: GroupMemberRole.member,
          joinedAt: now,
        ),
      ];

      final group = GroupChat(
        id: 'group-1',
        name: 'Test Group',
        avatar: 'https://example.com/group.png',
        members: members,
        createdAt: now,
        updatedAt: now,
        isActive: true,
      );

      expect(group.id, 'group-1');
      expect(group.name, 'Test Group');
      expect(group.members.length, 2);
      expect(group.isActive, true);
    });

    test('should serialize and deserialize group', () {
      final now = DateTime(2024, 1, 1);
      final original = GroupChat(
        id: 'group-1',
        name: 'Test Group',
        avatar: null,
        members: [
          GroupMember(
            id: 'member-1',
            groupId: 'group-1',
            userId: 'user-1',
            userName: 'Alice',
            role: GroupMemberRole.owner,
            joinedAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
        isActive: true,
      );

      final json = original.toJson();
      final restored = GroupChat.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.members.length, 1);
      expect(restored.isActive, true);
    });

    test('copyWith should update members', () {
      final now = DateTime.now();
      final original = GroupChat(
        id: 'group-1',
        name: 'Original Group',
        members: [],
        createdAt: now,
        updatedAt: now,
      );

      final newMembers = [
        GroupMember(
          id: 'member-1',
          groupId: 'group-1',
          userId: 'user-1',
          userName: 'Alice',
          role: GroupMemberRole.owner,
          joinedAt: now,
        ),
      ];

      final copied = original.copyWith(
        name: 'Updated Group',
        members: newMembers,
      );

      expect(copied.name, 'Updated Group');
      expect(copied.members.length, 1);
    });

    test('equality should be based on id', () {
      final now = DateTime.now();
      final group1 = GroupChat(
        id: 'group-1',
        name: 'Group 1',
        members: [],
        createdAt: now,
        updatedAt: now,
      );
      final group2 = GroupChat(
        id: 'group-1',
        name: 'Group 2',
        members: [],
        createdAt: now,
        updatedAt: now,
      );

      expect(group1 == group2, true);
    });
  });

  group('AtInfo Model Tests', () {
    test('should create AtInfo with all fields', () {
      final atInfo = AtInfo(
        userId: 'user-1',
        userName: 'Alice',
        atName: 'alice',
        position: 5,
        length: 6,
      );

      expect(atInfo.userId, 'user-1');
      expect(atInfo.userName, 'Alice');
      expect(atInfo.atName, 'alice');
      expect(atInfo.position, 5);
      expect(atInfo.length, 6);
    });

    test('should serialize and deserialize AtInfo', () {
      final original = AtInfo(
        userId: 'user-1',
        userName: 'Alice',
        atName: 'alice',
        position: 5,
        length: 6,
      );

      final json = original.toJson();
      final restored = AtInfo.fromJson(json);

      expect(restored.userId, original.userId);
      expect(restored.atName, original.atName);
      expect(restored.position, original.position);
    });

    test('should handle null atName', () {
      final atInfo = AtInfo(
        userId: 'user-1',
        userName: 'Alice',
        atName: null,
        position: 5,
        length: 6,
      );

      expect(atInfo.atName, null);

      final json = atInfo.toJson();
      final restored = AtInfo.fromJson(json);

      expect(restored.atName, null);
    });

    test('equality should be based on userId and position', () {
      final atInfo1 = AtInfo(
        userId: 'user-1',
        userName: 'Alice',
        atName: 'alice',
        position: 5,
        length: 6,
      );
      final atInfo2 = AtInfo(
        userId: 'user-1',
        userName: 'Alice',
        atName: 'different',
        position: 5,
        length: 10,
      );
      final atInfo3 = AtInfo(
        userId: 'user-2',
        userName: 'Alice',
        atName: 'alice',
        position: 5,
        length: 6,
      );

      expect(atInfo1 == atInfo2, true); // same userId and position
      expect(atInfo1 == atInfo3, false); // different userId
    });
  });

  group('GroupMessage Model Tests', () {
    test('should create GroupMessage with all fields', () {
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
        senderId: 'user-1',
        senderName: 'Alice',
        senderAvatar: 'https://example.com/alice.png',
        content: '@alice Hello',
        atList: atList,
        timestamp: now,
        isDeleted: false,
      );

      expect(message.id, 'msg-1');
      expect(message.groupId, 'group-1');
      expect(message.content, '@alice Hello');
      expect(message.atList.length, 1);
      expect(message.isDeleted, false);
    });

    test('should serialize and deserialize GroupMessage', () {
      final now = DateTime(2024, 1, 1);
      final original = GroupMessage(
        id: 'msg-1',
        groupId: 'group-1',
        senderId: 'user-1',
        senderName: 'Alice',
        content: 'Hello everyone',
        timestamp: now,
        isDeleted: false,
      );

      final json = original.toJson();
      final restored = GroupMessage.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.groupId, original.groupId);
      expect(restored.content, original.content);
      expect(restored.isDeleted, false);
    });

    test('copyWith should update content', () {
      final now = DateTime.now();
      final original = GroupMessage(
        id: 'msg-1',
        groupId: 'group-1',
        senderId: 'user-1',
        senderName: 'Alice',
        content: 'Original content',
        timestamp: now,
      );

      final copied = original.copyWith(
        content: 'Updated content',
        isDeleted: true,
      );

      expect(copied.content, 'Updated content');
      expect(copied.isDeleted, true);
      expect(copied.senderId, 'user-1'); // unchanged
    });

    test('equality should be based on id', () {
      final now = DateTime.now();
      final msg1 = GroupMessage(
        id: 'msg-1',
        groupId: 'group-1',
        senderId: 'user-1',
        senderName: 'Alice',
        content: 'Content 1',
        timestamp: now,
      );
      final msg2 = GroupMessage(
        id: 'msg-1',
        groupId: 'group-1',
        senderId: 'user-2',
        senderName: 'Bob',
        content: 'Content 2',
        timestamp: now,
      );

      expect(msg1 == msg2, true); // same id
    });
  });
}
