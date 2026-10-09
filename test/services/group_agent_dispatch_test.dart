import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_bot/models/ai_contact_config.dart';
import 'package:pocket_bot/models/group_chat.dart';
import 'package:pocket_bot/models/message.dart';
import 'package:pocket_bot/services/connection_manager.dart';
import 'package:pocket_bot/services/group_chat_service.dart';

void main() {
  final now = DateTime(2026, 1, 1);

  GroupMember member(String id, String name, {String? atName}) => GroupMember(
        id: 'm_$id',
        groupId: 'g1',
        userId: id,
        userName: name,
        atName: atName,
        role: GroupMemberRole.member,
        joinedAt: now,
      );

  AIContactConfig config(String contactId, {bool autoReply = false}) =>
      AIContactConfig(
        contactId: contactId,
        agentId: 'cursor',
        gatewayId: 'gw',
        autoReply: autoReply,
        createdAt: now,
        updatedAt: now,
      );

  GroupMessage message(String text, {String senderId = 'me'}) => GroupMessage(
        id: 'msg',
        groupId: 'g1',
        senderId: senderId,
        senderName: 'Me',
        content: text,
        timestamp: now,
      );

  final members = [
    member('me', 'Me'),
    member('coder', 'Coder', atName: 'coder'),
    member('writer', 'Writer'),
    member('human', 'Alice', atName: 'alice'),
  ];

  List<String> targetsFor(
    GroupMessage msg,
    Map<String, AIContactConfig> configs,
  ) =>
      GroupChatService.agentTargets(
        message: msg,
        members: members,
        configs: configs,
        mentions: GroupChatService().parseAtMentionsSync(msg.content),
      ).map((m) => m.userId).toList();

  group('agentTargets', () {
    test('picks only mentioned AI members', () {
      final configs = {'coder': config('coder'), 'writer': config('writer')};
      expect(targetsFor(message('@coder fix the build'), configs), ['coder']);
    });

    test('matches the display name case-insensitively', () {
      final configs = {'writer': config('writer')};
      expect(targetsFor(message('@writer hi'), configs), ['writer']);
    });

    test('includes auto-reply members without a mention', () {
      final configs = {
        'coder': config('coder'),
        'writer': config('writer', autoReply: true),
      };
      expect(targetsFor(message('anyone around?'), configs), ['writer']);
    });

    test('ignores people without an agent and the sender', () {
      final configs = {'coder': config('coder', autoReply: true)};
      expect(targetsFor(message('@alice hi'), configs), ['coder']);
      expect(
        targetsFor(message('@coder', senderId: 'coder'), configs),
        isEmpty,
      );
    });
  });

  test('groupPrompt names the group and the sender', () {
    final group = GroupChat(
      id: 'g1',
      name: 'Team',
      members: members,
      createdAt: now,
      updatedAt: now,
    );
    expect(
      GroupChatService.groupPrompt(group, message('@coder hi')),
      '群聊「Team」中，Me 说：\n@coder hi',
    );
  });

  test('profileKey separates folders and agents on one connection', () {
    final base = GatewayInfo.ssh(
      host: 'box',
      username: 'me',
      workingDirectory: '/a',
      agentId: 'cursor',
    );
    expect(
      ConnectionManager.profileKey(base),
      isNot(ConnectionManager.profileKey(
          base.copyWith(workingDirectory: '/b'))),
    );
    expect(
      ConnectionManager.profileKey(base),
      isNot(ConnectionManager.profileKey(base.copyWith(agentId: 'claude'))),
    );
    expect(
      ConnectionManager.profileKey(base),
      ConnectionManager.profileKey(base.copyWith(workingDirectory: ' /a ')),
    );
  });
}
