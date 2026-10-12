import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pocket_bot/models/contact.dart';
import 'package:pocket_bot/models/group_workspace.dart';
import 'package:pocket_bot/services/connection_manager.dart';
import 'package:pocket_bot/services/contact_service.dart';
import 'package:pocket_bot/services/group_chat_service.dart';
import 'package:pocket_bot/widgets/workspace_picker.dart';

/// 群组成员模型
class GroupMember {
  final String id;
  final String name;
  final String? avatar;
  final bool isAdmin;

  GroupMember({
    required this.id,
    required this.name,
    this.avatar,
    this.isAdmin = false,
  });

  factory GroupMember.fromContact(Contact contact, {bool isAdmin = false}) {
    return GroupMember(
      id: contact.id,
      name: contact.name,
      avatar: contact.avatar,
      isAdmin: isAdmin,
    );
  }
}

/// 创建群组页面
class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final TextEditingController _groupNameController = TextEditingController();
  final ContactService _contactService = ContactService();
  final GroupChatService _groupChatService = GroupChatService();
  List<Contact> _availableContacts = [];
  List<GroupMember> _selectedMembers = [];
  GroupWorkspace? _workspace;
  bool _isLoading = true;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    setState(() => _isLoading = true);
    try {
      _availableContacts = await _contactService.getAllContacts();
    } catch (e) {
      _showError('加载联系人失败: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _toggleMember(Contact contact) {
    setState(() {
      final index = _selectedMembers.indexWhere((m) => m.id == contact.id);
      if (index >= 0) {
        _selectedMembers.removeAt(index);
      } else {
        _selectedMembers.add(GroupMember.fromContact(contact));
      }
    });
  }

  bool _isSelected(String contactId) {
    return _selectedMembers.any((m) => m.id == contactId);
  }

  void _createGroup() async {
    final groupName = _groupNameController.text.trim();
    if (groupName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入群组名称')),
      );
      return;
    }

    if (_selectedMembers.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少选择2个联系人')),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      // 获取选中的联系人ID列表
      final memberIds = _selectedMembers.map((m) => m.id).toList();

      // 调用服务创建群聊
      final group = await _groupChatService.createGroup(groupName, memberIds);
      final workspace = _workspace;
      if (workspace != null) {
        await _groupChatService.workspaces.save(GroupWorkspace(
          groupId: group.id,
          hostId: workspace.hostId,
          workingDirectory: workspace.workingDirectory,
        ));
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('群组 "$groupName" 创建成功！')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  Future<void> _pickWorkspace() async {
    final choice = await pickWorkspace(
      context,
      groupId: '',
      current: _workspace,
    );
    if (choice == null || !mounted) return;
    setState(() => _workspace = choice.workspace);
  }

  Widget _buildWorkspaceTile() {
    final workspace = _workspace;
    return ListTile(
      leading: const Icon(Icons.folder_outlined),
      title: const Text('群聊工作目录'),
      subtitle: Text(
        workspace == null
            ? '可选。设置后所有 AI 成员都在这个目录里工作'
            : workspaceLabel(context.read<ConnectionManager>(), workspace),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: _pickWorkspace,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('创建群组'),
        actions: [
          _isCreating
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : TextButton(
                  onPressed: _createGroup,
                  child: const Text('创建'),
                ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 群组名称输入
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Theme.of(context).colorScheme.surfaceContainerLowest,
                  child: TextField(
                    controller: _groupNameController,
                    decoration: const InputDecoration(
                      labelText: '群组名称',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                _buildWorkspaceTile(),
                // 已选择成员
                if (_selectedMembers.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '已选择 ${_selectedMembers.length} 人',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _selectedMembers.map((member) {
                            return Chip(
                              label: Text(member.name),
                              deleteIcon: const Icon(Icons.close, size: 16),
                              onDeleted: () => _toggleMember(
                                _availableContacts
                                    .firstWhere((c) => c.id == member.id),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                const Divider(),
                // 联系人列表
                Expanded(
                  child: _availableContacts.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.people_outline,
                                size: 60,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '暂无联系人',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[500],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '请先添加联系人',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[400],
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _availableContacts.length,
                          itemBuilder: (context, index) {
                            final contact = _availableContacts[index];
                            final isSelected = _isSelected(contact.id);

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    Theme.of(context).colorScheme.primary,
                                child: contact.avatar != null &&
                                        contact.avatar!.isNotEmpty
                                    ? ClipOval(
                                        child: Image.network(
                                          contact.avatar!,
                                          width: 40,
                                          height: 40,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              _buildAvatarText(contact.name),
                                        ),
                                      )
                                    : _buildAvatarText(contact.name),
                              ),
                              title: Text(contact.name),
                              subtitle: contact.atName != null &&
                                      contact.atName!.isNotEmpty
                                  ? Text('@${contact.atName}')
                                  : null,
                              trailing: Checkbox(
                                value: isSelected,
                                onChanged: (_) => _toggleMember(contact),
                                activeColor:
                                    Theme.of(context).colorScheme.primary,
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildAvatarText(String name) {
    return Text(
      name.isNotEmpty ? name[0].toUpperCase() : '?',
      style: TextStyle(
        color: Theme.of(context).colorScheme.onPrimary,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}
