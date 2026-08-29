import 'attachment.dart';

/// How a chat bubble should be rendered.
enum MessageKind { chat, thought, tool, system, plan }

/// Message model for chat
class Message {
  final String id;
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final bool isStreaming;
  final List<Attachment> attachments;
  final DateTime? readAt;
  final bool confirmed; // Whether the ACP Agent confirmed the prompt request
  final MessageKind kind;
  final String? toolCallId;
  final String? toolStatus;

  Message({
    required this.id,
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.isStreaming = false,
    this.attachments = const [],
    this.readAt,
    this.confirmed = false,
    this.kind = MessageKind.chat,
    this.toolCallId,
    this.toolStatus,
  });

  /// Create a copy with updated fields
  Message copyWith({
    String? id,
    String? text,
    bool? isUser,
    DateTime? timestamp,
    bool? isStreaming,
    List<Attachment>? attachments,
    DateTime? readAt,
    bool? confirmed,
    MessageKind? kind,
    String? toolCallId,
    String? toolStatus,
  }) {
    return Message(
      id: id ?? this.id,
      text: text ?? this.text,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
      isStreaming: isStreaming ?? this.isStreaming,
      attachments: attachments ?? this.attachments,
      readAt: readAt ?? this.readAt,
      confirmed: confirmed ?? this.confirmed,
      kind: kind ?? this.kind,
      toolCallId: toolCallId ?? this.toolCallId,
      toolStatus: toolStatus ?? this.toolStatus,
    );
  }

  /// Create from JSON
  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] ?? '',
      text: json['text'] ?? '',
      isUser: json['isUser'] ?? false,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
      isStreaming: json['isStreaming'] ?? false,
      attachments: (json['attachments'] as List?)
              ?.map((a) => Attachment.fromJson(a))
              .toList() ??
          [],
      readAt: json['readAt'] != null ? DateTime.parse(json['readAt']) : null,
      confirmed: json['confirmed'] ?? false,
      kind: MessageKind.values.firstWhere(
        (value) => value.name == json['kind'],
        orElse: () => MessageKind.chat,
      ),
      toolCallId: json['toolCallId'] as String?,
      toolStatus: json['toolStatus'] as String?,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'isUser': isUser,
      'timestamp': timestamp.toIso8601String(),
      'isStreaming': isStreaming,
      'attachments': attachments.map((a) => a.toJson()).toList(),
      'readAt': readAt?.toIso8601String(),
      'confirmed': confirmed,
      'kind': kind.name,
      'toolCallId': toolCallId,
      'toolStatus': toolStatus,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Message && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

/// How PocketBot launches an ACP agent.
enum AgentTransportKind { local, ssh }

/// Saved ACP agent launch target (local stdio or SSH + remote stdio).
class GatewayInfo {
  final AgentTransportKind kind;
  final String host;
  final int port;
  final String token;
  final String name;
  final String version;
  final String endpointPath;
  final String workingDirectory;
  final bool secure;
  final String username;
  final String privateKey;
  final String command;
  final List<String> args;

  GatewayInfo({
    this.kind = AgentTransportKind.ssh,
    required this.host,
    int? port,
    this.token = '',
    this.name = 'ACP Agent',
    this.version = 'Unknown',
    this.endpointPath = '/acp',
    this.workingDirectory = '/',
    this.secure = false,
    this.username = '',
    this.privateKey = '',
    this.command = 'agent',
    this.args = const ['acp'],
  }) : port = port ?? (kind == AgentTransportKind.ssh ? 22 : 0);

  factory GatewayInfo.local({
    String name = 'Cursor Agent',
    String workingDirectory = '',
    String command = 'agent',
    List<String> args = const ['acp'],
  }) {
    return GatewayInfo(
      kind: AgentTransportKind.local,
      host: 'local',
      port: 0,
      name: name,
      workingDirectory: workingDirectory,
      command: command,
      args: args,
    );
  }

  factory GatewayInfo.ssh({
    required String host,
    int port = 22,
    required String username,
    String password = '',
    String privateKey = '',
    String name = 'SSH Agent',
    String workingDirectory = '.',
    String command = 'agent',
    List<String> args = const ['acp'],
  }) {
    return GatewayInfo(
      kind: AgentTransportKind.ssh,
      host: host,
      port: port,
      username: username,
      token: password,
      privateKey: privateKey,
      name: name,
      workingDirectory: workingDirectory,
      command: command,
      args: args,
    );
  }

  String get connectionId {
    if (kind == AgentTransportKind.local) {
      return 'local|$workingDirectory|$command';
    }
    return 'ssh|$username@$host:$port';
  }

  String get displayLabel {
    if (kind == AgentTransportKind.local) {
      return workingDirectory.isEmpty ? '这台电脑' : workingDirectory;
    }
    final auth = username.isEmpty ? '' : '$username@';
    final hostLabel = '$auth$host:$port';
    final cwd = workingDirectory.trim();
    if (cwd.isEmpty || cwd == '.' || cwd == '/') {
      return hostLabel;
    }
    return '$hostLabel · $cwd';
  }

  /// Connection URI
  String get uri {
    switch (kind) {
      case AgentTransportKind.local:
        return 'agent://local';
      case AgentTransportKind.ssh:
        final auth = username.isEmpty ? '' : '$username@';
        return 'ssh://$auth$host:$port';
    }
  }

  /// SSH targets need a password or private key.
  bool get requiresAuth =>
      kind == AgentTransportKind.ssh && token.isEmpty && privateKey.isEmpty;

  /// Create from JSON
  factory GatewayInfo.fromJson(Map<String, dynamic> json) {
    final kind = _parseKind(json['kind'] as String?, json['host'] as String?);
    final rawArgs = json['args'];
    return GatewayInfo(
      kind: kind,
      host: json['host'] ?? (kind == AgentTransportKind.local ? 'local' : ''),
      port: json['port'] ?? (kind == AgentTransportKind.local ? 0 : 22),
      token: json['token'] ?? '',
      name: json['name'] ?? 'ACP Agent',
      version: json['version'] ?? 'Unknown',
      endpointPath: json['endpointPath'] ?? '/acp',
      workingDirectory: json['workingDirectory'] ?? '/',
      secure: json['secure'] ?? false,
      username: json['username'] ?? '',
      privateKey: json['privateKey'] ?? '',
      command: json['command'] ?? 'agent',
      args: rawArgs is List
          ? rawArgs.map((item) => item.toString()).toList()
          : const ['acp'],
    );
  }

  static AgentTransportKind _parseKind(String? kind, String? host) {
    switch (kind) {
      case 'local':
        return AgentTransportKind.local;
      case 'ssh':
        return AgentTransportKind.ssh;
      default:
        if (host == 'local' || host == 'localhost') {
          return AgentTransportKind.local;
        }
        return AgentTransportKind.ssh;
    }
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'kind': kind.name,
      'host': host,
      'port': port,
      'token': token,
      'name': name,
      'version': version,
      'endpointPath': endpointPath,
      'workingDirectory': workingDirectory,
      'secure': secure,
      'username': username,
      'privateKey': privateKey,
      'command': command,
      'args': args,
    };
  }

  GatewayInfo copyWith({
    AgentTransportKind? kind,
    String? host,
    int? port,
    String? token,
    String? name,
    String? version,
    String? endpointPath,
    String? workingDirectory,
    bool? secure,
    String? username,
    String? privateKey,
    String? command,
    List<String>? args,
  }) {
    return GatewayInfo(
      kind: kind ?? this.kind,
      host: host ?? this.host,
      port: port ?? this.port,
      token: token ?? this.token,
      name: name ?? this.name,
      version: version ?? this.version,
      endpointPath: endpointPath ?? this.endpointPath,
      workingDirectory: workingDirectory ?? this.workingDirectory,
      secure: secure ?? this.secure,
      username: username ?? this.username,
      privateKey: privateKey ?? this.privateKey,
      command: command ?? this.command,
      args: args ?? this.args,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GatewayInfo && other.connectionId == connectionId;
  }

  @override
  int get hashCode => connectionId.hashCode;
}

/// Chat session model
class ChatSession {
  String id;
  String key;
  String title;
  final DateTime createdAt;
  DateTime lastUpdated;
  List<Message> messages;
  String? agentId;

  int unreadCount = 0;
  bool isGatewaySession = false;
  String? lastMessagePreview;
  String? sourceGatewayHost;
  double? scrollOffset;
  String? customTitle; // User-defined title that persists

  // Token usage fields from Gateway
  int inputTokens = 0;
  int outputTokens = 0;
  int totalTokens = 0;
  int contextTokens = 0;
  String? model;

  ChatSession({
    required this.id,
    required this.key,
    required this.title,
    required this.createdAt,
    required this.lastUpdated,
    required this.messages,
    this.agentId,
    this.unreadCount = 0,
    this.isGatewaySession = false,
    this.lastMessagePreview,
    this.sourceGatewayHost,
    this.scrollOffset,
    this.customTitle,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.totalTokens = 0,
    this.contextTokens = 0,
    this.model,
  });

  /// Create a new empty session
  factory ChatSession.create({String? title}) {
    final now = DateTime.now();
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    return ChatSession(
      id: id,
      key: 'pocketbot-$id',
      title: title ?? '新对话',
      createdAt: now,
      lastUpdated: now,
      messages: [],
    );
  }

  /// Add a message to the session
  void addMessage(Message message) {
    messages.add(message);
    lastUpdated = DateTime.now();
  }

  /// Create from JSON (handles both local and Gateway formats)
  factory ChatSession.fromJson(Map<String, dynamic> json) {
    final key = json['key'] ?? json['id'] ?? '';
    final lastUpdated = json['lastUpdated'] != null
        ? DateTime.parse(json['lastUpdated'])
        : (json['lastMessageAt'] != null
            ? DateTime.parse(json['lastMessageAt'])
            : DateTime.now());
    final createdAt = json['createdAt'] != null
        ? DateTime.parse(json['createdAt'])
        : lastUpdated;

    return ChatSession(
      id: key,
      key: key,
      title: json['title'] ?? '未命名',
      createdAt: createdAt,
      lastUpdated: lastUpdated,
      messages: (json['messages'] as List?)
              ?.map((m) => Message.fromJson(m))
              .toList() ??
          [],
      agentId: json['agentId'],
      unreadCount: json['unreadCount'] ?? 0,
      isGatewaySession: json['isGatewaySession'] ?? false,
      lastMessagePreview: json['lastMessagePreview'],
      sourceGatewayHost: json['sourceGatewayHost'],
      scrollOffset: json['scrollOffset'] != null
          ? (json['scrollOffset'] as num).toDouble()
          : null,
      customTitle: json['customTitle'],
      inputTokens: json['inputTokens'] ?? 0,
      outputTokens: json['outputTokens'] ?? 0,
      totalTokens: json['totalTokens'] ?? 0,
      contextTokens: json['contextTokens'] ?? 0,
      model: json['model'],
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'key': key,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'lastUpdated': lastUpdated.toIso8601String(),
      'messages': messages.map((m) => m.toJson()).toList(),
      'agentId': agentId,
      'unreadCount': unreadCount,
      'isGatewaySession': isGatewaySession,
      'lastMessagePreview': lastMessagePreview,
      'sourceGatewayHost': sourceGatewayHost,
      'scrollOffset': scrollOffset,
      'customTitle': customTitle,
      'inputTokens': inputTokens,
      'outputTokens': outputTokens,
      'totalTokens': totalTokens,
      'contextTokens': contextTokens,
      'model': model,
    };
  }

  /// Create a copy with updated fields
  ChatSession copyWith({
    String? id,
    String? key,
    String? title,
    DateTime? createdAt,
    DateTime? lastUpdated,
    List<Message>? messages,
    String? agentId,
    int? unreadCount,
    bool? isGatewaySession,
    String? lastMessagePreview,
    String? sourceGatewayHost,
    double? scrollOffset,
    String? customTitle,
    int? inputTokens,
    int? outputTokens,
    int? totalTokens,
    int? contextTokens,
    String? model,
  }) {
    return ChatSession(
      id: id ?? this.id,
      key: key ?? this.key,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      messages: messages ?? this.messages,
      agentId: agentId ?? this.agentId,
      unreadCount: unreadCount ?? this.unreadCount,
      isGatewaySession: isGatewaySession ?? this.isGatewaySession,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      sourceGatewayHost: sourceGatewayHost ?? this.sourceGatewayHost,
      scrollOffset: scrollOffset ?? this.scrollOffset,
      customTitle: customTitle ?? this.customTitle,
      inputTokens: inputTokens ?? this.inputTokens,
      outputTokens: outputTokens ?? this.outputTokens,
      totalTokens: totalTokens ?? this.totalTokens,
      contextTokens: contextTokens ?? this.contextTokens,
      model: model ?? this.model,
    );
  }

  /// Format number with k unit (e.g., 1500 -> "1.5k", 200000 -> "200k")
  String _formatNumberWithK(int value) {
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(value % 1000 == 0 ? 0 : 1)}k';
    }
    return value.toString();
  }

  /// Get formatted token usage string
  String get tokenUsageDisplay {
    if (totalTokens == 0) return '暂无数据';
    final percentage = contextTokens > 0
        ? (totalTokens / contextTokens * 100).toStringAsFixed(1)
        : '0';
    return '${_formatNumberWithK(totalTokens)} / ${_formatNumberWithK(contextTokens)} ($percentage%)';
  }
}
