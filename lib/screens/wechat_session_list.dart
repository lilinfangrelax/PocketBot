import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pocket_bot/config/session_storage.dart';
import 'package:pocket_bot/models/message.dart';
import 'package:pocket_bot/models/group_chat.dart';
import 'package:pocket_bot/screens/chat_screen.dart';
import 'package:pocket_bot/screens/group_chat_screen.dart';
import 'package:pocket_bot/services/connection_manager.dart';
import 'package:pocket_bot/services/group_chat_service.dart';
import 'package:pocket_bot/widgets/unread_badge.dart';
import 'package:pocket_bot/utils/logger.dart';
import 'package:pocket_bot/services/websocket_service.dart';

/// 会话项类型
enum SessionItemType { personal, group }

/// 统一的会话项（个人会话或群聊）
class SessionItem {
  final SessionItemType type;
  final ChatSession? personalSession;
  final GroupChat? groupChat;
  final DateTime lastUpdated;
  final String title;
  final String? lastMessage;
  final int unreadCount;

  SessionItem({
    required this.type,
    this.personalSession,
    this.groupChat,
    required this.lastUpdated,
    required this.title,
    this.lastMessage,
    this.unreadCount = 0,
  }) : assert((type == SessionItemType.personal && personalSession != null) ||
           (type == SessionItemType.group && groupChat != null));

  String get key => type == SessionItemType.personal 
      ? personalSession!.key 
      : 'group_${groupChat!.id}';
}

class WeChatSessionList extends StatefulWidget {
  const WeChatSessionList({super.key});

  @override
  State<WeChatSessionList> createState() => _WeChatSessionListState();
}

class _WeChatSessionListState extends State<WeChatSessionList> {
  List<SessionItem> _allSessions = [];
  List<SessionItem> _filteredSessions = [];
  bool _isLoading = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final GroupChatService _groupChatService = GroupChatService();
  // Step 1 fix: track listener ref and service for cleanup
  VoidCallback? _wsListener;
  WebSocketService? _wsService;

  @override
  void initState() {
    super.initState();
    _loadSessions();
    _listenToSessionChanges();
  }

  void _listenToSessionChanges() {
    _wsService = context.read<ConnectionManager>().wsService;
    
    _wsListener = () {
      if (mounted) {
        _refreshSessions();
      }
    };
    _wsService!.addListener(_wsListener!);
  }

  Future<void> _refreshSessions() async {
    if (!mounted) return;
    await _loadSessions();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadSessions() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final wsService = context.read<ConnectionManager>().wsService;
      
      // Load personal sessions from local storage
      final sessions = await SessionStorage.loadAllSessions();
      
      // Merge with in-memory session state (to get real-time unreadCount)
      for (final session in sessions) {
        final sessionState = wsService.getSession(session.key);
        if (sessionState != null) {
          session.unreadCount = sessionState.unreadCount;
          session.messages = List.from(sessionState.messages);
          session.lastUpdated = sessionState.lastUpdated;
        }
      }
      
      // Convert personal sessions to SessionItem
      List<SessionItem> sessionItems = sessions.map((s) => SessionItem(
        type: SessionItemType.personal,
        personalSession: s,
        lastUpdated: s.lastUpdated,
        title: s.title,
        lastMessage: s.lastMessagePreview ?? (s.messages.isNotEmpty ? s.messages.last.text : null),
        unreadCount: s.unreadCount,
      )).toList();
      
      // Load group chats (only show in session list)
      try {
        final groups = await _groupChatService.getAllGroups(showInSessionList: true);
        for (final group in groups) {
          final lastMessage = await _groupChatService.getGroupLastMessage(group.id);
          sessionItems.add(SessionItem(
            type: SessionItemType.group,
            groupChat: group,
            lastUpdated: lastMessage?.timestamp ?? group.createdAt,
            title: group.name,
            lastMessage: lastMessage?.content,
            unreadCount: 0, // TODO: 群聊未读数
          ));
        }
      } catch (e) {
        Logger.warning('Failed to load groups: $e');
      }
      
      if (!mounted) return;
      
      _allSessions = sessionItems
        ..sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));
      
      _updateFilteredSessions();
    } catch (e) {
      Logger.warning('Failed to load sessions: $e');
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _updateFilteredSessions() {
    if (_searchQuery.isEmpty) {
      _filteredSessions = List.from(_allSessions);
    } else {
      _filteredSessions = _allSessions
          .where((s) =>
              s.title.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }
  }

  /// 跳转到群聊
  void _navigateToGroupChat(GroupChat group) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GroupChatScreen(groupId: group.id)),
    ).then((_) => _loadSessions());
  }

  void _showSearch() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _buildSearchSheet(),
    );
  }

  Widget _buildSearchSheet() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _searchController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: '搜索会话',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _searchQuery = '';
                    _updateFilteredSessions();
                  });
                },
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
                _updateFilteredSessions();
              });
            },
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: _filteredSessions.length,
              itemBuilder: (context, index) {
                final session = _filteredSessions[index];
                return _buildSessionItem(session, session.key);
              },
            ),
          ),
        ],
      ),
    );
  }

  void _createSession() {
    final wsService = context.read<ConnectionManager>().wsService;
    wsService.createNewSession();
    _navigateToChat();
  }

  void _navigateToChat() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ChatScreen()),
    ).then((_) => _loadSessions());
  }

  void _selectSession(SessionItem sessionItem) {
    if (sessionItem.type == SessionItemType.group) {
      // 群聊
      _navigateToGroupChat(sessionItem.groupChat!);
    } else {
      // 个人会话
      final wsService = context.read<ConnectionManager>().wsService;
      // Deactivate current session first so incoming messages can be counted as unread
      wsService.deactivateCurrentSession();
      wsService.selectSession(sessionItem.personalSession!.key, agentId: sessionItem.personalSession!.agentId);
      _navigateToChat();
    }
  }

  Future<void> _deleteSession(SessionItem sessionItem) async {
    if (sessionItem.type == SessionItemType.personal) {
      final wsService = context.read<ConnectionManager>().wsService;
      await wsService.deleteSession(sessionItem.personalSession!.key);
    } else {
      // 群聊：从会话列表中隐藏
      await _groupChatService.hideGroupFromSessionList(sessionItem.groupChat!.id);
    }
    _loadSessions();
  }

  void _showDeleteConfirmation(SessionItem sessionItem) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除会话'),
        content: Text('确定要删除 "${sessionItem.title}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteSession(sessionItem);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionItem(SessionItem sessionItem, String sessionKey) {
    final wsService = context.read<ConnectionManager>().wsService;
    final isCurrentSession = sessionItem.type == SessionItemType.personal && 
        sessionKey == wsService.currentSessionKey;

    // Get unread count
    int unreadCount = sessionItem.unreadCount;
    if (sessionItem.type == SessionItemType.personal) {
      final sessionState = wsService.getSession(sessionKey);
      unreadCount = sessionState?.unreadCount ?? sessionItem.unreadCount;
    }

    return Dismissible(
      key: Key(sessionKey),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        _showDeleteConfirmation(sessionItem);
        return false;
        },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: GestureDetector(
        onTap: () => _selectSession(sessionItem),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.grey[200]!),
            ),
          ),
          child: Row(
            children: [
              _buildAvatar(sessionItem, isCurrentSession),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            sessionItem.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          _formatTime(sessionItem.lastUpdated),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            sessionItem.lastMessage ?? '暂无消息',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (unreadCount > 0)
                          UnreadBadge(count: unreadCount),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(SessionItem sessionItem, bool isCurrentSession) {
    if (sessionItem.type == SessionItemType.group) {
      // 群聊头像：多个头像的集合
      return _buildGroupAvatar(sessionItem.groupChat!);
    } else {
      // 个人会话头像
      const icon = Icons.chat_bubble;
      const iconColor = Colors.white;
      const bgColor = Colors.blue;

      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          icon,
          color: iconColor,
          size: 26,
        ),
      );
    }
  }

  /// 构建群聊头像（多个头像的集合）
  Widget _buildGroupAvatar(GroupChat group) {
    final members = group.members;
    if (members.isEmpty) {
      // 无成员，显示默认群聊图标
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.green,
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(
          Icons.group,
          color: Colors.white,
          size: 26,
        ),
      );
    }

    // 最多显示4个头像（2x2网格）
    final displayCount = members.length > 4 ? 4 : members.length;
    final displayMembers = members.take(displayCount).toList();

    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        children: [
          // 2x2 网格布局
          if (displayCount == 1)
            Positioned.fill(
              child: _buildMemberAvatar(displayMembers[0], 48),
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
              Expanded(child: _buildMemberAvatar(members[0], 22)),
              const SizedBox(height: 2),
              Expanded(child: _buildMemberAvatar(members[1], 22)),
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
              Expanded(child: _buildMemberAvatar(members[0], 34)),
              const SizedBox(height: 2),
              Expanded(
                child: Column(
                  children: [
                    Expanded(child: _buildMemberAvatar(members[1], 16)),
                    const SizedBox(height: 2),
                    Expanded(child: _buildMemberAvatar(members[2], 16)),
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
              Expanded(child: _buildMemberAvatar(members[0], 22)),
              const SizedBox(height: 2),
              Expanded(child: _buildMemberAvatar(members[1], 22)),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Expanded(
          child: Row(
            children: [
              Expanded(child: _buildMemberAvatar(members[2], 22)),
              const SizedBox(height: 2),
              Expanded(child: _buildMemberAvatar(members[3], 22)),
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

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(time.year, time.month, time.day);
    final diff = now.difference(time);

    if (messageDay == today) {
      if (diff.inMinutes < 1) {
        return '刚刚';
      } else if (diff.inHours < 1) {
        return '${diff.inMinutes}分钟前';
      } else {
        return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
      }
    } else if (messageDay == today.subtract(const Duration(days: 1))) {
      return '昨天';
    } else {
      return '${time.month}/${time.day}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : const Color(0xFFEDEDED),
        elevation: 0,
        title: const Text(
          '消息',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w500,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _showSearch,
            color: isDarkMode ? Colors.white : Colors.black87,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _createSession,
            color: isDarkMode ? Colors.white : Colors.black87,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _allSessions.isEmpty
              ? _buildEmptyState(isDarkMode)
              : RefreshIndicator(
                  onRefresh: _loadSessions,
                  child: ListView.builder(
                    // 添加缓存区域优化滚动性能
                    cacheExtent: 150,
                    itemCount: _allSessions.length,
                    itemBuilder: (context, index) {
                      final session = _allSessions[index];
                      // 使用 RepaintBoundary 隔离重绘
                      return RepaintBoundary(
                        child: _buildSessionItem(session, session.key),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState(bool isDarkMode) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 80,
            color: isDarkMode ? Colors.grey[700] : Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            '暂无会话',
            style: TextStyle(
              fontSize: 16,
              color: isDarkMode ? Colors.grey[500] : Colors.grey[500],
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _createSession,
            icon: const Icon(Icons.add),
            label: const Text('新建会话'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Step 1 fix: clean up listener ref using stored service
    if (_wsListener != null && _wsService != null) {
      _wsService!.removeListener(_wsListener!);
    }
    _searchController.dispose();
    super.dispose();
  }
}
