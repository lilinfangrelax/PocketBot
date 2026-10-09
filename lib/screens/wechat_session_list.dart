import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pocket_bot/config/session_storage.dart';
import 'package:pocket_bot/models/message.dart';
import 'package:pocket_bot/models/group_chat.dart';
import 'package:pocket_bot/screens/chat_screen.dart';
import 'package:pocket_bot/screens/group_chat_screen.dart';
import 'package:pocket_bot/services/connection_manager.dart';
import 'package:pocket_bot/services/group_chat_service.dart';
import 'package:pocket_bot/widgets/fluent_page.dart';
import 'package:pocket_bot/widgets/unread_badge.dart';
import 'package:pocket_bot/theme/fluent_theme.dart';
import 'package:pocket_bot/utils/logger.dart';
import 'package:pocket_bot/services/websocket_service.dart';

const double _kAvatarSize = 44;

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
      List<SessionItem> sessionItems = sessions
          .map((s) => SessionItem(
                type: SessionItemType.personal,
                personalSession: s,
                lastUpdated: s.lastUpdated,
                title: s.title,
                lastMessage: s.lastMessagePreview ??
                    (s.messages.isNotEmpty ? s.messages.last.text : null),
                unreadCount: s.unreadCount,
              ))
          .toList();

      // Load group chats (only show in session list)
      try {
        final groups =
            await _groupChatService.getAllGroups(showInSessionList: true);
        for (final group in groups) {
          final lastMessage =
              await _groupChatService.getGroupLastMessage(group.id);
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
          .where(
              (s) => s.title.toLowerCase().contains(_searchQuery.toLowerCase()))
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
          fluent.TextBox(
            controller: _searchController,
            autofocus: true,
            placeholder: '搜索会话',
            prefix: const Padding(
              padding: EdgeInsetsDirectional.only(start: 10),
              child: Icon(fluent.WindowsIcons.search, size: 14),
            ),
            suffix: fluent.IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _searchQuery = '';
                  _updateFilteredSessions();
                });
              },
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
      wsService.selectSession(sessionItem.personalSession!.key,
          agentId: sessionItem.personalSession!.agentId);
      _navigateToChat();
    }
  }

  Future<void> _deleteSession(SessionItem sessionItem) async {
    if (sessionItem.type == SessionItemType.personal) {
      final wsService = context.read<ConnectionManager>().wsService;
      await wsService.deleteSession(sessionItem.personalSession!.key);
    } else {
      // 群聊：从会话列表中隐藏
      await _groupChatService
          .hideGroupFromSessionList(sessionItem.groupChat!.id);
    }
    _loadSessions();
  }

  void _showDeleteConfirmation(SessionItem sessionItem) {
    fluent.showDialog(
      context: context,
      builder: (context) => fluent.ContentDialog(
        title: const Text('删除会话'),
        content: Text('确定要删除 "${sessionItem.title}" 吗？'),
        actions: [
          fluent.Button(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          fluent.FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteSession(sessionItem);
            },
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
        color: FluentColors.of(context).danger,
        child: Icon(fluent.WindowsIcons.delete,
            color: FluentColors.of(context).onAccent),
      ),
      child: _SessionRow(
        selected: isCurrentSession,
        onTap: () => _selectSession(sessionItem),
        avatar: _buildAvatar(sessionItem, isCurrentSession),
        title: sessionItem.title,
        time: _formatTime(sessionItem.lastUpdated),
        preview: sessionItem.lastMessage ?? '暂无消息',
        unreadCount: unreadCount,
      ),
    );
  }

  Widget _buildAvatar(SessionItem sessionItem, bool isCurrentSession) {
    if (sessionItem.type == SessionItemType.group) {
      // 群聊头像：多个头像的集合
      return _buildGroupAvatar(sessionItem.groupChat!);
    } else {
      return const FluentIconAvatar(
        icon: fluent.WindowsIcons.chat_bubbles,
        size: _kAvatarSize,
      );
    }
  }

  /// 构建群聊头像（多个头像的集合）
  Widget _buildGroupAvatar(GroupChat group) {
    final members = group.members;
    if (members.isEmpty) {
      // 无成员，显示默认群聊图标
      return const FluentIconAvatar(
        icon: fluent.WindowsIcons.people,
        size: _kAvatarSize,
      );
    }

    // 最多显示4个头像（2x2网格）
    final displayCount = members.length > 4 ? 4 : members.length;
    final displayMembers = members.take(displayCount).toList();

    return SizedBox(
      width: _kAvatarSize,
      height: _kAvatarSize,
      child: Stack(
        children: [
          // 2x2 网格布局
          if (displayCount == 1)
            Positioned.fill(
              child: _buildMemberAvatar(displayMembers[0], _kAvatarSize),
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
          errorBuilder: (_, __, ___) =>
              _buildDefaultAvatar(member.userName, size),
        ),
      );
    }
    return _buildDefaultAvatar(member.userName, size);
  }

  Widget _buildDefaultAvatar(String name, double size) {
    final colors = FluentColors.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.accentSubtle,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: size * 0.4,
            fontWeight: FontWeight.w600,
            color: colors.accent,
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
    return FluentScreen(
      title: const Text('消息'),
      commands: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          fluent.IconButton(
            icon: const Icon(fluent.WindowsIcons.search),
            onPressed: _showSearch,
          ),
          fluent.IconButton(
            icon: const Icon(fluent.WindowsIcons.add),
            onPressed: _createSession,
          ),
        ],
      ),
      content: _isLoading
          ? const Center(child: fluent.ProgressRing())
          : _allSessions.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadSessions,
                  child: ListView.builder(
                    cacheExtent: 150,
                    itemCount: _allSessions.length,
                    itemBuilder: (context, index) {
                      final session = _allSessions[index];
                      return RepaintBoundary(
                        child: _buildSessionItem(session, session.key),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    final colors = FluentColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const FluentIconAvatar(
              icon: fluent.WindowsIcons.chat_bubbles,
              size: 72,
            ),
            const SizedBox(height: 16),
            Text(
              '暂无会话',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '新建一个会话，开始和代理聊天',
              style: TextStyle(fontSize: 13, color: colors.textSecondary),
            ),
            const SizedBox(height: 20),
            fluent.FilledButton(
              onPressed: _createSession,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(fluent.WindowsIcons.add, size: 14),
                  SizedBox(width: 8),
                  Text('新建会话'),
                ],
              ),
            ),
          ],
        ),
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

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.selected,
    required this.onTap,
    required this.avatar,
    required this.title,
    required this.time,
    required this.preview,
    required this.unreadCount,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget avatar;
  final String title;
  final String time;
  final String preview;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final colors = FluentColors.of(context);
    return fluent.HoverButton(
      onPressed: onTap,
      builder: (context, states) {
        final Color background;
        if (states.isPressed) {
          background = colors.stroke;
        } else if (selected) {
          background = colors.accentSubtle;
        } else {
          background = const Color(0x00000000);
        }
        return ColoredBox(
          color: background,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 16),
            child: Row(
              children: [
                avatar,
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsetsDirectional.only(
                      top: 14,
                      bottom: 14,
                      end: 16,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: colors.stroke),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: colors.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              time,
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                preview,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: colors.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (unreadCount > 0) ...[
                              const SizedBox(width: 8),
                              UnreadBadge(count: unreadCount),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
