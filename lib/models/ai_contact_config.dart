import 'dart:convert';

/// AI 联系人配置
class AIContactConfig {
  final String id;
  final String contactId; // 联系人 ID
  final String agentId; // ACP Agent identifier
  final String? model; // 使用的模型（可选）
  final String? systemPrompt; // 自定义系统提示词
  final Map<String, dynamic>? tools; // 允许使用的工具
  final bool autoReply; // 是否自动回复（无需 @）
  final List<String>? keywords; // 关键词触发（无需 @）
  final DateTime createdAt;
  final DateTime updatedAt;

  AIContactConfig({
    this.id = '',
    required this.contactId,
    required this.agentId,
    this.model,
    this.systemPrompt,
    this.tools,
    this.autoReply = false,
    this.keywords,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory AIContactConfig.fromJson(Map<String, dynamic> json) {
    return AIContactConfig(
      id: json['id'] ?? '',
      contactId: json['contactId'] ?? '',
      agentId: json['agentId'] ?? '',
      model: json['model'],
      systemPrompt: json['systemPrompt'],
      tools: json['tools'] is Map
          ? Map<String, dynamic>.from(json['tools'])
          : null,
      autoReply: json['autoReply'] ?? false,
      keywords:
          json['keywords'] is List ? List<String>.from(json['keywords']) : null,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'contactId': contactId,
      'agentId': agentId,
      'model': model,
      'systemPrompt': systemPrompt,
      'tools': tools,
      'autoReply': autoReply,
      'keywords': keywords,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// 转换为数据库存储格式
  Map<String, dynamic> toDbMap() {
    return {
      'id': id,
      'contact_id': contactId,
      'agent_id': agentId,
      'model': model,
      'system_prompt': systemPrompt,
      'tools': tools != null ? jsonEncode(tools) : null,
      'auto_reply': autoReply ? 1 : 0,
      'keywords': keywords != null ? jsonEncode(keywords) : null,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// 从数据库格式创建
  factory AIContactConfig.fromDbMap(Map<String, dynamic> map) {
    return AIContactConfig(
      id: map['id'] ?? '',
      contactId: map['contact_id'] ?? '',
      agentId: map['agent_id'] ?? '',
      model: map['model'],
      systemPrompt: map['system_prompt'],
      tools: map['tools'] != null
          ? Map<String, dynamic>.from(jsonDecode(map['tools']))
          : null,
      autoReply: map['auto_reply'] == 1,
      keywords: map['keywords'] != null
          ? List<String>.from(jsonDecode(map['keywords']))
          : null,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'])
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'])
          : DateTime.now(),
    );
  }

  AIContactConfig copyWith({
    String? id,
    String? contactId,
    String? agentId,
    String? model,
    String? systemPrompt,
    Map<String, dynamic>? tools,
    bool? autoReply,
    List<String>? keywords,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AIContactConfig(
      id: id ?? this.id,
      contactId: contactId ?? this.contactId,
      agentId: agentId ?? this.agentId,
      model: model ?? this.model,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      tools: tools ?? this.tools,
      autoReply: autoReply ?? this.autoReply,
      keywords: keywords ?? this.keywords,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AIContactConfig && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
