import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_bot/models/group_chat.dart';
import 'package:pocket_bot/models/message.dart';
import 'package:pocket_bot/screens/wechat_session_list.dart';

void main() {
  group('SessionItem Tests', () {
    test('should create personal session item correctly', () {
      final now = DateTime.now();
      final session = SessionItem(
        type: SessionItemType.personal,
        personalSession: _createMockChatSession('session-1', 'Personal Chat'),
        lastUpdated: now,
        title: 'Personal Chat',
        lastMessage: 'Hello',
        unreadCount: 5,
      );

      expect(session.type, SessionItemType.personal);
      expect(session.key, 'session-1');
      expect(session.unreadCount, 5);
    });

    test('should create group session item correctly', () {
      final now = DateTime.now();
      final group = GroupChat(
        id: 'group-1',
        name: 'Test Group',
        members: [],
        createdAt: now,
        updatedAt: now,
        showInSessionList: true,
      );

      final session = SessionItem(
        type: SessionItemType.group,
        groupChat: group,
        lastUpdated: now,
        title: 'Test Group',
        lastMessage: 'Group message',
        unreadCount: 0,
      );

      expect(session.type, SessionItemType.group);
      expect(session.key, 'group_group-1');
      expect(session.unreadCount, 0);
    });

    test('should generate correct key for personal session', () {
      final session = SessionItem(
        type: SessionItemType.personal,
        personalSession: _createMockChatSession('abc123', 'Test'),
        lastUpdated: DateTime.now(),
        title: 'Test',
      );

      expect(session.key, 'abc123');
    });

    test('should generate correct key for group session', () {
      final group = GroupChat(
        id: 'group-xyz',
        name: 'Group',
        members: [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final session = SessionItem(
        type: SessionItemType.group,
        groupChat: group,
        lastUpdated: DateTime.now(),
        title: 'Group',
      );

      expect(session.key, 'group_group-xyz');
    });

    test('group session key should include group_ prefix', () {
      final group = GroupChat(
        id: 'my-group-123',
        name: 'My Group',
        members: [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        showInSessionList: false, // hidden from session list
      );

      final session = SessionItem(
        type: SessionItemType.group,
        groupChat: group,
        lastUpdated: DateTime.now(),
        title: 'My Group',
      );

      // Key should still be generated (hide logic is handled by service)
      expect(session.key, 'group_my-group-123');
    });
  });

  group('Group Chat showInSessionList Logic', () {
    test('group with showInSessionList true should appear in session list', () {
      final group = GroupChat(
        id: 'group-1',
        name: 'Visible Group',
        members: [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        showInSessionList: true,
      );

      expect(group.showInSessionList, true);
    });

    test('group with showInSessionList false should not appear in session list', () {
      final group = GroupChat(
        id: 'group-2',
        name: 'Hidden Group',
        members: [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        showInSessionList: false,
      );

      expect(group.showInSessionList, false);
    });

    test('copyWith should toggle showInSessionList correctly', () {
      final group = GroupChat(
        id: 'group-1',
        name: 'Test',
        members: [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        showInSessionList: true,
      );

      final hidden = group.copyWith(showInSessionList: false);
      final visible = group.copyWith(showInSessionList: true);

      expect(hidden.showInSessionList, false);
      expect(visible.showInSessionList, true);
    });
  });
}

// Helper function to create mock ChatSession
ChatSession _createMockChatSession(String key, String title) {
  return ChatSession(
    id: 'test-id-${DateTime.now().millisecondsSinceEpoch}',
    key: key,
    title: title,
    createdAt: DateTime.now(),
    lastUpdated: DateTime.now(),
    messages: [],
    unreadCount: 0,
  );
}
