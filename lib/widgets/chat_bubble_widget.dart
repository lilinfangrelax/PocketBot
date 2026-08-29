import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:pocket_bot/widgets/markdown_message_widget.dart';
import 'package:pocket_bot/widgets/attachment_widget.dart';

/// 共享的消息气泡组件
/// 用于普通会话和群聊的消息渲染
class ChatBubbleWidget extends StatelessWidget {
  /// 消息内容
  final String content;
  /// 是否是用户发送的消息
  final bool isUser;
  /// 是否是深色模式
  final bool isDarkMode;
  /// 发送者名称（群聊需要）
  final String? senderName;
  /// 发送者头像 URL 或 base64
  final String? senderAvatar;
  /// 当前用户 ID（用于判断是否是自己）
  final String? currentUserId;
  /// 消息 ID
  final String? messageId;
  /// 附件列表
  final List<dynamic> attachments;
  /// 消息状态（已发送、已读等）
  final bool isConfirmed;
  /// 消息是否正在流式输出
  final bool isStreaming;

  const ChatBubbleWidget({
    super.key,
    required this.content,
    required this.isUser,
    required this.isDarkMode,
    this.senderName,
    this.senderAvatar,
    this.currentUserId,
    this.messageId,
    this.attachments = const [],
    this.isConfirmed = false,
    this.isStreaming = false,
  });

  @override
  Widget build(BuildContext context) {
    // 气泡最大宽度 = 屏幕宽度 - 左边头像区域(48) - 右边头像区域(48) - 头像与气泡间距(8*2)
    // = 屏幕宽度 - 112
    final maxWidth = MediaQuery.of(context).size.width - 112;

    if (isUser) {
      return _buildUserBubble(context, maxWidth);
    } else {
      return _buildAIBubble(context, maxWidth);
    }
  }

  /// 构建用户消息气泡
  Widget _buildUserBubble(BuildContext context, double maxWidth) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 气泡 + 状态图标
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDarkMode ? const Color(0xFF3EB575) : const Color(0xFF95EC69),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(6),
                      topRight: Radius.circular(6),
                      bottomLeft: Radius.circular(6),
                      bottomRight: Radius.circular(2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (attachments.isNotEmpty)
                        AttachmentRow(
                          attachments: attachments.cast(),
                          isUser: isUser,
                          isDarkMode: isDarkMode,
                        ),
                      Flexible(
                        child: MarkdownMessageView(
                          content: content,
                          isDarkMode: isDarkMode,
                          isUser: isUser,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 状态图标
              _buildMessageStatus(),
            ],
          ),
          const SizedBox(width: 8),
          _buildAvatar(),
        ],
      ),
    );
  }

  /// 构建 AI/他人消息气泡
  Widget _buildAIBubble(BuildContext context, double maxWidth) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAvatar(),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF262626) : Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(6),
                  bottomLeft: Radius.circular(2),
                  bottomRight: Radius.circular(6),
                ),
                border: Border.all(
                  color: isDarkMode ? Colors.grey[700]! : Colors.grey[300]!,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 群聊：显示发送者名称
                  if (senderName != null && !isUser)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        senderName!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[600],
                        ),
                      ),
                    ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (attachments.isNotEmpty)
                        AttachmentRow(
                          attachments: attachments.cast(),
                          isUser: isUser,
                          isDarkMode: isDarkMode,
                        ),
                      Flexible(
                        child: MarkdownMessageView(
                          content: content,
                          isDarkMode: isDarkMode,
                          isUser: isUser,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建消息状态图标
  Widget _buildMessageStatus() {
    return Padding(
      padding: const EdgeInsets.only(left: 0, top: 2),
      child: SizedBox(
        width: 16,
        height: 16,
        child: isConfirmed
            ? Icon(
                Icons.done_all,
                size: 14,
                color: isDarkMode ? Colors.blue[300] : Colors.blue[400],
              )
            : Icon(
                Icons.done,
                size: 14,
                color: isDarkMode ? Colors.grey[500] : Colors.grey[400],
              ),
      ),
    );
  }

  /// 构建头像
  Widget _buildAvatar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isUser
            ? (isDarkMode ? const Color(0xFF4A4A4A) : Colors.grey[300])
            : (isDarkMode ? const Color(0xFF2D3A4A) : Colors.blue[100]),
        borderRadius: BorderRadius.circular(6),
      ),
      child: _buildAvatarContent(),
    );
  }

  Widget _buildAvatarContent() {
    // 如果有自定义头像
    if (senderAvatar != null && senderAvatar!.isNotEmpty) {
      if (senderAvatar!.startsWith('http')) {
        // 网络头像
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.network(
            senderAvatar!,
            fit: BoxFit.cover,
            width: 40,
            height: 40,
            errorBuilder: (_, __, ___) => _buildDefaultAvatar(),
          ),
        );
      } else if (senderAvatar!.length > 100) {
        // Base64 头像
        try {
          return ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.memory(
              base64Decode(senderAvatar!),
              fit: BoxFit.cover,
              width: 40,
              height: 40,
              errorBuilder: (_, __, ___) => _buildDefaultAvatar(),
            ),
          );
        } catch (_) {
          return _buildDefaultAvatar();
        }
      }
    }

    return _buildDefaultAvatar();
  }

  Widget _buildDefaultAvatar() {
    final displayName = isUser ? '我' : (senderName ?? (isUser ? '我' : 'AI'));
    return Icon(
      isUser ? Icons.person : Icons.group,
      color: isUser
          ? (isDarkMode ? Colors.grey[300] : Colors.grey[600])
          : (isDarkMode ? Colors.blue[300] : Colors.blue[400]),
      size: 24,
    );
  }
}

/// 时间分割线组件
class TimeDivider extends StatelessWidget {
  final DateTime time;

  const TimeDivider({super.key, required this.time});

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: isDarkMode 
              ? Colors.grey[800]!.withValues(alpha: 0.8) 
              : Colors.grey[300]!.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          _formatTime(time),
          style: TextStyle(
            fontSize: 12,
            color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(time.year, time.month, time.day);

    if (messageDay == today) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else if (messageDay == today.subtract(const Duration(days: 1))) {
      return '昨天 ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else {
      return '${time.month}月${time.day}日 ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
  }
}

/// 打字动画指示器
class TypingIndicator extends StatelessWidget {
  final bool isDarkMode;

  const TypingIndicator({super.key, required this.isDarkMode});

  @override
  Widget build(BuildContext context) {
    // 气泡最大宽度 = 屏幕宽度 - 112 (同上)
    final maxWidth = MediaQuery.of(context).size.width - 112;

    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(width: 8),
        // AI 头像
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isDarkMode ? const Color(0xFF2D3A4A) : Colors.blue[100],
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            Icons.group,
            color: isDarkMode ? Colors.blue[300] : Colors.blue[400],
            size: 24,
          ),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: IntrinsicHeight(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF2E2E2E) : Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(6),
                  bottomRight: Radius.circular(6),
                  bottomLeft: Radius.circular(2),
                ),
                border: Border.all(
                  color: isDarkMode ? Colors.grey[700]! : Colors.grey[300]!,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _TypingDots(isDarkMode: isDarkMode),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 50),
      ],
    );
  }
}

class _TypingDots extends StatefulWidget {
  final bool isDarkMode;

  const _TypingDots({required this.isDarkMode});

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      3,
      (index) => AnimationController(
        duration: const Duration(milliseconds: 300),
        vsync: this,
      ),
    );

    _animations = _controllers.map((controller) {
      return Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: controller, curve: Curves.easeInOut),
      );
    }).toList();

    _startAnimation();
  }

  void _startAnimation() async {
    while (mounted) {
      for (int i = 0; i < 3; i++) {
        if (!mounted) return;
        await Future.delayed(const Duration(milliseconds: 150));
        if (mounted) {
          _controllers[i].forward().then((_) {
            if (mounted) {
              _controllers[i].reverse();
            }
          });
        }
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _animations[index],
          builder: (context, child) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: widget.isDarkMode
                    ? Colors.grey[400]!.withValues(alpha: 0.4 + _animations[index].value * 0.6)
                    : Colors.grey[600]!.withValues(alpha: 0.4 + _animations[index].value * 0.6),
                shape: BoxShape.circle,
              ),
            );
          },
        );
      }),
    );
  }
}
