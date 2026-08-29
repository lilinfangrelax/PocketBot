import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:pocket_bot/models/contact.dart';
import 'package:pocket_bot/services/database_service.dart';

/// 联系人服务
class ContactService {
  final DatabaseService _db = DatabaseService();
  final List<ContactChangeLog> _changeLogs = [];

  ContactService();

  /// 获取所有联系人
  Future<List<Contact>> getAllContacts() async {
    return await _db.getAllContacts();
  }

  /// 获取单个联系人
  Future<Contact?> getContact(String id) async {
    return await _db.getContact(id);
  }

  /// 搜索联系人
  Future<List<Contact>> searchContacts(String keyword) async {
    final contacts = await _db.getAllContacts();
    final lowerKeyword = keyword.toLowerCase();
    return contacts
        .where((c) =>
            c.name.toLowerCase().contains(lowerKeyword) ||
            (c.atName?.toLowerCase().contains(lowerKeyword) ?? false))
        .toList();
  }

  /// 获取所有AI联系人
  Future<List<Contact>> getAIContacts() async {
    final contacts = await _db.getAllContacts();
    return contacts.where((c) => c.isAI).toList();
  }

  /// 创建联系人
  Future<Contact> createContact({
    required String name,
    String? atName,
    String? avatar,
    bool isAI = false,
  }) async {
    final now = DateTime.now();
    final contact = Contact(
      id: 'contact_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      atName: atName,
      avatar: avatar,
      isActive: true,
      isAI: isAI,
      createdAt: now,
      updatedAt: now,
    );

    // 保存到数据库
    await _db.insertContact(contact);

    // 记录变更日志
    _changeLogs.add(ContactChangeLog(
      id: 'log_${DateTime.now().millisecondsSinceEpoch}',
      contactId: contact.id,
      changeType: ContactChangeType.created,
      newValue: name,
      createdAt: now,
    ));

    return contact;
  }

  /// 更新联系人
  Future<Contact> updateContact({
    required String id,
    String? name,
    String? atName,
    String? avatar,
    bool? isActive,
    bool? isAI,
  }) async {
    final oldContact = await _db.getContact(id);
    if (oldContact == null) {
      throw Exception('联系人不存在');
    }

    final now = DateTime.now();

    // 记录变更日志
    if (name != null && name != oldContact.name) {
      _changeLogs.add(ContactChangeLog(
        id: 'log_${DateTime.now().millisecondsSinceEpoch}',
        contactId: id,
        changeType: ContactChangeType.nameChanged,
        oldValue: oldContact.name,
        newValue: name,
        createdAt: now,
      ));
    }

    final updatedContact = oldContact.copyWith(
      name: name,
      atName: atName,
      avatar: avatar,
      isActive: isActive,
      isAI: isAI,
      updatedAt: now,
    );

    // 更新数据库
    await _db.updateContact(updatedContact);
    return updatedContact;
  }

  /// 删除联系人
  Future<void> deleteContact(String id) async {
    final contact = await _db.getContact(id);
    if (contact == null) {
      throw Exception('联系人不存在');
    }

    // 软删除
    await _db.deleteContact(id);

    // 记录变更日志
    _changeLogs.add(ContactChangeLog(
      id: 'log_${DateTime.now().millisecondsSinceEpoch}',
      contactId: id,
      changeType: ContactChangeType.deleted,
      oldValue: contact.name,
      createdAt: DateTime.now(),
    ));
  }

  /// 获取联系人变更日志
  Future<List<ContactChangeLog>> getChangeLogs(String contactId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _changeLogs
        .where((log) => log.contactId == contactId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// 获取变更日志
  Future<List<ContactChangeLog>> getAllChangeLogs() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return List.unmodifiable(_changeLogs)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }
}
