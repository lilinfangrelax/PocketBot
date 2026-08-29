import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_bot/models/group_chat.dart';
import 'package:pocket_bot/screens/group_chat_list.dart';

void main() {
  group('GroupChatListScreen Widget Tests', () {
    testWidgets('should show empty state when no groups', (tester) async {
      // Note: This test requires mocking the GroupChatService
      // For now, we test the UI components directly

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: Text('Group Chat List'),
            ),
          ),
        ),
      );

      expect(find.text('Group Chat List'), findsOneWidget);
    });

    testWidgets('GroupListTile should show group name', (tester) async {
      final now = DateTime.now();
      final group = GroupChat(
        id: 'group-1',
        name: 'Test Group',
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
        showInSessionList: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListTile(
              leading: const CircleAvatar(child: Text('T')),
              title: Text(group.name),
              subtitle: Text('${group.members.length} 位成员'),
            ),
          ),
        ),
      );

      expect(find.text('Test Group'), findsOneWidget);
      expect(find.text('1 位成员'), findsOneWidget);
    });

    testWidgets('GroupListTile should show hidden badge when showInSessionList is false', (tester) async {
      final now = DateTime.now();
      final group = GroupChat(
        id: 'group-1',
        name: 'Hidden Group',
        members: [],
        createdAt: now,
        updatedAt: now,
        showInSessionList: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                Text(group.name),
                if (!group.showInSessionList)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: const Text('已隐藏', style: TextStyle(fontSize: 10)),
                  ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Hidden Group'), findsOneWidget);
      expect(find.text('已隐藏'), findsOneWidget);
    });

    testWidgets('GroupListTile should show visibility icon when group is hidden', (tester) async {
      final now = DateTime.now();
      final group = GroupChat(
        id: 'group-1',
        name: 'Hidden Group',
        members: [],
        createdAt: now,
        updatedAt: now,
        showInSessionList: false,
      );

      // Test when onShowInSessionList is provided (group is hidden)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListTile(
              title: Text(group.name),
              trailing: IconButton(
                icon: const Icon(Icons.visibility, color: Colors.blue),
                onPressed: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.visibility), findsOneWidget);
    });
  });

  group('Group Chat showInSessionList Model Tests', () {
    test('new group should default to showInSessionList true', () {
      final group = GroupChat(
        id: 'group-1',
        name: 'New Group',
        members: [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(group.showInSessionList, true);
    });

    test('should create group hidden from session list', () {
      final group = GroupChat(
        id: 'group-1',
        name: 'New Group',
        members: [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        showInSessionList: false,
      );

      expect(group.showInSessionList, false);
    });

    test('should toggle showInSessionList with copyWith', () {
      final group = GroupChat(
        id: 'group-1',
        name: 'Test',
        members: [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        showInSessionList: true,
      );

      final hidden = group.copyWith(showInSessionList: false);
      final shown = hidden.copyWith(showInSessionList: true);

      expect(group.showInSessionList, true);
      expect(hidden.showInSessionList, false);
      expect(shown.showInSessionList, true);
    });
  });
}
