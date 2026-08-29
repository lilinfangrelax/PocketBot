import 'package:flutter/material.dart';
import 'package:pocket_bot/models/group_chat.dart';
import 'package:pocket_bot/services/group_chat_service.dart';
import 'package:pocket_bot/screens/group_chat_screen.dart';

/// 群聊列表页面
class GroupChatListScreen extends StatefulWidget {
  const GroupChatListScreen({super.key});

  @override
  State<GroupChatListScreen> createState() => _GroupChatListScreenState();
}

class _GroupChatListScreenState extends State<GroupChatListScreen> {
  final GroupChatService _groupChatService = GroupChatService();
  List<GroupChat> _groups = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    setState(() => _isLoading = true);
    try {
      // 获取所有群聊（包括已隐藏的）
      final groups = await _groupChatService.getAllGroups();
      setState(() {
        _groups = groups;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载群聊失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('群聊'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showCreateGroupDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _groups.isEmpty
              ? _buildEmptyState()
              : _buildGroupList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.group_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text('暂无群聊', style: TextStyle(color: Colors.grey[600])),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _showCreateGroupDialog,
            icon: const Icon(Icons.add),
            label: const Text('创建群聊'),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupList() {
    return RefreshIndicator(
      onRefresh: _loadGroups,
      child: ListView.builder(
        itemCount: _groups.length,
        itemBuilder: (context, index) {
          final group = _groups[index];
          return _GroupListTile(
            group: group,
            onTap: () => _openGroupChat(group),
            onShowInSessionList: group.showInSessionList 
                ? null 
                : () => _showGroupInSessionList(group),
          );
        },
      ),
    );
  }

  void _openGroupChat(GroupChat group) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GroupChatScreen(groupId: group.id)),
    ).then((_) => _loadGroups());
  }

  /// 将群聊恢复到会话列表
  Future<void> _showGroupInSessionList(GroupChat group) async {
    try {
      await _groupChatService.showGroupInSessionList(group.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已将 "${group.name}" 恢复到会话列表')),
        );
        _loadGroups();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e')),
        );
      }
    }
  }

  void _showCreateGroupDialog() {
    // TODO: 显示创建群聊对话框
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('创建群聊'),
        content: const Text('创建群聊功能开发中...'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}

class _GroupListTile extends StatelessWidget {
  final GroupChat group;
  final VoidCallback onTap;
  final VoidCallback? onShowInSessionList;

  const _GroupListTile({
    required this.group,
    required this.onTap,
    this.onShowInSessionList,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundImage: group.avatar != null ? NetworkImage(group.avatar!) : null,
        backgroundColor: Colors.green,
        child: group.avatar == null 
            ? Text(
                group.name.isNotEmpty ? group.name[0] : '?',
                style: const TextStyle(color: Colors.white),
              )
            : null,
      ),
      title: Text(group.name),
      subtitle: Row(
        children: [
          Text('${group.members.length} 位成员'),
          if (!group.showInSessionList) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '已隐藏',
                style: TextStyle(fontSize: 10, color: Colors.black54),
              ),
            ),
          ],
        ],
      ),
      trailing: onShowInSessionList != null
          ? IconButton(
              icon: const Icon(Icons.visibility, color: Colors.blue),
              tooltip: '恢复到会话列表',
              onPressed: onShowInSessionList,
            )
          : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
