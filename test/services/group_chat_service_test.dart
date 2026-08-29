import 'package:pocket_bot/models/group_chat.dart';
import 'package:pocket_bot/services/group_chat_service.dart';
import 'package:test/test.dart';

void main() {
  group('GroupChatService Tests', () {
    late GroupChatService groupChatService;

    setUp(() {
      groupChatService = GroupChatService();
    });

    group('parseAtMentionsSync', () {
      test('should parse single @mention correctly', () {
        const text = '@gpt Hello';
        
        final atList = groupChatService.parseAtMentionsSync(text);

        expect(atList.length, 1);
        expect(atList[0].atName, 'gpt');
        expect(atList[0].position, 0);
        expect(atList[0].length, 4); // @gpt
      });

      test('should parse multiple @mentions correctly', () {
        const text = '@gpt and @claude please help';
        
        final atList = groupChatService.parseAtMentionsSync(text);

        expect(atList.length, 2);
        expect(atList[0].atName, 'gpt');
        expect(atList[1].atName, 'claude');
      });

      test('should not match @ at end of text', () {
        const text = 'Hello @';
        
        final atList = groupChatService.parseAtMentionsSync(text);

        expect(atList.length, 0);
      });

      test('should handle @ in middle of word', () {
        const text = 'test@example.com';
        
        final atList = groupChatService.parseAtMentionsSync(text);

        // This would match email as @mention - expected behavior
        expect(atList.length, 1);
        expect(atList[0].atName, 'example.com');
      });

      test('should handle multiple @ in sequence', () {
        const text = '@alice @bob @charlie';
        
        final atList = groupChatService.parseAtMentionsSync(text);

        expect(atList.length, 3);
        expect(atList[0].atName, 'alice');
        expect(atList[1].atName, 'bob');
        expect(atList[2].atName, 'charlie');
      });

      test('should handle @ with numbers', () {
        const text = '@user123 Hello';
        
        final atList = groupChatService.parseAtMentionsSync(text);

        expect(atList.length, 1);
        expect(atList[0].atName, 'user123');
      });

      test('should handle @ with underscore', () {
        const text = '@user_name Hello';
        
        final atList = groupChatService.parseAtMentionsSync(text);

        expect(atList.length, 1);
        expect(atList[0].atName, 'user_name');
      });

      test('should return empty list for text without @', () {
        const text = 'Hello everyone';
        
        final atList = groupChatService.parseAtMentionsSync(text);

        expect(atList.length, 0);
      });

      test('should handle @ followed by space', () {
        const text = '@ gpt Hello'; // space after @
        
        final atList = groupChatService.parseAtMentionsSync(text);

        expect(atList.length, 0); // @ followed by space doesn't match
      });
    });

    group('GroupMessage with AtInfo', () {
      test('should create GroupMessage with atList', () {
        final now = DateTime.now();
        final atList = [
          AtInfo(
            userId: 'ai-1',
            userName: 'GPT Assistant',
            atName: 'gpt',
            position: 0,
            length: 4,
          ),
        ];

        final message = GroupMessage(
          id: 'msg-1',
          groupId: 'group-1',
          senderId: 'user-1',
          senderName: 'Alice',
          content: '@gpt Hello',
          atList: atList,
          timestamp: now,
        );

        expect(message.atList.length, 1);
        expect(message.atList[0].userId, 'ai-1');
      });

      test('should create GroupMessage without atList', () {
        final now = DateTime.now();

        final message = GroupMessage(
          id: 'msg-1',
          groupId: 'group-1',
          senderId: 'user-1',
          senderName: 'Alice',
          content: 'Hello everyone',
          timestamp: now,
        );

        expect(message.atList.length, 0);
      });

      test('should parse and create message with atList', () {
        const text = '@claude Hi there';
        
        final atList = groupChatService.parseAtMentionsSync(text);
        final now = DateTime.now();

        final message = GroupMessage(
          id: 'msg-1',
          groupId: 'group-1',
          senderId: 'user-1',
          senderName: 'Bob',
          content: text,
          atList: atList,
          timestamp: now,
        );

        expect(message.atList.length, 1);
        expect(message.atList[0].atName, 'claude');
        expect(message.content, '@claude Hi there');
      });
    });

    group('AtInfo parsing edge cases', () {
      test('should calculate correct position for @ in middle', () {
        const text = 'Hello @gpt, how are you?';
        
        final atList = groupChatService.parseAtMentionsSync(text);

        expect(atList.length, 1);
        expect(atList[0].position, 6); // '@gpt' starts at position 6
      });

      test('should calculate correct length with different atNames', () {
        const text = '@a @ab @abc';
        
        final atList = groupChatService.parseAtMentionsSync(text);

        expect(atList[0].length, 2); // @a
        expect(atList[1].length, 3); // @ab
        expect(atList[2].length, 4); // @abc
      });
    });
  });

  group('GroupChat Model Tests (Integration)', () {
    test('should create group with multiple members', () {
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
          role: GroupMemberRole.admin,
          joinedAt: now,
        ),
        GroupMember(
          id: 'member-3',
          groupId: 'group-1',
          userId: 'ai-1',
          userName: 'GPT',
          atName: 'gpt',
          role: GroupMemberRole.member,
          joinedAt: now,
        ),
      ];

      final group = GroupChat(
        id: 'group-1',
        name: 'Test Group',
        members: members,
        createdAt: now,
        updatedAt: now,
      );

      expect(group.members.length, 3);
      expect(group.members[0].role, GroupMemberRole.owner);
      expect(group.members[2].atName, 'gpt');
    });

    test('should serialize and deserialize group with members', () {
      final now = DateTime(2024, 1, 1, 12, 0, 0);
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
            atName: 'alice',
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
      expect(restored.members[0].atName, 'alice');
      expect(restored.isActive, true);
    });

    test('should handle empty atName', () {
      final now = DateTime.now();
      final member = GroupMember(
        id: 'member-1',
        groupId: 'group-1',
        userId: 'user-1',
        userName: 'Alice',
        atName: null, // no @name
        role: GroupMemberRole.member,
        joinedAt: now,
      );

      expect(member.atName, null);
      expect(member.userName, 'Alice');
    });

    group('showInSessionList', () {
      test('should default showInSessionList to true', () {
        final now = DateTime.now();
        final group = GroupChat(
          id: 'group-1',
          name: 'Test Group',
          members: [],
          createdAt: now,
          updatedAt: now,
        );

        expect(group.showInSessionList, true);
      });

      test('should allow setting showInSessionList to false', () {
        final now = DateTime.now();
        final group = GroupChat(
          id: 'group-1',
          name: 'Test Group',
          members: [],
          createdAt: now,
          updatedAt: now,
          showInSessionList: false,
        );

        expect(group.showInSessionList, false);
      });

      test('should serialize showInSessionList to JSON', () {
        final now = DateTime.now();
        final group = GroupChat(
          id: 'group-1',
          name: 'Test Group',
          members: [],
          createdAt: now,
          updatedAt: now,
          showInSessionList: false,
        );

        final json = group.toJson();
        expect(json['showInSessionList'], false);
      });

      test('should deserialize showInSessionList from JSON', () {
        final now = DateTime.now();
        final json = {
          'id': 'group-1',
          'name': 'Test Group',
          'members': [],
          'createdAt': now.toIso8601String(),
          'updatedAt': now.toIso8601String(),
          'isActive': true,
          'showInSessionList': false,
        };

        final group = GroupChat.fromJson(json);
        expect(group.showInSessionList, false);
      });

      test('should default showInSessionList to true when missing in JSON', () {
        final now = DateTime.now();
        final json = {
          'id': 'group-1',
          'name': 'Test Group',
          'members': [],
          'createdAt': now.toIso8601String(),
          'updatedAt': now.toIso8601String(),
          'isActive': true,
        };

        final group = GroupChat.fromJson(json);
        expect(group.showInSessionList, true);
      });

      test('copyWith should preserve showInSessionList', () {
        final now = DateTime.now();
        final group = GroupChat(
          id: 'group-1',
          name: 'Test Group',
          members: [],
          createdAt: now,
          updatedAt: now,
          showInSessionList: false,
        );

        final copied = group.copyWith(name: 'New Name');
        expect(copied.showInSessionList, false);
      });

      test('copyWith should allow updating showInSessionList', () {
        final now = DateTime.now();
        final group = GroupChat(
          id: 'group-1',
          name: 'Test Group',
          members: [],
          createdAt: now,
          updatedAt: now,
          showInSessionList: false,
        );

        final copied = group.copyWith(showInSessionList: true);
        expect(copied.showInSessionList, true);
        expect(copied.name, 'Test Group');
      });
    });
  });
}
