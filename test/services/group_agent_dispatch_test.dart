import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_bot/models/ai_contact_config.dart';
import 'package:pocket_bot/models/group_chat.dart';
import 'package:pocket_bot/models/group_workspace.dart';
import 'package:pocket_bot/models/message.dart';
import 'package:pocket_bot/services/connection_manager.dart';
import 'package:pocket_bot/services/contact_agent_linker.dart';
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

  group('contact agent processes', () {
    final host = GatewayInfo.ssh(
      host: 'box',
      username: 'me',
      workingDirectory: '/a',
      agentId: 'cursor',
    );
    GatewayInfo contact(String id) => host.copyWith(
          instanceTag: ConnectionManager.contactInstanceTag(id),
        );

    test('one process per contact whatever the folder', () {
      expect(
        ConnectionManager.profileKey(contact('coder')),
        ConnectionManager.profileKey(
          contact('coder').copyWith(workingDirectory: '/b'),
        ),
      );
      expect(
        ConnectionManager.profileKey(contact('coder')),
        isNot(ConnectionManager.profileKey(contact('writer'))),
      );
    });

    test('contacts never share the untagged primary process', () {
      expect(
        ConnectionManager.profileKey(contact('coder')),
        isNot(ConnectionManager.profileKey(host)),
      );
    });

    test('hostId ignores folder and agent', () {
      expect(host.hostId, 'ssh|me@box:22');
      expect(host.copyWith(workingDirectory: '/b', agentId: 'x').hostId,
          host.hostId);
      expect(GatewayInfo.local(workingDirectory: '/x').hostId, 'local');
    });
  });

  group('directoryFor', () {
    test('prefers the group folder over the contact folder', () {
      final cfg = config('coder').copyWith(workingDirectory: '/own');
      final workspace = GroupWorkspace(
        groupId: 'g1',
        hostId: 'ssh|me@box:22',
        workingDirectory: '/repo',
      );
      expect(ContactAgentLinker.directoryFor(cfg, workspace), '/repo');
      expect(ContactAgentLinker.directoryFor(cfg), '/own');
    });

    test('ignores a group workspace without a folder', () {
      final workspace =
          GroupWorkspace(groupId: 'g1', hostId: 'h', workingDirectory: ' ');
      expect(workspace.isSet, isFalse);
      expect(ContactAgentLinker.directoryFor(config('coder'), workspace),
          isNull);
    });
  });

  test('GroupWorkspace round-trips through the database row', () {
    final workspace = GroupWorkspace(
      groupId: 'g1',
      hostId: 'ssh|me@box:22',
      workingDirectory: '/repo',
      updatedAt: now,
    );
    final copy = GroupWorkspace.fromDbMap(workspace.toDbMap());
    expect(copy.groupId, 'g1');
    expect(copy.hostId, 'ssh|me@box:22');
    expect(copy.workingDirectory, '/repo');
    expect(copy.updatedAt, now);
  });
}
