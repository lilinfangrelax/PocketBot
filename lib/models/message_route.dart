import 'package:pocket_bot/models/at_parse_result.dart';

/// 消息路由类型
enum MessageRouteType {
  /// 普通消息（无需路由）
  normal,

  /// 路由到 AI 联系人
  aiContact,

  /// 路由到群聊
  groupChat,

  /// 路由到私聊
  privateChat,

  /// 广播消息
  broadcast,
}

/// 消息路由模型
class MessageRoute {
  /// 路由 ID
  final String id;

  /// 路由类型
  final MessageRouteType routeType;

  /// 目标联系人 ID（AI 联系人）
  final String? targetContactId;

  /// 目标群 ID
  final String? targetGroupId;

  /// Target ACP session ID.
  final String? sessionKey;

  /// 原始消息
  final String originalMessage;

  /// 解析后的消息内容
  final String processedMessage;

  /// @ 解析结果
  final AtParseResult? atResult;

  /// 是否需要 AI 处理
  final bool needsAI;

  /// 是否需要自动回复
  final bool needsAutoReply;

  /// 匹配的关键词
  final List<String>? matchedKeywords;

  /// 路由时间
  final DateTime timestamp;

  MessageRoute({
    required this.id,
    required this.routeType,
    this.targetContactId,
    this.targetGroupId,
    this.sessionKey,
    required this.originalMessage,
    required this.processedMessage,
    this.atResult,
    this.needsAI = false,
    this.needsAutoReply = false,
    this.matchedKeywords,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory MessageRoute.normal({
    required String originalMessage,
    required String processedMessage,
  }) {
    return MessageRoute(
      id: 'route_${DateTime.now().millisecondsSinceEpoch}',
      routeType: MessageRouteType.normal,
      originalMessage: originalMessage,
      processedMessage: processedMessage,
    );
  }

  factory MessageRoute.toAIContact({
    required String contactId,
    required String sessionKey,
    required String originalMessage,
    required String processedMessage,
    AtParseResult? atResult,
    List<String>? matchedKeywords,
  }) {
    return MessageRoute(
      id: 'route_${DateTime.now().millisecondsSinceEpoch}',
      routeType: MessageRouteType.aiContact,
      targetContactId: contactId,
      sessionKey: sessionKey,
      originalMessage: originalMessage,
      processedMessage: processedMessage,
      atResult: atResult,
      needsAI: true,
      matchedKeywords: matchedKeywords,
    );
  }

  factory MessageRoute.toGroup({
    required String groupId,
    required String originalMessage,
    required String processedMessage,
  }) {
    return MessageRoute(
      id: 'route_${DateTime.now().millisecondsSinceEpoch}',
      routeType: MessageRouteType.groupChat,
      targetGroupId: groupId,
      originalMessage: originalMessage,
      processedMessage: processedMessage,
    );
  }

  MessageRoute copyWith({
    String? id,
    MessageRouteType? routeType,
    String? targetContactId,
    String? targetGroupId,
    String? sessionKey,
    String? originalMessage,
    String? processedMessage,
    AtParseResult? atResult,
    bool? needsAI,
    bool? needsAutoReply,
    List<String>? matchedKeywords,
    DateTime? timestamp,
  }) {
    return MessageRoute(
      id: id ?? this.id,
      routeType: routeType ?? this.routeType,
      targetContactId: targetContactId ?? this.targetContactId,
      targetGroupId: targetGroupId ?? this.targetGroupId,
      sessionKey: sessionKey ?? this.sessionKey,
      originalMessage: originalMessage ?? this.originalMessage,
      processedMessage: processedMessage ?? this.processedMessage,
      atResult: atResult ?? this.atResult,
      needsAI: needsAI ?? this.needsAI,
      needsAutoReply: needsAutoReply ?? this.needsAutoReply,
      matchedKeywords: matchedKeywords ?? this.matchedKeywords,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'routeType': routeType.name,
      'targetContactId': targetContactId,
      'targetGroupId': targetGroupId,
      'sessionKey': sessionKey,
      'originalMessage': originalMessage,
      'processedMessage': processedMessage,
      'atResult': atResult?.toJson(),
      'needsAI': needsAI,
      'needsAutoReply': needsAutoReply,
      'matchedKeywords': matchedKeywords,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory MessageRoute.fromJson(Map<String, dynamic> json) {
    return MessageRoute(
      id: json['id'] ?? '',
      routeType: MessageRouteType.values.firstWhere(
        (e) => e.name == json['routeType'],
        orElse: () => MessageRouteType.normal,
      ),
      targetContactId: json['targetContactId'],
      targetGroupId: json['targetGroupId'],
      sessionKey: json['sessionKey'],
      originalMessage: json['originalMessage'] ?? '',
      processedMessage: json['processedMessage'] ?? '',
      atResult: json['atResult'] != null
          ? AtParseResult(
              hasAt: json['atResult']['hasAt'] ?? false,
              contactIds:
                  List<String>.from(json['atResult']['contactIds'] ?? []),
              atNames: List<String>.from(json['atResult']['atNames'] ?? []),
              messageContent: json['atResult']['messageContent'] ?? '',
              originalContent: json['atResult']['originalContent'] ?? '',
              atInfos: [],
            )
          : null,
      needsAI: json['needsAI'] ?? false,
      needsAutoReply: json['needsAutoReply'] ?? false,
      matchedKeywords: json['matchedKeywords'] != null
          ? List<String>.from(json['matchedKeywords'])
          : null,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
    );
  }

  @override
  String toString() {
    return 'MessageRoute(id: $id, type: $routeType, targetContactId: $targetContactId, needsAI: $needsAI)';
  }
}
