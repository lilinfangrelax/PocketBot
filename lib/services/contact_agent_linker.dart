import 'package:pocket_bot/models/ai_contact_config.dart';
import 'package:pocket_bot/models/contact.dart';
import 'package:pocket_bot/models/group_workspace.dart';
import 'package:pocket_bot/services/ai_contact_service.dart';
import 'package:pocket_bot/services/connection_manager.dart';
import 'package:pocket_bot/services/websocket_service.dart';
import 'package:pocket_bot/utils/logger.dart';

class ContactChat {
  final WebSocketService service;
  final String sessionKey;

  const ContactChat(this.service, this.sessionKey);
}

/// Resolves an AI contact to its agent connection and to the ACP session
/// that holds its conversation (one per direct chat and per group).
class ContactAgentLinker {
  ContactAgentLinker(this._manager, {AIContactService? contacts})
      : _contacts = contacts ?? AIContactService();

  final ConnectionManager _manager;
  final AIContactService _contacts;

  Future<AIContactConfig?> configFor(String contactId) =>
      _contacts.getConfig(contactId);

  /// The contact's agent process. In a group with a folder it runs on the
  /// group's host; otherwise on the contact's own.
  Future<WebSocketService> serviceFor(
    AIContactConfig config, {
    GroupWorkspace? workspace,
  }) {
    final hostId = workspace != null && workspace.isSet
        ? workspace.hostId
        : config.gatewayId;
    final profile = _manager.profileForContact(config, hostId: hostId);
    if (profile == null) {
      throw Exception(
        hostId.isEmpty ? '这个联系人还没有绑定主机，群聊也没有设置工作目录' : '绑定的主机已被删除，请重新选择',
      );
    }
    return _manager.connectProfile(profile);
  }

  /// Folder the contact works in: the group's when it has one, otherwise the
  /// contact's own. Null leaves it to the agent's launch folder.
  static String? directoryFor(
    AIContactConfig config, [
    GroupWorkspace? workspace,
  ]) {
    if (workspace != null && workspace.isSet) {
      return workspace.workingDirectory.trim();
    }
    final own = config.workingDirectory.trim();
    return own.isEmpty ? null : own;
  }

  /// Returns the ACP session for [contactId] in [groupId], resuming the saved
  /// one when the agent allows it and starting a new one otherwise. A saved
  /// session from another folder is replaced.
  Future<String> sessionFor({
    required WebSocketService service,
    required String contactId,
    required String groupId,
    required String title,
    String? cwd,
  }) async {
    final folder = cwd?.trim() ?? '';
    final mapping = await _contacts.getMapping(contactId, groupId);
    if (mapping != null) {
      final saved = mapping.workingDirectory;
      if (saved.isEmpty || folder.isEmpty || saved == folder) {
        try {
          return await service.ensureRemoteSession(
            mapping.sessionKey,
            cwd: folder.isEmpty ? null : folder,
          );
        } catch (error) {
          Logger.info(
            '[Contacts] Could not resume ${mapping.sessionKey}, starting anew: $error',
          );
        }
      } else {
        Logger.info(
          '[Contacts] $contactId in $groupId moved from $saved to $folder',
        );
      }
    }
    final created = await service.createGatewaySession(
      title,
      cwd: folder.isEmpty ? null : folder,
    );
    await _contacts.createOrUpdateMapping(
      contactId: contactId,
      groupId: groupId,
      sessionKey: created.key,
      workingDirectory: service.workingDirectoryFor(created.key),
    );
    return created.key;
  }

  Future<ContactChat> openDirectChat(Contact contact) async {
    final config = await configFor(contact.id);
    if (config == null) throw Exception('这个联系人还没有绑定代理');
    final service = await serviceFor(config);
    final sessionKey = await sessionFor(
      service: service,
      contactId: contact.id,
      groupId: AIContactService.directChatId,
      title: contact.name,
      cwd: directoryFor(config),
    );
    service.selectSession(sessionKey, agentId: config.agentId);
    final session = service.getSession(sessionKey);
    if (session != null && session.customTitle == null) {
      session.setCustomTitle(contact.name);
    }
    await service.saveCurrentSession();
    return ContactChat(service, sessionKey);
  }

  Future<String?> contactForSession(String sessionKey) =>
      _contacts.contactForDirectSession(sessionKey);
}
