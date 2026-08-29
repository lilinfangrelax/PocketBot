/// @ 解析结果模型
class AtParseResult {
  /// 是否包含 @ 指令
  final bool hasAt;

  /// 解析是否有效（@目标是否存在）
  final bool isValid;

  /// 是否@了自己
  final bool isSelfAt;

  /// 被 @ 的联系人 ID 列表
  final List<String> contactIds;

  /// 被 @ 的联系人名称列表
  final List<String> atNames;

  /// 解析后的消息内容（去除 @ 部分）
  final String messageContent;

  /// 原始消息内容
  final String originalContent;

  /// @ 信息的位置信息
  final List<AtInfo> atInfos;

  AtParseResult({
    required this.hasAt,
    this.isValid = true,
    this.isSelfAt = false,
    required this.contactIds,
    required this.atNames,
    required this.messageContent,
    required this.originalContent,
    required this.atInfos,
  });

  factory AtParseResult.none() {
    return AtParseResult(
      hasAt: false,
      isValid: true,
      isSelfAt: false,
      contactIds: [],
      atNames: [],
      messageContent: '',
      originalContent: '',
      atInfos: [],
    );
  }

  factory AtParseResult.fromMessage(String message) {
    // 正则匹配 @名字，支持中文、英文、数字、下划线、连字符
    final atRegex = RegExp(r'@([\u4e00-\u9fa5a-zA-Z0-9_-]+)');
    final matches = atRegex.allMatches(message);

    if (matches.isEmpty) {
      return AtParseResult(
        hasAt: false,
        isValid: true,
        isSelfAt: false,
        contactIds: [],
        atNames: [],
        messageContent: message,
        originalContent: message,
        atInfos: [],
      );
    }

    final List<String> atNames = [];
    final List<AtInfo> atInfos = [];
    String processedContent = message;

    for (final match in matches) {
      final atName = match.group(1) ?? '';
      if (atName.isNotEmpty && !atNames.contains(atName)) {
        atNames.add(atName);
        atInfos.add(AtInfo(
          name: atName,
          startIndex: match.start,
          endIndex: match.end,
        ));
      }
    }

    // 移除 @名字 部分，保留剩余内容，并清理多余空格
    processedContent = message.replaceAll(atRegex, '').replaceAll(RegExp(r'\s+'), ' ').trim();

    return AtParseResult(
      hasAt: true,
      isValid: atNames.isNotEmpty,
      isSelfAt: false,
      contactIds: [], // 稍后通过服务查询映射
      atNames: atNames,
      messageContent: processedContent,
      originalContent: message,
      atInfos: atInfos,
    );
  }

  AtParseResult copyWith({
    bool? hasAt,
    bool? isValid,
    bool? isSelfAt,
    List<String>? contactIds,
    List<String>? atNames,
    String? messageContent,
    String? originalContent,
    List<AtInfo>? atInfos,
  }) {
    return AtParseResult(
      hasAt: hasAt ?? this.hasAt,
      isValid: isValid ?? this.isValid,
      isSelfAt: isSelfAt ?? this.isSelfAt,
      contactIds: contactIds ?? this.contactIds,
      atNames: atNames ?? this.atNames,
      messageContent: messageContent ?? this.messageContent,
      originalContent: originalContent ?? this.originalContent,
      atInfos: atInfos ?? this.atInfos,
    );
  }

  @override
  String toString() {
    return 'AtParseResult(hasAt: $hasAt, atNames: $atNames, contactIds: $contactIds, messageContent: $messageContent)';
  }

  Map<String, dynamic> toJson() {
    return {
      'hasAt': hasAt,
      'isValid': isValid,
      'isSelfAt': isSelfAt,
      'contactIds': contactIds,
      'atNames': atNames,
      'messageContent': messageContent,
      'originalContent': originalContent,
      'atInfos': atInfos.map((a) => a.toJson()).toList(),
    };
  }

  factory AtParseResult.fromJson(Map<String, dynamic> json) {
    return AtParseResult(
      hasAt: json['hasAt'] ?? false,
      isValid: json['isValid'] ?? true,
      isSelfAt: json['isSelfAt'] ?? false,
      contactIds: List<String>.from(json['contactIds'] ?? []),
      atNames: List<String>.from(json['atNames'] ?? []),
      messageContent: json['messageContent'] ?? '',
      originalContent: json['originalContent'] ?? '',
      atInfos: json['atInfos'] != null
          ? (json['atInfos'] as List).map((a) => AtInfo.fromJson(a)).toList()
          : [],
    );
  }
}

/// @ 信息
class AtInfo {
  /// @ 的名称（不含 @ 符号）
  final String name;

  /// 在消息中的起始位置
  final int startIndex;

  /// 在消息中的结束位置
  final int endIndex;

  AtInfo({
    required this.name,
    required this.startIndex,
    required this.endIndex,
  });

  @override
  String toString() {
    return 'AtInfo(name: $name, start: $startIndex, end: $endIndex)';
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'startIndex': startIndex,
      'endIndex': endIndex,
    };
  }

  factory AtInfo.fromJson(Map<String, dynamic> json) {
    return AtInfo(
      name: json['name'] ?? '',
      startIndex: json['startIndex'] ?? 0,
      endIndex: json['endIndex'] ?? 0,
    );
  }
}
