import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:pocket_bot/services/contact_service.dart';
import 'package:pocket_bot/models/contact.dart';
import 'package:pocket_bot/screens/contact_detail_screen.dart';
import 'package:pocket_bot/screens/create_contact_screen.dart';
import 'package:pocket_bot/screens/create_group_screen.dart';
import 'package:pocket_bot/screens/group_chat_list.dart';
import 'package:pocket_bot/theme/fluent_theme.dart';
import 'package:pocket_bot/widgets/fluent_page.dart';

// ============ 常量定义 ============
const double _kSpacingMedium = 16;

/// 通讯录页面
class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final ContactService _contactService = ContactService();
  List<Contact> _contacts = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    setState(() => _isLoading = true);
    try {
      final contacts = await _contactService.getAllContacts();
      setState(() => _contacts = contacts);
    } catch (e) {
      _showError('加载联系人失败: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _searchContacts(String keyword) async {
    if (keyword.isEmpty) {
      _loadContacts();
      return;
    }
    final results = await _contactService.searchContacts(keyword);
    setState(() => _contacts = results);
  }

  void _showError(String message) {
    showAppNotice(context, message);
  }

  @override
  Widget build(BuildContext context) {
    return FluentScreen(
      title: const Text('通讯录'),
      commands: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          fluent.Tooltip(
            message: '创建群聊',
            child: fluent.IconButton(
              icon: const Icon(fluent.WindowsIcons.group),
              onPressed: _navigateToCreateGroup,
            ),
          ),
          fluent.Tooltip(
            message: '添加联系人',
            child: fluent.IconButton(
              icon: const Icon(fluent.WindowsIcons.add_friend),
              onPressed: _navigateToCreateContact,
            ),
          ),
        ],
      ),
      content: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                _kSpacingMedium, 0, _kSpacingMedium, 8),
            child: fluent.TextBox(
              controller: _searchController,
              placeholder: '搜索联系人...',
              prefix: const Padding(
                padding: EdgeInsetsDirectional.only(start: 10),
                child: Icon(fluent.WindowsIcons.search, size: 14),
              ),
              onChanged: _searchContacts,
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: fluent.ProgressRing())
                : _buildContactList(),
          ),
        ],
      ),
    );
  }

  Widget _buildContactList() {
    return CustomScrollView(
      slivers: [
        // 群聊入口
        SliverToBoxAdapter(
          child: _buildGroupChatEntry(),
        ),
        // 联系人列表
        _contacts.isEmpty
            ? SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    '暂无联系人',
                    style: TextStyle(
                      fontSize: 13,
                      color: FluentColors.of(context).textSecondary,
                    ),
                  ),
                ),
              )
            : SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final contact = _contacts[index];
                    return _buildContactItem(contact);
                  },
                  childCount: _contacts.length,
                ),
              ),
      ],
    );
  }

  /// 构建群聊入口
  Widget _buildGroupChatEntry() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          _kSpacingMedium, 4, _kSpacingMedium, _kSpacingMedium),
      child: Card(
        child: ListTile(
          leading: const FluentIconAvatar(
            icon: fluent.WindowsIcons.people,
            size: 40,
          ),
          title: const Text('群聊'),
          subtitle: const Text('查看所有群聊，包括已隐藏的'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _navigateToGroupChatList,
        ),
      ),
    );
  }

  Widget _buildContactItem(Contact contact) {
    final colors = FluentColors.of(context);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: colors.accentSubtle,
        foregroundColor: colors.accent,
        backgroundImage:
            contact.avatar != null ? NetworkImage(contact.avatar!) : null,
        child:
            contact.avatar == null ? Text(contact.name[0].toUpperCase()) : null,
      ),
      title: Text(contact.name),
      subtitle: Text('@${contact.atName}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!contact.isActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: colors.control,
                border: Border.all(color: colors.stroke),
                borderRadius: BorderRadius.circular(FluentColors.radius),
              ),
              child: Text(
                '离线',
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
            ),
        ],
      ),
      onTap: () => _navigateToDetail(contact),
    );
  }

  void _navigateToDetail(Contact contact) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ContactDetailScreen(contact: contact),
      ),
    ).then((_) => _loadContacts());
  }

  void _navigateToCreateContact() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CreateContactScreen(),
      ),
    ).then((_) => _loadContacts());
  }

  void _navigateToCreateGroup() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CreateGroupScreen(),
      ),
    );
  }

  void _navigateToGroupChatList() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const GroupChatListScreen(),
      ),
    );
  }
}
