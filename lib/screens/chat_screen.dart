import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:pocket_bot/config/session_storage.dart';
import 'package:pocket_bot/config/user_config.dart';
import 'package:pocket_bot/main.dart';
import 'package:pocket_bot/models/message.dart';
import 'package:pocket_bot/services/connection_manager.dart';
import 'package:pocket_bot/services/websocket_service.dart';
import 'package:pocket_bot/utils/logger.dart';
import 'package:pocket_bot/widgets/attachment_widget.dart';
import 'package:pocket_bot/widgets/markdown_message_widget.dart';

/// Keyboard intents for chat input
class _SendIntent extends Intent {
  const _SendIntent();
}

class _NewLineIntent extends Intent {
  const _NewLineIntent();
}

/// Actions for handling keyboard events
class _SendAction extends Action<_SendIntent> {
  final VoidCallback onSend;

  _SendAction(this.onSend);

  @override
  void invoke(covariant _SendIntent intent) {
    // 只在有内容时发送
    onSend();
  }
}

class _NewLineAction extends Action<_NewLineIntent> {
  final TextEditingController controller;

  _NewLineAction(this.controller);

  @override
  void invoke(covariant _NewLineIntent intent) {
    // Insert newline at cursor position
    final text = controller.text;
    final selection = controller.selection;
    final newText = text.replaceRange(selection.start, selection.end, '\n');
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: selection.start + 1),
    );
  }
}

/// Message item wrapper for rendering messages with time dividers
class _MessageItem {
  final Message? message;
  final DateTime? timestamp;

  _MessageItem.message(this.message) : timestamp = null;
  _MessageItem.timestamp(this.timestamp) : message = null;

  bool get isTimestamp => timestamp != null;
  bool get isMessage => message != null;
}

/// Chat screen - Conversation with an ACP Agent
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Message> _messages = [];
  bool _isTyping = false;
  bool _isGenerating = false; // AI 正在生成回复的状态
  final List<_MessageItem> _messageItems = [];
  bool _hasMarkedReadOnScroll = false;
  String? _currentLoadedSessionKey; // Step 3 fix: prevent infinite reload
  String? _userAvatarBase64; // User custom avatar
  WebSocketService?
      _wsService; // Cached reference to avoid context access in async callbacks

  // Step 1 fix: track listener/subscription refs for cleanup
  VoidCallback? _wsListener;
  StreamSubscription<Message>? _messageSub;
  StreamSubscription<Message>? _messageUpdateSub;
  StreamSubscription<Map<String, dynamic>>? _eventSub;
  StreamSubscription<Map<String, dynamic>>? _clientRequestSub;
  StreamSubscription<void>? _userConfigSub;
  bool _syncScheduled = false;
  bool _pendingScroll = false;

  @override
  void initState() {
    super.initState();
    // Cache wsService reference to avoid context access in async callbacks
    _wsService = context.read<ConnectionManager>().wsService;
    _listenToMessages();
    _scrollController.addListener(_onScroll);
    _loadUserAvatar(); // Load user avatar
    _listenForClientRequests();

    // Listen for user config changes (e.g., avatar update)
    _userConfigSub =
        context.read<UserConfigProvider>().configChanged.listen((_) {
      if (mounted) {
        _loadUserAvatar();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await _wsService?.ensureActiveRemoteSession();
      } catch (error) {
        Logger.warning('[ChatScreen] Failed to start ACP session: $error');
      }
      _scrollToBottom();
    });
  }

  /// Load user avatar from storage
  Future<void> _loadUserAvatar() async {
    final avatar = await UserConfigStorage.getUserAvatar();
    if (mounted) {
      setState(() {
        _userAvatarBase64 = avatar;
      });
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels > 0 && !_hasMarkedReadOnScroll) {
      _markMessagesAsRead();
      _hasMarkedReadOnScroll = true;
    }
  }

  void _markMessagesAsRead() {
    final wsService = _wsService;
    if (wsService == null) return;
    final session = wsService.activeSession;
    if (session != null && session.unreadCount > 0) {
      session.markAsRead();
      if (mounted) {
        setState(() {});
      }
    }
  }

  Widget _buildSlashCommandList(
    WebSocketService wsService,
    String text,
    bool isDarkMode,
  ) {
    if (!text.startsWith('/') || wsService.availableCommands.isEmpty) {
      return const SizedBox.shrink();
    }
    final query = text.substring(1).split(RegExp(r'\s')).first.toLowerCase();
    final matches = wsService.availableCommands
        .where((command) =>
            query.isEmpty || command.name.toLowerCase().contains(query))
        .take(6)
        .toList();
    if (matches.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      constraints: const BoxConstraints(maxHeight: 180),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF2E2E2E) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: isDarkMode ? Colors.grey[700]! : Colors.grey[300]!),
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final command in matches)
            ListTile(
              dense: true,
              title: Text('/${command.name}'),
              subtitle: command.description == null
                  ? null
                  : Text(command.description!,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () {
                _controller.value = TextEditingValue(
                  text: '/${command.name} ',
                  selection: TextSelection.collapsed(
                      offset: command.name.length + 2),
                );
              },
            ),
        ],
      ),
    );
  }

  /// Build message items with time dividers
  void _buildMessageItems() {
    _messageItems.clear();
    DateTime? lastTimestamp;

    for (final message in _messages) {
      if (lastTimestamp == null ||
          message.timestamp.difference(lastTimestamp).inMinutes > 5) {
        _messageItems.add(_MessageItem.timestamp(message.timestamp));
      }
      _messageItems.add(_MessageItem.message(message));
      lastTimestamp = message.timestamp;
    }
  }

  /// Build session info banner shown at top of chat
  Widget _buildSessionInfoBanner(bool isDarkMode, WebSocketService wsService) {
    final session = wsService.activeSession;
    if (session == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF191919) : const Color(0xFFF7F7F7),
        border: Border(
          bottom: BorderSide(
            color: isDarkMode ? Colors.grey[800]! : Colors.grey[200]!,
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // ACP Agent online status indicator
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: wsService.isConnected ? Colors.green : Colors.grey,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),

              // AI 正在生成回复状态 - 优先级高于 Agent badge
              if (_isGenerating)
                Flexible(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color:
                          isDarkMode ? Colors.orange[900] : Colors.orange[50],
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isDarkMode
                            ? Colors.orange[700]!
                            : Colors.orange[200]!,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: AnimatedTypingDots(),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '正在回复',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isDarkMode
                                ? Colors.orange[300]
                                : Colors.orange[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              // Agent badge - 当没有正在生成时显示
              else if (session.agentId != null)
                Flexible(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDarkMode ? Colors.blue[900] : Colors.blue[50],
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color:
                            isDarkMode ? Colors.blue[700]! : Colors.blue[200]!,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.smart_toy,
                          size: 14,
                          color:
                              isDarkMode ? Colors.blue[300] : Colors.blue[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          session.agentId!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isDarkMode
                                ? Colors.blue[300]
                                : Colors.blue[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(width: 8),

              // Message count
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDarkMode ? Colors.grey[800] : Colors.grey[100],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 12,
                        color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${session.messages.length}',
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              isDarkMode ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(),
              Text(
                _formatSessionTime(session.sessionKey),
                style: TextStyle(
                  fontSize: 11,
                  color: isDarkMode ? Colors.grey[500] : Colors.grey[400],
                ),
              ),
            ],
          ),
          if (wsService.configOptions.isNotEmpty ||
              wsService.availableModes.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildConfigOptionsBar(wsService, isDarkMode),
          ],
          if (wsService.todos.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...wsService.todos.take(5).map((todo) {
              final done = todo.status == 'completed';
              return Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '${done ? '✓' : '○'} ${todo.content}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    decoration: done ? TextDecoration.lineThrough : null,
                    color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildConfigOptionsBar(WebSocketService wsService, bool isDarkMode) {
    final options = wsService.configOptions.isNotEmpty
        ? wsService.configOptions
        : [
            AcpConfigOption(
              id: 'mode',
              name: 'Mode',
              category: 'mode',
              currentValue: wsService.currentModeId,
              options: wsService.availableModes
                  .map((mode) => AcpConfigOptionValue(
                        value: mode.id,
                        name: mode.name,
                        description: mode.description,
                      ))
                  .toList(),
            ),
          ];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return _buildConfigOptionControl(
              options[index], wsService, isDarkMode);
        },
      ),
    );
  }

  Widget _buildConfigOptionControl(
    AcpConfigOption option,
    WebSocketService wsService,
    bool isDarkMode,
  ) {
    if (option.isBoolean) {
      final on = option.currentValue == true || option.currentId == 'true';
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            option.name,
            style: TextStyle(
              fontSize: 11,
              color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
            ),
          ),
          Switch(
            value: on,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (value) => _changeConfigOption(wsService, option, value),
          ),
        ],
      );
    }

    if (option.isSelect && option.options.length <= 4) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final value in option.options)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ChoiceChip(
                label: Text(value.name, style: const TextStyle(fontSize: 11)),
                selected: option.currentId == value.value,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onSelected: (_) =>
                    _changeConfigOption(wsService, option, value.value),
              ),
            ),
        ],
      );
    }

    var label = option.currentId ?? option.name;
    for (final value in option.options) {
      if (value.value == option.currentId) {
        label = value.name;
        break;
      }
    }
    return PopupMenuButton<String>(
      tooltip: option.description ?? option.name,
      onSelected: (value) => _changeConfigOption(wsService, option, value),
      itemBuilder: (context) => [
        for (final value in option.options)
          PopupMenuItem(
            value: value.value,
            child: Text(value.name),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isDarkMode ? Colors.grey[700]! : Colors.grey[300]!,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${option.name}: $label',
              style: TextStyle(
                fontSize: 11,
                color: isDarkMode ? Colors.grey[200] : Colors.grey[800],
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeConfigOption(
    WebSocketService wsService,
    AcpConfigOption option,
    Object value,
  ) async {
    try {
      if (option.category == 'mode' &&
          option.id == 'mode' &&
          wsService.configOptions.isEmpty) {
        await wsService.setSessionMode(value.toString());
      } else {
        await wsService.setConfigOption(option.id, value);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法设置 ${option.name}：$error')),
      );
    }
  }

  /// Format session creation time
  String _formatSessionTime(String sessionKey) {
    try {
      final timestamp = int.parse(sessionKey.split('-').last);
      final createdAt = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final createdDay =
          DateTime(createdAt.year, createdAt.month, createdAt.day);

      if (createdDay == today) {
        return '今天 ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';
      } else if (createdDay == today.subtract(const Duration(days: 1))) {
        return '昨天 ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';
      } else {
        return '${createdAt.month}/${createdAt.day} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';
      }
    } catch (e) {
      return '';
    }
  }

  /// Format message time for divider
  String _formatMessageTime(DateTime time) {
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

  /// Build time divider widget
  Widget _buildTimeDivider(DateTime time, bool isDarkMode) {
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
          _formatMessageTime(time),
          style: TextStyle(
            fontSize: 12,
            color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
      ),
    );
  }

  /// Sync local _messages from SessionState (single source of truth)
  void _syncMessagesFromSession() {
    final wsService = _wsService;
    if (wsService == null) return;
    final session = wsService.activeSession;
    if (session != null) {
      // 使用 sync 模式复制列表，避免竞态条件
      _messages.clear();
      _messages.addAll(session.messages);
    } else {
      _messages.clear();
    }
    _buildMessageItems();
  }

  void _requestMessageSync({bool scroll = false}) {
    if (scroll) _pendingScroll = true;
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) return;
      setState(() => _syncMessagesFromSession());
      if (_pendingScroll) {
        _pendingScroll = false;
        _scrollToBottom();
      }
    });
  }

  /// Load saved messages for a session
  Future<void> _loadSessionMessages(String sessionKey) async {
    if (!mounted) return;

    try {
      final wsService = _wsService;
      if (wsService == null) return;
      final connectionManager =
          Provider.of<ConnectionManager>(context, listen: false);
      final sessionState = wsService.getSession(sessionKey);

      // If session has in-memory messages, sync from there
      if (sessionState != null && sessionState.messages.isNotEmpty) {
        if (mounted) {
          setState(() {
            _syncMessagesFromSession();
          });
          _scrollToBottom();
        }
        return; // in-memory data is authoritative
      }

      // Fallback: load from local storage
      final session = await connectionManager.loadSavedSession(sessionKey);
      // Step 3 fix: guard against race condition after await
      if (wsService.currentSessionKey != sessionKey) return;

      if (session != null && session.messages.isNotEmpty) {
        // Populate session state from storage (don't call selectSession to avoid loop)
        final state = wsService.getSession(sessionKey);
        if (state != null) {
          for (final msg in session.messages) {
            if (!state.messages.any((m) => m.id == msg.id)) {
              state.messages.add(msg);
            }
          }
          state.agentId = session.agentId;
        }
        if (mounted) {
          setState(() {
            _syncMessagesFromSession();
          });
          _scrollToBottom();
        }
      } else {
        if (mounted) {
          setState(() {
            _syncMessagesFromSession();
          });
        }
      }
    } catch (e) {
      Logger.warning('[ChatScreen] Failed to load session messages: $e');
    }
  }

  /// Scroll to bottom - 跳转到列表末尾显示最新消息
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        // 使用延迟滚动确保内容已完全渲染
        Future.delayed(const Duration(milliseconds: 50), () {
          if (_scrollController.hasClients) {
            _scrollController
                .jumpTo(_scrollController.position.maxScrollExtent);
          }
        });
      }
    });
  }

  void _listenToMessages() {
    final wsService = _wsService;
    if (wsService == null) return;

    // Step 3 fix: only reload when session actually changes
    _wsListener = () {
      if (!mounted) return;
      final newKey = wsService.currentSessionKey;
      if (newKey != null && newKey != _currentLoadedSessionKey) {
        _currentLoadedSessionKey = newKey;
        _hasMarkedReadOnScroll = false;
        _loadSessionMessages(newKey);
      } else if (newKey == _currentLoadedSessionKey) {
        if (_isGenerating) return;
        _requestMessageSync();
      }
    };
    wsService.addListener(_wsListener!);

    // Load current session immediately if exists
    if (wsService.currentSessionKey != null) {
      _currentLoadedSessionKey = wsService.currentSessionKey;
      _loadSessionMessages(wsService.currentSessionKey!);
    }

    // Step 2 fix: stream listeners just trigger sync, no manual add
    _messageSub = wsService.messages.listen((msg) {
      if (mounted) {
        _hasMarkedReadOnScroll = false;
        if (!msg.isUser && msg.isStreaming && !_isGenerating) {
          setState(() => _isGenerating = true);
        }
        _requestMessageSync(scroll: true);
      }
    });

    _messageUpdateSub = wsService.messageUpdates.listen((msg) {
      if (!mounted) return;
      if (msg.isStreaming) {
        if (!_isGenerating) setState(() => _isGenerating = true);
        return;
      }
      _requestMessageSync();
    });

    _eventSub = wsService.events.listen((event) {
      if (event['result'] is Map &&
          (event['result'] as Map).containsKey('stopReason')) {
        if (mounted && (_isTyping || _isGenerating)) {
          setState(() {
            _isTyping = false;
            _isGenerating = false;
          });
        }
      }
    });
  }

  void _listenForClientRequests() {
    final wsService = _wsService;
    if (wsService == null) return;
    _clientRequestSub = wsService.clientRequests.listen(_onClientRequest);
    final pending = wsService.pendingClientRequest;
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _onClientRequest(pending);
      });
    }
  }

  Future<void> _onClientRequest(Map<String, dynamic> request) async {
    if (!mounted) return;
    final method = request['method'] as String?;
    if (method == 'cursor/ask_question') {
      await _showAskQuestionDialog(request);
    } else if (method == 'cursor/create_plan') {
      await _showCreatePlanDialog(request);
    }
  }

  Future<void> _showAskQuestionDialog(Map<String, dynamic> request) async {
    final wsService = _wsService;
    if (wsService == null) return;
    final params = request['params'] as Map<String, dynamic>? ?? const {};
    final questions = (params['questions'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    if (questions.isEmpty) {
      wsService.respondToAgentRequest(request['id'], {
        'outcome': {'outcome': 'skipped'},
      });
      return;
    }

    final answers = <String, List<String>>{};
    for (final question in questions) {
      final id = question['id'] as String? ?? '';
      final options = (question['options'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      final allowMultiple = question['allowMultiple'] == true;
      if (!mounted) return;
      final selected = await showDialog<List<String>>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          var current = <String>{};
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: Text(
                  params['title'] as String? ??
                      question['prompt'] as String? ??
                      '需要你的选择',
                ),
                content: SizedBox(
                  width: 360,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (params['title'] != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(question['prompt'] as String? ?? ''),
                          ),
                        for (final option in options)
                          ListTile(
                            dense: true,
                            title: Text(option['label'] as String? ?? ''),
                            leading: allowMultiple
                                ? Checkbox(
                                    value: current.contains(option['id']),
                                    onChanged: (checked) {
                                      setDialogState(() {
                                        if (checked == true) {
                                          current.add(option['id'] as String);
                                        } else {
                                          current.remove(option['id']);
                                        }
                                      });
                                    },
                                  )
                                : Icon(
                                    current.contains(option['id'])
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_off,
                                  ),
                            onTap: () {
                              setDialogState(() {
                                final id = option['id'] as String? ?? '';
                                if (allowMultiple) {
                                  if (current.contains(id)) {
                                    current.remove(id);
                                  } else {
                                    current.add(id);
                                  }
                                } else {
                                  current = {id};
                                }
                              });
                            },
                          ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, <String>[]),
                    child: const Text('跳过'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, current.toList()),
                    child: const Text('确定'),
                  ),
                ],
              );
            },
          );
        },
      );
      if (selected == null || selected.isEmpty) {
        wsService.respondToAgentRequest(request['id'], {
          'outcome': {'outcome': 'skipped'},
        });
        return;
      }
      answers[id] = selected;
    }

    wsService.respondToAgentRequest(request['id'], {
      'outcome': {
        'outcome': 'answered',
        'answers': answers.entries
            .map((entry) => {
                  'questionId': entry.key,
                  'selectedOptionIds': entry.value,
                })
            .toList(),
      },
    });
  }

  Future<void> _showCreatePlanDialog(Map<String, dynamic> request) async {
    final wsService = _wsService;
    if (wsService == null) return;
    final params = request['params'] as Map<String, dynamic>? ?? const {};
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Text(params['name'] as String? ?? '确认计划'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Text(
                [
                  if ((params['overview'] as String?)?.isNotEmpty == true)
                    params['overview'],
                  params['plan'] ?? '',
                ].whereType<String>().join('\n\n'),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('拒绝'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('接受'),
            ),
          ],
        );
      },
    );
    wsService.respondToAgentRequest(request['id'], {
      'outcome': {
        'outcome': accepted == true ? 'accepted' : 'rejected',
      },
    });
  }

  @override
  Widget build(BuildContext context) {
    final connectionManager = context.watch<ConnectionManager>();
    final wsService = connectionManager.wsService;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    // 气泡最大宽度：屏幕宽度减去两个头像、边距及气泡间隔的距离
    // 头像 margin 8 + 宽度 40 + margin 8 = 56
    // 气泡与头像间隔：8
    // 总共占用 128 (56 + 8 + 56 = 120，额外考虑 SafeArea 等)
    final maxWidth = MediaQuery.of(context).size.width - 128;

    return Scaffold(
      appBar: AppBar(
        backgroundColor:
            isDarkMode ? const Color(0xFF191919) : const Color(0xFFEDEDED),
        elevation: isDarkMode ? 0 : 0.5,
        title: Center(
          child: Text(
            wsService.activeSession?.customTitle?.isNotEmpty == true
                ? wsService.activeSession!.customTitle!
                : 'PocketBot',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w500,
              color: isDarkMode ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Session info banner
          _buildSessionInfoBanner(isDarkMode, wsService),

          // Connection status banner - WeChat style
          if (!connectionManager.wsService.isConnected &&
              !connectionManager.wsService.isReconnecting)
            Container(
              color: const Color(0xFFFA9D3B),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '连接已断开，请重新连接 Agent',
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      if (connectionManager.gateway != null) {
                        connectionManager.connectTo(connectionManager.gateway!);
                      }
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                    ),
                    child: const Text('重连'),
                  ),
                ],
              ),
            ),

          // Auto-reconnect countdown banner
          if (connectionManager.wsService.isReconnecting)
            Container(
              color: const Color(0xFF2196F3),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.sync, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '自动重连中 ${connectionManager.wsService.reconnectCountdown} 秒...',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

          // Messages with WeChat-style background
          Expanded(
            child: Container(
              color: isDarkMode
                  ? const Color(0xFF191919)
                  : const Color(0xFFF5F5F5),
              child: _messages.isEmpty
                  ? _buildEmptyState(isDarkMode)
                  : GestureDetector(
                      onTap: () => FocusScope.of(context).unfocus(),
                      child: ListView.builder(
                        key: PageStorageKey<String>(
                            wsService.currentSessionKey ?? 'default'),
                        controller: _scrollController,
                        reverse: false, // 最新消息显示在最下方
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        itemCount: _messageItems.length,
                        shrinkWrap: false,
                        // 添加缓存区域，减少滚动时的重建
                        cacheExtent: 200,
                        physics: const AlwaysScrollableScrollPhysics(),
                        // 使用 itemExtent 避免每次测量高度
                        itemExtent: null,
                        itemBuilder: (context, index) {
                          final item = _messageItems[index];
                          if (item.isTimestamp && item.timestamp != null) {
                            return _buildTimeDivider(
                                item.timestamp!, isDarkMode);
                          }
                          if (item.isMessage && item.message != null) {
                            // 使用 RepaintBoundary 隔离重绘
                            return RepaintBoundary(
                              child: _buildMessageBubble(
                                  item.message!, isDarkMode),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
            ),
          ),

          // Typing indicator - WeChat style with avatar and adaptive bubble
          if (_isTyping)
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(width: 8),
                _buildAvatar(false, isDarkMode),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: IntrinsicHeight(
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color:
                            isDarkMode ? const Color(0xFF2E2E2E) : Colors.white,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(6),
                          topRight: Radius.circular(6),
                          bottomRight: Radius.circular(6),
                          bottomLeft: Radius.circular(2),
                        ),
                        border: Border.all(
                            color: isDarkMode
                                ? Colors.grey[700]!
                                : Colors.grey[300]!),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildTypingDots(isDarkMode),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 50),
              ],
            ),

          // Input area - WeChat style bottom input bar
          Container(
            color:
                isDarkMode ? const Color(0xFF191919) : const Color(0xFFF7F7F7),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _controller,
                    builder: (context, value, child) {
                      return _buildSlashCommandList(
                        wsService,
                        value.text,
                        isDarkMode,
                      );
                    },
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Container(
                          constraints: const BoxConstraints(maxHeight: 100),
                          decoration: BoxDecoration(
                            color: isDarkMode
                                ? const Color(0xFF2E2E2E)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: isDarkMode
                                    ? Colors.grey[700]!
                                    : Colors.grey[300]!),
                          ),
                          child: Shortcuts(
                            shortcuts: {
                              LogicalKeySet(LogicalKeyboardKey.enter):
                                  _SendIntent(),
                              LogicalKeySet(LogicalKeyboardKey.control,
                                  LogicalKeyboardKey.enter): _NewLineIntent(),
                              LogicalKeySet(LogicalKeyboardKey.shift,
                                  LogicalKeyboardKey.enter): _NewLineIntent(),
                            },
                            child: Actions(
                              actions: {
                                _SendIntent: _SendAction(_sendMessage),
                                _NewLineIntent: _NewLineAction(_controller),
                              },
                              child: TextField(
                                controller: _controller,
                                decoration: InputDecoration(
                                  hintText: wsService.availableCommands.isEmpty
                                      ? ''
                                      : '输入 / 查看命令',
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  isDense: true,
                                  hintStyle: TextStyle(
                                      color: isDarkMode
                                          ? Colors.grey[600]
                                          : Colors.grey[400]),
                                ),
                                maxLines: null,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: isDarkMode
                                      ? Colors.white
                                      : Colors.black87,
                                ),
                                onSubmitted: (_) => _sendMessage(),
                                keyboardType: TextInputType.multiline,
                                textInputAction: TextInputAction.send,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      if (_isGenerating)
                        IconButton(
                          onPressed: () {
                            wsService.cancelPrompt();
                            setState(() => _isGenerating = false);
                          },
                          tooltip: '停止',
                          icon: const Icon(Icons.stop, size: 22),
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFFFA5151),
                            foregroundColor: Colors.white,
                          ),
                          constraints: const BoxConstraints.tightFor(
                              width: 36, height: 36),
                        )
                      else
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _controller,
                          builder: (context, value, child) {
                            final canSend = value.text.trim().isNotEmpty;
                            return IconButton(
                              onPressed: canSend ? _sendMessage : null,
                              tooltip: '发送',
                              icon: const Icon(Icons.send, size: 22),
                              style: IconButton.styleFrom(
                                backgroundColor: canSend
                                    ? const Color(0xFF07C160)
                                    : Colors.transparent,
                                foregroundColor: canSend
                                    ? Colors.white
                                    : isDarkMode
                                        ? Colors.grey[400]
                                        : Colors.grey[600],
                                side: BorderSide(
                                  color: canSend
                                      ? Colors.transparent
                                      : (isDarkMode
                                          ? Colors.grey[700]!
                                          : Colors.grey[400]!),
                                  width: 1,
                                ),
                              ),
                              constraints: const BoxConstraints.tightFor(
                                  width: 36, height: 36),
                            );
                          },
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
                Icons.chat_bubble_outline,
                size: 60,
                color: isDarkMode ? Colors.grey[600] : Colors.grey[400],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '开始对话',
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

  Widget _buildMessageBubble(Message message, bool isDarkMode) {
    if (message.kind == MessageKind.system) {
      return _buildSystemBubble(message, isDarkMode);
    }
    if (message.kind == MessageKind.thought) {
      return _buildThoughtBubble(message, isDarkMode);
    }
    if (message.kind == MessageKind.tool || message.kind == MessageKind.plan) {
      return _buildToolBubble(message, isDarkMode);
    }

    final isUser = message.isUser;
    // 气泡最大宽度：屏幕宽度减去两个头像、边距及气泡间隔的距离
    // 头像 margin 8 + 宽度 40 + margin 8 = 56
    // 气泡与头像间隔：8
    // 总共占用 128 (56 + 8 + 56 = 120，额外考虑 SafeArea 等)
    final maxWidth = MediaQuery.of(context).size.width - 128;

    // 用户消息：气泡在上，状态图标在气泡下方左侧
    if (isUser) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDarkMode
                          ? const Color(0xFF3EB575)
                          : const Color(0xFF95EC69),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(6),
                        topRight: const Radius.circular(6),
                        bottomLeft: const Radius.circular(6),
                        bottomRight: Radius.circular(2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (message.attachments.isNotEmpty)
                          AttachmentRow(
                            attachments: message.attachments,
                            isUser: isUser,
                            isDarkMode: isDarkMode,
                          ),
                        Flexible(
                          child: MarkdownMessageView(
                            content: message.text,
                            isDarkMode: isDarkMode,
                            isUser: isUser,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _buildAvatar(isUser, isDarkMode),
              ],
            ),
            // 状态图标在气泡下方左侧
            _buildMessageStatus(message, isDarkMode),
          ],
        ),
      );
    }

    // AI 消息：保持原来的 Row 布局
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAvatar(isUser, isDarkMode),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF262626) : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(6),
                  topRight: const Radius.circular(6),
                  bottomLeft: Radius.circular(2),
                  bottomRight: Radius.circular(6),
                ),
                border: Border.all(
                    color: isDarkMode ? Colors.grey[700]! : Colors.grey[300]!),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.attachments.isNotEmpty)
                    AttachmentRow(
                      attachments: message.attachments,
                      isUser: isUser,
                      isDarkMode: isDarkMode,
                    ),
                  Flexible(
                    child: message.isStreaming
                        ? _buildLivePlainText(message, isDarkMode)
                        : MarkdownMessageView(
                            content: message.text,
                            isDarkMode: isDarkMode,
                            isUser: isUser,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemBubble(Message message, bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 6),
      child: Text(
        message.text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          color: isDarkMode ? Colors.grey[500] : Colors.grey[600],
        ),
      ),
    );
  }

  Widget _buildLivePlainText(Message message, bool isDarkMode, {TextStyle? style}) {
    final resolved = style ??
        TextStyle(
          fontSize: 16,
          height: 1.5,
          color: isDarkMode ? Colors.white : Colors.black87,
        );
    final wsService = _wsService;
    if (wsService == null || !message.isStreaming) {
      return Text(message.text, style: resolved);
    }
    return ValueListenableBuilder<int>(
      valueListenable: wsService.streamingTick,
      builder: (_, __, ___) {
        return Text(
          wsService.streamingTextFor(message.id) ?? message.text,
          style: resolved,
        );
      },
    );
  }

  Widget _buildThoughtBubble(Message message, bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(56, 2, 72, 2),
      child: _buildLivePlainText(
        message,
        isDarkMode,
        style: TextStyle(
          fontSize: 12,
          fontStyle: FontStyle.italic,
          color: isDarkMode ? Colors.grey[500] : Colors.grey[600],
        ),
      ),
    );
  }

  Widget _buildToolBubble(Message message, bool isDarkMode) {
    final status = message.toolStatus ?? '';
    final color = status == 'failed'
        ? Colors.red
        : status == 'completed'
            ? Colors.green
            : Colors.orange;
    final icon = message.kind == MessageKind.plan
        ? Icons.checklist
        : Icons.build_outlined;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 48, 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF232323) : const Color(0xFFF0F0F0),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDarkMode ? Colors.grey[800]! : Colors.grey[300]!,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: _buildLivePlainText(
                message,
                isDarkMode,
                style: TextStyle(
                  fontSize: 13,
                  color: isDarkMode ? Colors.grey[300] : Colors.grey[800],
                ),
              ),
            ),
            if (status.isNotEmpty)
              Text(
                status,
                style: TextStyle(fontSize: 11, color: color),
              ),
          ],
        ),
      ),
    );
  }

  /// Build message delivery status indicator
  Widget _buildMessageStatus(Message message, bool isDarkMode) {
    if (!message.isUser) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 2, right: 48),
      child: SizedBox(
        width: 16,
        height: 16,
        child: Icon(
          Icons.done,
          size: 14,
          color: message.confirmed
              ? Colors.green
              : (isDarkMode ? Colors.grey[500] : Colors.grey[400]),
        ),
      ),
    );
  }

  Widget _buildAvatar(bool isUser, bool isDarkMode) {
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
      child: _userAvatarBase64 != null && isUser
          ? ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.memory(
                base64Decode(_userAvatarBase64!),
                fit: BoxFit.cover,
                width: 40,
                height: 40,
                errorBuilder: (context, error, stackTrace) {
                  Logger.warning('[ChatScreen] Failed to load avatar: $error');
                  return Icon(
                    Icons.person,
                    color: isUser
                        ? (isDarkMode ? Colors.grey[300] : Colors.grey[600])
                        : (isDarkMode ? Colors.blue[300] : Colors.blue[400]),
                    size: 24,
                  );
                },
              ),
            )
          : Icon(
              isUser ? Icons.person : Icons.smart_toy,
              color: isUser
                  ? (isDarkMode ? Colors.grey[300] : Colors.grey[600])
                  : (isDarkMode ? Colors.blue[300] : Colors.blue[400]),
              size: 24,
            ),
    );
  }

  /// Typing animation widget
  Widget _buildTypingDots(bool isDarkMode) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Dot(index: 0, isDarkMode: isDarkMode),
        _Dot(index: 1, isDarkMode: isDarkMode),
        _Dot(index: 2, isDarkMode: isDarkMode),
      ],
    );
  }

  void _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    Logger.info('[UI] _sendMessage called: "$text"');
    Logger.info('[UI] wsService: $_wsService');

    // Clear input first (before sending)
    _controller.clear();

    // Clear typing indicator when user sends message
    if (mounted) {
      setState(() => _isTyping = false);
    }

    // Step 2 fix: only send via wsService, SessionState handles message storage
    try {
      final wsService = _wsService;
      if (wsService == null) {
        Logger.error('[UI] wsService is null!');
        if (mounted) {
          _controller.text = text;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('发送失败：未连接到 Agent')),
          );
        }
        return;
      }
      Logger.info('[UI] Calling wsService.sendMessage...');
      if (mounted) setState(() => _isGenerating = true);
      await wsService.sendMessage(text);
      Logger.info('[UI] wsService.sendMessage completed');
      // Sync UI immediately after sending
      if (mounted) {
        setState(() {
          _syncMessagesFromSession();
        });
        _scrollToBottom();
      }
    } catch (e) {
      Logger.error('[UI] Failed to send message: $e');
      if (mounted) {
        _controller.text = text;
        setState(() => _isGenerating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送失败：$e')),
        );
      }
    }
  }

  // Step 2 fix: _saveCurrentSession removed - SessionState._saveToStorage() handles persistence

  @override
  void dispose() {
    // Save scroll position before disposing - cache provider before any cleanup
    ConnectionManager? connectionManager;
    try {
      connectionManager =
          Provider.of<ConnectionManager>(context, listen: false);
    } catch (e) {
      // Context may be invalid, skip saving scroll position
      connectionManager = null;
    }

    if (connectionManager != null) {
      final wsService = connectionManager.wsService;
      final activeSession = wsService.activeSession;
      if (activeSession != null && _scrollController.hasClients) {
        activeSession.scrollOffset = _scrollController.position.pixels;
        SessionStorage.saveSession(activeSession.toChatSession());
        unawaited(SessionStorage.flush());
      }
    }

    // Step 1 fix: clean up all listener/subscription refs
    if (connectionManager != null) {
      final wsService = connectionManager.wsService;
      if (_wsListener != null) wsService.removeListener(_wsListener!);
    }
    _messageSub?.cancel();
    _messageUpdateSub?.cancel();
    _eventSub?.cancel();
    _clientRequestSub?.cancel();
    _userConfigSub?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

/// Typing animation dot widget
class _Dot extends StatefulWidget {
  final int index;
  final bool isDarkMode;

  const _Dot({required this.index, required this.isDarkMode});

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    // Stagger the animation start based on index
    Future.delayed(Duration(milliseconds: widget.index * 150), () {
      if (mounted && !_isDisposed) {
        _controller.repeat();
      }
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller.drive(
        Tween<double>(begin: 0.3, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 1.5),
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: widget.isDarkMode ? Colors.grey[400] : const Color(0xFF8C8C8C),
          borderRadius: const BorderRadius.all(Radius.circular(3)),
        ),
      ),
    );
  }
}

/// Animated typing dots indicator - three blinking dots animation
class AnimatedTypingDots extends StatefulWidget {
  const AnimatedTypingDots({super.key});

  @override
  State<AnimatedTypingDots> createState() => _AnimatedTypingDotsState();
}

class _AnimatedTypingDotsState extends State<AnimatedTypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: FadeTransition(
            opacity: Tween<double>(begin: 0.3, end: 1.0).animate(
              CurvedAnimation(
                parent: _controller,
                curve: Interval(
                  index * 0.2,
                  (index + 1) * 0.2,
                  curve: Curves.easeInOut,
                ),
              ),
            ),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.orange[300]
                    : Colors.orange[700],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// Single typing dot with fade animation (used in input field)
class _TypingDot extends StatefulWidget {
  final bool isDarkMode;
  final int index;

  const _TypingDot({required this.isDarkMode, required this.index});

  @override
  State<_TypingDot> createState() => __TypingDotState();
}

class __TypingDotState extends State<_TypingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    )..repeat();
    Future.delayed(Duration(milliseconds: widget.index * 150), () {
      if (mounted) _controller.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller.drive(
        Tween<double>(begin: 0.3, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 1.5),
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: widget.isDarkMode ? Colors.grey[400] : const Color(0xFF8C8C8C),
          borderRadius: const BorderRadius.all(Radius.circular(3)),
        ),
      ),
    );
  }
}
