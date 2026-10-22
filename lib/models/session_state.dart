import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:pocket_bot/config/session_storage.dart';
import 'package:pocket_bot/models/message.dart';
import 'package:pocket_bot/utils/logger.dart';

String _formatTokenCount(int value) {
  if (value < 1000) return value.toString();
  final scaled = value / 1000;
  return '${scaled.toStringAsFixed(value % 1000 == 0 ? 0 : 1)}k';
}

class SessionState with ChangeNotifier {
  final String sessionKey;
  String? agentId;
  String? currentRunId;
  List<Message> messages;
  DateTime lastUpdated;
  bool isActive;
  int unreadCount;
  bool isGatewaySession;
  String? sourceGatewayHost;
  String? workingDirectory;
  List<String> additionalDirectories = const [];
  double? scrollOffset;
  String? customTitle; // User-defined title that persists
  String? agentTitle; // Agent-provided title, replaceable
  String? model; // Model name from Gateway

  // Token usage reported by the agent (ACP usage_update or Gateway sync).
  int inputTokens = 0;
  int outputTokens = 0;
  int totalTokens = 0;
  int contextTokens = 0;
  double? costAmount;
  String? costCurrency;

  /// False for sessions that back a group chat member; they are stored with
  /// the group's messages instead of the chat list.
  bool persist = true;

  /// Get the display title for this session (public getter)
  /// 优先返回自定义标题，如果没有则根据消息生成
  String get displayTitle {
    if (customTitle != null && customTitle!.isNotEmpty) {
      return customTitle!;
    }
    if (agentTitle != null && agentTitle!.isNotEmpty) {
      return agentTitle!;
    }

    if (messages.isEmpty) {
      return '新对话';
    }
    Message? lastUserMessage;
    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i].isUser) {
        lastUserMessage = messages[i];
        break;
      }
    }
    if (lastUserMessage == null) {
      return '新对话';
    }
    final preview = lastUserMessage.text;
    if (preview.length > 30) {
      return preview.substring(0, 30) + '...';
    }
    return preview;
  }

  final StreamController<Message> _messageController =
      StreamController<Message>.broadcast();
  final StreamController<Message> _messageUpdateController =
      StreamController<Message>.broadcast();

  Stream<Message> get messageStream => _messageController.stream;
  Stream<Message> get messageUpdateStream => _messageUpdateController.stream;

  SessionState({
    required this.sessionKey,
    this.agentId,
    this.currentRunId,
    List<Message>? messages,
    DateTime? lastUpdated,
    this.isActive = false,
    this.unreadCount = 0,
    this.isGatewaySession = false,
    this.sourceGatewayHost,
    this.workingDirectory,
    this.additionalDirectories = const [],
    this.scrollOffset,
    this.customTitle,
    this.agentTitle,
    this.model,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.totalTokens = 0,
    this.contextTokens = 0,
    this.costAmount,
    this.costCurrency,
  })  : messages = messages ?? [],
        lastUpdated = lastUpdated ?? DateTime.now();

  void activate() {
    isActive = true;
    unreadCount = 0;
    notifyListeners();
  }

  void deactivate() {
    isActive = false;
    notifyListeners();
  }

  void markAsRead() {
    unreadCount = 0;
    notifyListeners();
  }

  void addMessage(Message message) {
    Logger.debug(
        '[Session] addMessage: ${message.id}, isUser: ${message.isUser}');
    if (messages.any((m) => m.id == message.id)) {
      Logger.warning('[SessionState] 尝试添加重复消息 ID: ${message.id}');
      return;
    }
    messages.add(message);
    lastUpdated = DateTime.now();

    // Only increase unread count if session is not active
    if (!message.isUser && !isActive) {
      unreadCount++;
    }
    // Persist settled bubbles only. Streaming tokens would rewrite the whole
    // session list to FlutterSecureStorage many times per second.
    if (!message.isStreaming) {
      _saveToStorage();
    }

    _messageController.add(message);
    notifyListeners();
  }

  void updateLastMessage(Message message) {
    updateMessage(message);
  }

  /// 更新任意消息（用于已读确认等功能）
  void updateMessage(Message message) {
    final index = messages.indexWhere((m) => m.id == message.id);
    if (index >= 0) {
      messages[index] = message;
      lastUpdated = DateTime.now();
      _messageUpdateController.add(message);
      notifyListeners();
      // Streaming tokens arrive many times per second. Persist only when the
      // bubble settles so ACP I/O does not block the UI isolate.
      if (!message.isStreaming) {
        _saveToStorage();
      }
    }
  }

  /// Apply stream text without notifying the chat list or hitting storage.
  void patchStreamingMessage(Message message) {
    final index = messages.indexWhere((m) => m.id == message.id);
    if (index >= 0) {
      messages[index] = message;
      lastUpdated = DateTime.now();
    }
  }

  void clearMessages() {
    messages.clear();
    unreadCount = 0;
    currentRunId = null;
    notifyListeners();
  }

  void disposeStreams() {
    _messageController.close();
    _messageUpdateController.close();
  }

  ChatSession toChatSession() {
    return ChatSession(
      id: sessionKey,
      key: sessionKey,
      title: displayTitle,
      createdAt: lastUpdated,
      lastUpdated: lastUpdated,
      messages: List.from(messages),
      agentId: agentId,
      unreadCount: unreadCount,
      isGatewaySession: isGatewaySession,
      lastMessagePreview: messages.isNotEmpty ? messages.last.text : null,
      sourceGatewayHost: sourceGatewayHost,
      workingDirectory: workingDirectory,
      additionalDirectories: additionalDirectories,
      scrollOffset: scrollOffset,
      customTitle: customTitle,
      agentTitle: agentTitle,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      totalTokens: totalTokens,
      contextTokens: contextTokens,
      costAmount: costAmount,
      costCurrency: costCurrency,
      model: model,
    );
  }

  /// Compact context usage for the session banner, e.g. `2.7k / 200k`.
  String? get tokenUsageLabel {
    if (totalTokens <= 0 || contextTokens <= 0) return null;
    return '${_formatTokenCount(totalTokens)} / '
        '${_formatTokenCount(contextTokens)}';
  }

  /// Cumulative session cost, e.g. `USD 0.12`.
  String? get costLabel {
    final amount = costAmount;
    final currency = costCurrency;
    if (amount == null || amount <= 0 || currency == null || currency.isEmpty) {
      return null;
    }
    return '$currency ${amount.toStringAsFixed(2)}';
  }

  /// Combined context/cost label for the chat header.
  String? get contextUsageLabel {
    final tokens = tokenUsageLabel;
    final cost = costLabel;
    if (tokens == null) return cost;
    if (cost == null) return tokens;
    return '$tokens · $cost';
  }

  Future<void> _saveToStorage() async {
    if (!persist) return;
    try {
      Logger.debug(
          '[Session] Saving to storage: ${sessionKey}, ${messages.length} messages');
      await SessionStorage.saveSession(toChatSession());
      Logger.debug('[Session] Save complete');
    } catch (e) {
      Logger.warning('[Session] Failed to save session: $e');
    }
  }

  /// Set a custom title for this session
  void setCustomTitle(String title) {
    customTitle = title;
    notifyListeners();
    _saveToStorage();
  }

  factory SessionState.fromChatSession(ChatSession session) {
    return SessionState(
      sessionKey: session.key,
      agentId: session.agentId,
      messages: List.from(session.messages),
      lastUpdated: session.lastUpdated,
      unreadCount: session.unreadCount,
      isGatewaySession: session.isGatewaySession,
      sourceGatewayHost: session.sourceGatewayHost,
      workingDirectory: session.workingDirectory,
      additionalDirectories: session.additionalDirectories,
      scrollOffset: session.scrollOffset,
      customTitle: session.customTitle,
      agentTitle: session.agentTitle,
      model: session.model,
      inputTokens: session.inputTokens,
      outputTokens: session.outputTokens,
      totalTokens: session.totalTokens,
      contextTokens: session.contextTokens,
      costAmount: session.costAmount,
      costCurrency: session.costCurrency,
    );
  }
}
