import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pocket_bot/models/group_chat.dart';
import 'package:pocket_bot/services/group_chat_service.dart';
import 'package:pocket_bot/services/connection_manager.dart';
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
  bool _isTyping = false; // AI 正在输入

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

      // TODO: 处理@提及和AI响应
      // 模拟 AI 响应（实际应该连接 AI 服务）
      _simulateAIResponse();
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

  /// 模拟 AI 响应（placeholder）
  void _simulateAIResponse() async {
    // 显示正在输入
    setState(() => _isTyping = true);
    
    // 模拟延迟
    await Future.delayed(const Duration(seconds: 2));
    
    if (!mounted) return;
    
    // 创建 AI 消息
    final aiMessage = GroupMessage(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
      groupId: widget.groupId,
      senderId: 'ai_assistant',
      senderName: 'AI 助手',
      senderAvatar: null,
      content: '收到消息: "${_messages.last.content}"\n\n这是一个群聊测试消息。',
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(aiMessage);
      _isTyping = false;
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
    final messageItems = _buildMessageItems();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: isDarkMode ? const Color(0xFF191919) : const Color(0xFFEDEDED),
        elevation: isDarkMode ? 0 : 0.5,
        title: Text(
          _group?.name ?? '群聊',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w500,
            color: isDarkMode ? Colors.white : Colors.black87,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 消息列表
                Expanded(
                  child: Container(
                    color: isDarkMode ? const Color(0xFF191919) : const Color(0xFFF5F5F5),
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
                                  final message = item['message'] as GroupMessage;
                                  final isMe = message.senderId == _currentUserId;
                                  return ChatBubbleWidget(
                                    content: message.content,
                                    isUser: isMe,
                                    isDarkMode: isDarkMode,
                                    senderName: isMe ? null : message.senderName,
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
                if (_isTyping)
                  TypingIndicator(isDarkMode: isDarkMode),

                // 输入框
                _buildInputBar(isDarkMode),
              ],
            ),
    );
  }

  Widget _buildEmptyState(bool isDarkMode) {
    return Container(
      color: isDarkMode ? const Color(0xFF191919) : const Color(0xFFF5F5F5),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF2E2E2E) : Colors.white,
                borderRadius: BorderRadius.circular(12),
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
    return Container(
      color: isDarkMode ? const Color(0xFF191919) : const Color(0xFFF7F7F7),
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
                  color: isDarkMode ? const Color(0xFF2E2E2E) : Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isDarkMode ? Colors.grey[700]! : Colors.grey[300]!,
                  ),
                ),
                child: TextField(
                  controller: _messageController,
                  decoration: InputDecoration(
                    hintText: '',
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
                  : _isSending ? null : _sendMessage,
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
                    ? const Color(0xFF07C160)
                    : Colors.transparent,
                foregroundColor: _messageController.text.isNotEmpty
                    ? Colors.white
                    : isDarkMode ? Colors.grey[400] : Colors.grey[600],
                side: BorderSide(
                  color: _messageController.text.isEmpty
                      ? (isDarkMode ? Colors.grey[700]! : Colors.grey[400]!)
                      : Colors.transparent,
                  width: 1,
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
