import 'package:pocket_bot/models/ai_contact_config.dart';
import 'package:pocket_bot/models/contact.dart';
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

  Future<WebSocketService> serviceFor(AIContactConfig config) {
    final profile = _manager.profileForContact(config);
    if (profile == null) {
      throw Exception(
        config.hasAgent ? '这个联系人绑定的连接已被删除，请重新选择' : '这个联系人还没有绑定代理',
      );
    }
    return _manager.connectProfile(profile);
  }

  /// Returns the ACP session for [contactId] in [groupId], resuming the saved
  /// one when the agent allows it and starting a new one otherwise.
  Future<String> sessionFor({
    required WebSocketService service,
    required String contactId,
    required String groupId,
    required String title,
  }) async {
    final mapping = await _contacts.getMapping(contactId, groupId);
    if (mapping != null) {
      try {
        return await service.ensureRemoteSession(mapping.sessionKey);
      } catch (error) {
        Logger.info(
          '[Contacts] Could not resume ${mapping.sessionKey}, starting anew: $error',
        );
      }
    }
    final created = await service.createGatewaySession(title);
    await _contacts.createOrUpdateMapping(
      contactId: contactId,
      groupId: groupId,
      sessionKey: created.key,
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
