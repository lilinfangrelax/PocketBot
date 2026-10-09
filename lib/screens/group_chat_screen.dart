import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:pocket_bot/models/group_chat.dart';
import 'package:pocket_bot/services/group_chat_service.dart';
import 'package:pocket_bot/theme/fluent_theme.dart';
import 'package:pocket_bot/widgets/fluent_page.dart';
import 'package:pocket_bot/utils/logger.dart';
import 'package:pocket_bot/widgets/chat_bubble_widget.dart';

/// 群聊聊天页面 - 使用共享组件
class GroupChatScreen extends StatefulWidget {
  final String groupId;

  const GroupChatScreen({super.key, required this.groupId});

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final GroupChatService _groupChatService = GroupChatService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  GroupChat? _group;
  List<GroupMessage> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  final Set<String> _thinking = {};

  // 当前用户信息（应该从用户服务获取）
  final String _currentUserId = 'current_user';
  final String _currentUserName = '我';
  String? _currentUserAvatar;

  @override
  void initState() {
    super.initState();
    _loadGroup();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadGroup() async {
    setState(() => _isLoading = true);
    try {
      // 获取群聊信息
      final groups = await _groupChatService.getAllGroups();
      _group = groups.firstWhere(
        (g) => g.id == widget.groupId,
        orElse: () => throw Exception('群聊不存在'),
      );

      // 获取群消息
      _messages = await _groupChatService.getGroupMessages(widget.groupId);
      _messages = _messages.reversed.toList(); // 按时间正序排列
    } catch (e) {
      Logger.warning('Failed to load group: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    setState(() => _isSending = true);
    _messageController.clear();

    try {
      // 创建消息
      final message = GroupMessage(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        groupId: widget.groupId,
        senderId: _currentUserId,
        senderName: _currentUserName,
        senderAvatar: _currentUserAvatar,
        content: content,
        timestamp: DateTime.now(),
      );

      // 保存到数据库
      await _groupChatService.sendGroupMessage(message);

      // 更新 UI
      setState(() {
        _messages.add(message);
      });

      // 滚动到底部
      _scrollToBottom();

      _dispatchToAgents(message);
    } catch (e) {
      Logger.error('Failed to send message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _dispatchToAgents(GroupMessage message) async {
    final group = _group;
    if (group == null) return;
    final replies = await _groupChatService.dispatchToAgents(
      group,
      message,
      onStatus: (name, error) {
        if (!mounted) return;
        setState(() {
          if (error == null) {
            _thinking.add(name);
          } else {
            _thinking.remove(name);
          }
        });
        if (error != null) showAppNotice(context, '$name 无法回复：$error');
      },
    );
    if (!mounted) return;
    setState(() {
      _thinking.clear();
      _messages.addAll(replies);
      _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// 构建带时间分割线的消息列表
  List<dynamic> _buildMessageItems() {
    final items = <dynamic>[];
    DateTime? lastTimestamp;

    for (final message in _messages) {
      // 超过5分钟显示时间分割线
      if (lastTimestamp == null ||
          message.timestamp.difference(lastTimestamp).inMinutes > 5) {
        items.add({'type': 'time', 'time': message.timestamp});
      }
      items.add({'type': 'message', 'message': message});
      lastTimestamp = message.timestamp;
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final colors = FluentColors.of(context);
    final messageItems = _buildMessageItems();

    return FluentScreen(
      title: Text(_group?.name ?? '群聊'),
      content: _isLoading
          ? const Center(child: fluent.ProgressRing())
          : Column(
              children: [
                // 消息列表
                Expanded(
                  child: Container(
                    color: colors.background,
                    child: _messages.isEmpty
                        ? _buildEmptyState(isDarkMode)
                        : GestureDetector(
                            onTap: () => FocusScope.of(context).unfocus(),
                            child: ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              itemCount: messageItems.length,
                              itemBuilder: (context, index) {
                                final item = messageItems[index];
                                if (item['type'] == 'time') {
                                  return TimeDivider(time: item['time']);
                                } else {
                                  final message =
                                      item['message'] as GroupMessage;
                                  final isMe =
                                      message.senderId == _currentUserId;
                                  return ChatBubbleWidget(
                                    content: message.content,
                                    isUser: isMe,
                                    isDarkMode: isDarkMode,
                                    senderName:
                                        isMe ? null : message.senderName,
                                    senderAvatar: message.senderAvatar,
                                    currentUserId: _currentUserId,
                                    messageId: message.id,
                                  );
                                }
                              },
                            ),
                          ),
                  ),
                ),

                // 打字指示器
                if (_thinking.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: fluent.ProgressRing(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_thinking.join('、')} 正在回复…',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // 输入框
                _buildInputBar(isDarkMode),
              ],
            ),
    );
  }

  Widget _buildEmptyState(bool isDarkMode) {
    final colors = FluentColors.of(context);
    return Container(
      color: colors.background,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.stroke),
              ),
              child: Icon(
                Icons.group_outlined,
                size: 60,
                color: isDarkMode ? Colors.grey[600] : Colors.grey[400],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '暂无消息',
              style: TextStyle(
                fontSize: 16,
                color: isDarkMode ? Colors.grey[400] : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(bool isDarkMode) {
    final colors = FluentColors.of(context);
    return Container(
      color: colors.chrome,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 输入框
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 100),
                decoration: BoxDecoration(
                  color: colors.control,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: colors.strokeStrong),
                ),
                child: TextField(
                  controller: _messageController,
                  decoration: InputDecoration(
                    hintText: '@名称 让代理回复',
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    isDense: true,
                    hintStyle: TextStyle(
                      color: isDarkMode ? Colors.grey[600] : Colors.grey[400],
                    ),
                  ),
                  maxLines: null,
                  style: TextStyle(
                    fontSize: 16,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _sendMessage(),
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.send,
                ),
              ),
            ),
            const SizedBox(width: 4),
            // 发送/更多按钮
            IconButton(
              onPressed: _messageController.text.trim().isEmpty
                  ? null // TODO: 展开更多菜单
                  : _isSending
                      ? null
                      : _sendMessage,
              icon: _isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _messageController.text.trim().isEmpty
                          ? Icons.add
                          : Icons.send,
                      size: 22,
                    ),
              style: IconButton.styleFrom(
                backgroundColor: _messageController.text.isNotEmpty
                    ? colors.accent
                    : Colors.transparent,
                foregroundColor: _messageController.text.isNotEmpty
                    ? colors.onAccent
                    : colors.textSecondary,
                side: BorderSide(
                  color: _messageController.text.isEmpty
                      ? colors.strokeStrong
                      : Colors.transparent,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            ),
          ],
        ),
      ),
    );
  }
}
