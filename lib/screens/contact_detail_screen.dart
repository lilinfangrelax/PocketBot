import 'package:flutter/material.dart';
import 'package:pocket_bot/models/contact.dart';
import 'package:pocket_bot/models/group_chat.dart';
import 'package:pocket_bot/services/contact_service.dart';
import 'package:pocket_bot/services/group_chat_service.dart';
import 'package:pocket_bot/screens/group_chat_screen.dart';

/// 联系人详情页面
class ContactDetailScreen extends StatefulWidget {
  final Contact contact;

  const ContactDetailScreen({super.key, required this.contact});

  @override
  State<ContactDetailScreen> createState() => _ContactDetailScreenState();
}

class _ContactDetailScreenState extends State<ContactDetailScreen> {
  late Contact _contact;
  final ContactService _contactService = ContactService();
  final GroupChatService _groupChatService = GroupChatService();
  bool _isLoading = true;
  List<ContactChangeLog> _changeLogs = [];
  List<GroupChat> _groups = [];

  @override
  void initState() {
    super.initState();
    _contact = widget.contact;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final contact = await _contactService.getContact(_contact.id);
      if (contact != null && mounted) {
        setState(() => _contact = contact);
      }
      _changeLogs = await _contactService.getChangeLogs(_contact.id);
      
      // 获取该联系人所在的群聊
      _groups = await _groupChatService.getUserGroups(_contact.id);
    } catch (e) {
      _showError('加载失败: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _navigateToGroupChat(GroupChat group) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GroupChatScreen(groupId: group.id)),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _editContact() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditContactScreen(contact: _contact),
      ),
    );

    if (result != null && result is Contact) {
      setState(() => _contact = result);
    }
  }

  void _deleteContact() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除联系人'),
        content: Text('确定要删除 "${_contact.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await _contactService.deleteContact(_contact.id);
                if (mounted) {
                  Navigator.pop(context, true);
                }
              } catch (e) {
                _showError('删除失败: $e');
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('联系人详情'),
        backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _editContact,
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _deleteContact,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  // 头像
                  Center(
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor: const Color(0xFF07C160),
                      child: _contact.avatar != null && _contact.avatar!.isNotEmpty
                          ? ClipOval(
                              child: Image.network(
                                _contact.avatar!,
                                width: 100,
                                height: 100,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _buildAvatarText(),
                              ),
                            )
                          : _buildAvatarText(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 名称
                  Text(
                    _contact.name,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_contact.atName != null && _contact.atName!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '@${_contact.atName}',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  // 状态
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _contact.isActive ? Colors.green : Colors.grey,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _contact.isActive ? '在线' : '离线',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // 所属群聊
                  if (_groups.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: isDarkMode ? const Color(0xFF2D2D2D) : Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.group, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                '所在群聊 (${_groups.length})',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ..._groups.map((group) => _buildGroupItem(group, isDarkMode)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),
                  // 变更历史
                  if (_changeLogs.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: isDarkMode ? const Color(0xFF2D2D2D) : Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '变更历史',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ..._changeLogs.take(5).map((log) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    Icon(
                                      _getChangeIcon(log.changeType),
                                      size: 16,
                                      color: Colors.grey,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _getChangeDescription(log),
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                                        ),
                                      ),
                                    ),
                                    Text(
                                      _formatTime(log.createdAt),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildAvatarText() {
    return Text(
      _contact.name.isNotEmpty ? _contact.name[0].toUpperCase() : '?',
      style: const TextStyle(
        fontSize: 32,
        color: Colors.white,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  IconData _getChangeIcon(ContactChangeType type) {
    switch (type) {
      case ContactChangeType.created:
        return Icons.add_circle;
      case ContactChangeType.updated:
        return Icons.edit;
      case ContactChangeType.deleted:
        return Icons.delete;
      case ContactChangeType.nameChanged:
        return Icons.person;
      case ContactChangeType.avatarChanged:
        return Icons.image;
      case ContactChangeType.statusChanged:
        return Icons.circle;
    }
  }

  String _getChangeDescription(ContactChangeLog log) {
    switch (log.changeType) {
      case ContactChangeType.created:
        return '创建了联系人';
      case ContactChangeType.updated:
        return '更新了联系人信息';
      case ContactChangeType.deleted:
        return '删除了联系人';
      case ContactChangeType.nameChanged:
        return '昵称从 "${log.oldValue}" 改为 "${log.newValue}"';
      case ContactChangeType.avatarChanged:
        return '更新了头像';
      case ContactChangeType.statusChanged:
        return '更新了状态';
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final logDay = DateTime(time.year, time.month, time.day);
    final diff = now.difference(time);

    if (logDay == today) {
      if (diff.inMinutes < 1) {
        return '刚刚';
      } else if (diff.inHours < 1) {
        return '${diff.inMinutes}分钟前';
      } else {
        return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
      }
    } else if (logDay == today.subtract(const Duration(days: 1))) {
      return '昨天';
    } else {
      return '${time.month}/${time.day}';
    }
  }

  Widget _buildGroupItem(GroupChat group, bool isDarkMode) {
    return InkWell(
      onTap: () => _navigateToGroupChat(group),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            // 群头像（显示前4个成员头像）
            _buildGroupAvatar(group),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${group.members.length} 位成员',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupAvatar(GroupChat group) {
    final members = group.members;
    if (members.isEmpty) {
      return Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.green,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.group,
          color: Colors.white,
          size: 24,
        ),
      );
    }

    final displayCount = members.length > 4 ? 4 : members.length;
    final displayMembers = members.take(displayCount).toList();

    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        children: [
          if (displayCount == 1)
            Positioned.fill(
              child: _buildMemberAvatar(displayMembers[0], 44),
            )
          else if (displayCount == 2)
            _buildGrid2(displayMembers)
          else if (displayCount == 3)
            _buildGrid3(displayMembers)
          else
            _buildGrid4(displayMembers),
        ],
      ),
    );
  }

  Widget _buildGrid2(List<GroupMember> members) {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: _buildMemberAvatar(members[0], 20)),
              const SizedBox(height: 2),
              Expanded(child: _buildMemberAvatar(members[1], 20)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGrid3(List<GroupMember> members) {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: _buildMemberAvatar(members[0], 32)),
              const SizedBox(width: 2),
              Expanded(
                child: Column(
                  children: [
                    Expanded(child: _buildMemberAvatar(members[1], 14)),
                    const SizedBox(height: 2),
                    Expanded(child: _buildMemberAvatar(members[2], 14)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGrid4(List<GroupMember> members) {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: _buildMemberAvatar(members[0], 20)),
              const SizedBox(width: 2),
              Expanded(child: _buildMemberAvatar(members[1], 20)),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Expanded(
          child: Row(
            children: [
              Expanded(child: _buildMemberAvatar(members[2], 20)),
              const SizedBox(width: 2),
              Expanded(child: _buildMemberAvatar(members[3], 20)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMemberAvatar(GroupMember member, double size) {
    if (member.userAvatar != null && member.userAvatar!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: Image.network(
          member.userAvatar!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildDefaultAvatar(member.userName, size),
        ),
      );
    }
    return _buildDefaultAvatar(member.userName, size);
  }

  Widget _buildDefaultAvatar(String name, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(2),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: size * 0.4,
            fontWeight: FontWeight.bold,
            color: Colors.grey[600],
          ),
        ),
      ),
    );
  }
}

/// 编辑联系人页面
class EditContactScreen extends StatefulWidget {
  final Contact contact;

  const EditContactScreen({super.key, required this.contact});

  @override
  State<EditContactScreen> createState() => _EditContactScreenState();
}

class _EditContactScreenState extends State<EditContactScreen> {
  late Contact _contact;
  final ContactService _contactService = ContactService();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _atNameController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _contact = widget.contact;
    _nameController.text = _contact.name;
    _atNameController.text = _contact.atName ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _atNameController.dispose();
    super.dispose();
  }

  void _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入名称')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final updated = await _contactService.updateContact(
        id: _contact.id,
        name: name,
        atName: _atNameController.text.trim().isEmpty ? null : _atNameController.text.trim(),
      );
      if (mounted) {
        Navigator.pop(context, updated);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑联系人'),
        backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '名称',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _atNameController,
              decoration: const InputDecoration(
                labelText: '@名称 (可选)',
                hintText: '用于@提及的标识符',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _save,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
