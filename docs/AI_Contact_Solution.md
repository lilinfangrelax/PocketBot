# PocketBot AI 联系人群聊功能技术方案

## 一、需求概述

### 1.1 核心场景

1. **用户 @AI 联系人**：用户在群聊中 @AI 联系人，AI 做出回应
2. **AI @AI 联系人**：AI 联系人也可以 @其他 AI 联系人，其他 AI 做出回应
3. **上下文隔离**：每个 AI 联系人在每个群聊中有独立的会话上下文

### 1.2 核心概念

| 概念 | 说明 |
|------|------|
| **AI 联系人** | 群聊中的特殊成员，本质是 ACP Agent 的一个 session |
| **@触发** | 解析消息中的 `@xxx` 匹配 AI 联系人，触发对应 AI 响应 |
| **会话映射** | AI联系人 + 群聊 → 唯一的 ACP sessionId |
| **消息路由** | 判断消息是发给人还是发给 AI |

---

## 二、架构设计

### 2.1 整体架构

```
┌─────────────────────────────────────────────────────────────────┐
│                        PocketBot App                            │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────────┐   │
│  │  群聊消息入口  │ → │  消息路由器   │ → │  AI联系人服务     │   │
│  │ (Webhook/WS) │   │ MessageRouter│   │ AIContactService │   │
│  └──────────────┘   └──────────────┘   └──────────────────┘   │
│                                                     │          │
│                             ┌────────────────────────┼────────┐│
│                             ▼                        ▼        ││
│                     ┌───────────────┐    ┌───────────────────┐ ││
│                     │ 联系人-Session │    │     ACP Agent    │ ││
│                     │   映射表       │    │   (WebSocket)     │ ││
│                     │ ContactSession│    │                   │ ││
│                     │    Mapper     │    │ • session/list    │ ││
│                     └───────────────┘    │ • agent           │ ││
│                                            └───────────────────┘ ││
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 模块职责

| 模块 | 职责 |
|------|------|
| `MessageRouter` | 解析群消息，提取 @ 信息，判断消息类型（用户→AI / AI→AI / 用户→用户） |
| `AIContactService` | 管理 AI 联系人，提供创建、查询、触发响应的能力 |
| `ContactSessionMapper` | 维护 AI联系人+群聊 → sessionKey 的映射关系 |
| `WebSocketService` | 封装 ACP WebSocket 与 JSON-RPC 通信 |
| `GroupMessageService` | 群消息的接收、存储、推送 |

---

## 三、数据模型扩展

### 3.1 现有模型（已支持）

```dart
// lib/models/contact.dart
class Contact {
  String id;
  String name;
  String? atName;        // @名称，用于群聊中触发
  bool isAI;            // 是否为 AI 联系人
  String? agentId;      // ACP Agent identifier
  // ...
}

// lib/models/group_chat.dart
class GroupChat {
  String id;
  List<GroupMember> members;  // 包含 AI 联系人
  // ...
}

class GroupMember {
  String id;
  String userId;
  String? atName;
  bool isAI;             // 是否为 AI 成员
  String? agentId;       // 对应的 agentId
  // ...
}
```

### 3.2 新增模型

#### 3.2.1 AI 联系人配置

```dart
// lib/models/ai_contact_config.dart

/// AI 联系人配置
class AIContactConfig {
  final String contactId;           // 联系人 ID
  final String agentId;             // ACP Agent identifier
  final String? model;              // 使用的模型（可选）
  final String? systemPrompt;      // 自定义系统提示词
  final Map<String, dynamic>? tools; // 允许使用的工具
  final bool autoReply;             // 是否自动回复（无需 @）
  final List<String>? keywords;     // 关键词触发（无需 @）

  AIContactConfig({
    required this.contactId,
    required this.agentId,
    this.model,
    this.systemPrompt,
    this.tools,
    this.autoReply = false,
    this.keywords,
  });
}
```

#### 3.2.2 会话映射

```dart
// lib/models/session_mapping.dart

/// AI 联系人 + 群聊 → Session 映射
class ContactSessionMapping {
  final String id;
  final String contactId;      // AI 联系人 ID
  final String groupId;        // 群聊 ID
  final String sessionKey;    // 对应的 ACP sessionId
  final DateTime createdAt;
  final DateTime lastActiveAt;
  final int messageCount;     // 累计消息数

  ContactSessionMapping({
    required this.id,
    required this.contactId,
    required this.groupId,
    required this.sessionKey,
    required this.createdAt,
    required this.lastActiveAt,
    this.messageCount = 0,
  });
}
```

#### 3.2.3 @ 解析结果

```dart
// lib/models/at_parse_result.dart

/// 消息 @ 解析结果
class AtParseResult {
  final String rawText;           // 原始消息文本
  final String? atTarget;        // @的目标名称（如 "小爱"）
  final String? atTargetId;      // @的目标 ID
  final String messageWithoutAt; // 去除 @ 部分后的消息内容
  final int atPosition;          // @在消息中的位置
  final bool isValid;            // 是否有效（目标是否存在）

  AtParseResult({
    required this.rawText,
    this.atTarget,
    this.atTargetId,
    required this.messageWithoutAt,
    required this.atPosition,
    this.isValid = false,
  });
}
```

#### 3.2.4 消息路由决策

```dart
// lib/models/message_route.dart

/// 消息路由类型
enum MessageRouteType {
  userToUser,    // 用户 → 用户（普通消息）
  userToAI,      // 用户 @ AI
  aiToUser,      // AI → 用户
  aiToAI,        // AI @ AI
  broadcast,     // 广播（无 @）
}

/// 消息路由决策
class MessageRoute {
  final MessageRouteType type;
  final String? sourceContactId;   // 发送者 ID
  final String? targetContactId;  // 接收者 ID（AI 联系人）
  final String? targetAgentId;    // 目标 agentId
  final String? targetSessionKey; // 目标 sessionKey
  final String message;           // 待处理的消息

  MessageRoute({
    required this.type,
    this.sourceContactId,
    this.targetContactId,
    this.targetAgentId,
    this.targetSessionKey,
    required this.message,
  });
}
```

---

## 四、核心模块设计

### 4.1 消息路由器 (MessageRouter)

#### 4.1.1 核心职责
- 解析群消息中的 @ 信息
- 判断消息类型（用户→AI / AI→AI / 用户→用户）
- 过滤自己 @ 自己的情况
- 处理 @ 机器人自己时的自循环问题

#### 4.1.2 完善的 @ 解析逻辑

```dart
// lib/services/message_router.dart

/// @ 解析结果（支持多个 @ 同时触发）
class AtParseResult {
  final String rawText;
  final String? atTarget;        // @的目标名称（如 "小爱"）
  final String? atTargetId;     // @的目标 ID
  final String? atTargetAgentId; // @的目标 agentId
  final String messageWithoutAt; // 去除所有 @ 部分后的消息内容
  final int atPosition;         // @在消息中的位置
  final bool isValid;           // 是否有效（目标是否存在）
  final bool isSelfAt;          // 是否是自己 @ 自己

  AtParseResult({
    required this.rawText,
    this.atTarget,
    this.atTargetId,
    this.atTargetAgentId,
    required this.messageWithoutAt,
    required this.atPosition,
    this.isValid = false,
    this.isSelfAt = false,
  });
}

/// 多个 @ 解析结果
class MultiAtParseResult {
  final String rawText;
  final List<AtParseResult> results;     // 所有 @ 解析结果
  final List<AtParseResult> validAts;    // 有效的 AI @ 目标
  final String messageWithoutAllAt;      // 去除所有 @ 后的消息内容
  final bool hasSelfAt;                  // 是否包含自己 @ 自己

  MultiAtParseResult({
    required this.rawText,
    required this.results,
    required this.validAts,
    required this.messageWithoutAllAt,
    this.hasSelfAt = false,
  });
}

class MessageRouter {
  final ContactService _contactService;
  final AIContactService _aiContactService;
  final ContactSessionMapper _sessionMapper;

  /// 支持中文、英文、数字、下划线、中文标点的正则
  /// 匹配 @xxx 格式，其中 xxx 可以包含中文、英文、数字、下划线、中文标点
  static final RegExp _atPattern = RegExp(
    r'@([\u4e00-\u9fa5a-zA-Z0-9_\u3000-\u303f\uff00-\uffef]+)',
    multiLine: false,
  );

  /// 处理收到的群消息
  Future<MessageRoute?> route(GroupMessage message, String groupId) async {
    // 1. 解析 @ 信息（支持多个 @）
    final multiAtResult = _parseMultiAtInfo(message.content, groupId);

    // 2. 判断发送者是否为 AI
    final isFromAI = _isAIContact(message.senderId);
    final senderInfo = await _contactService.getContact(message.senderId);

    // 3. 如果没有 @ 或无效 @，视为普通消息
    if (multiAtResult.validAts.isEmpty) {
      return MessageRoute(
        type: MessageRouteType.userToUser,
        message: message.content,
      );
    }

    // 4. 处理多 @ 情况（取第一个有效的 AI 目标）
    final atResult = multiAtResult.validAts.first;
    final targetContact = await _contactService.getContact(atResult.atTargetId!);

    // 5. 过滤自己 @ 自己的情况
    if (atResult.isSelfAt) {
      // 自己 @ 自己，忽略或记录日志
      return null;
    }

    // 6. 检查是否 @ 的是机器人自己（自循环检测）
    if (_isBotContact(atResult.atTargetId)) {
      // 防止自循环：检测到 @ 机器人自己，忽略或限流
      return null;
    }

    // 7. 获取或创建 AI 的 session
    final sessionKey = await _sessionMapper.getOrCreateSession(
      contactId: atResult.atTargetId!,
      groupId: groupId,
      agentId: atResult.atTargetAgentId!,
    );

    // 8. 返回路由决策
    return MessageRoute(
      type: isFromAI ? MessageRouteType.aiToAI : MessageRouteType.userToAI,
      sourceContactId: message.senderId,
      sourceName: senderInfo?.name,
      targetContactId: atResult.atTargetId,
      targetAgentId: atResult.atTargetAgentId,
      targetSessionKey: sessionKey,
      message: multiAtResult.messageWithoutAllAt,
      rawMessage: message.content,
    );
  }

  /// 解析多个 @ 信息
  MultiAtParseResult _parseMultiAtInfo(String content, String groupId) {
    final matches = _atPattern.allMatches(content).toList();
    final results = <AtParseResult>[];
    final validAts = <AtParseResult>[];

    // 查找群成员
    final groupMembers = _getGroupMembersSync(groupId);
    final memberMap = <String, GroupMember>{};
    for (final member in groupMembers) {
      if (member.atName != null) {
        memberMap[member.atName!] = member;
      }
    }

    String processedContent = content;
    for (final match in matches) {
      final atName = match.group(1)!;
      final member = memberMap[atName];

      AtParseResult result;
      if (member != null) {
        // 找到对应的群成员
        result = AtParseResult(
          rawText: content,
          atTarget: atName,
          atTargetId: member.id,
          atTargetAgentId: member.agentId,
          messageWithoutAt: '',
          atPosition: match.start,
          isValid: member.isAI,
          isSelfAt: member.isAI && member.id == _getBotContactId(),
        );

        if (member.isAI && !result.isSelfAt) {
          validAts.add(result);
        }
      } else {
        // 未找到成员，标记为无效
        result = AtParseResult(
          rawText: content,
          atTarget: atName,
          messageWithoutAt: '',
          atPosition: match.start,
          isValid: false,
        );
      }
      results.add(result);
    }

    // 移除所有 @ 部分，获取纯消息内容
    final messageWithoutAllAt = content.replaceAll(_atPattern, '').trim();

    // 检查是否有自己 @ 自己的情况
    final hasSelfAt = results.any((r) => r.isSelfAt);

    return MultiAtParseResult(
      rawText: content,
      results: results,
      validAts: validAts,
      messageWithoutAllAt: messageWithoutAllAt,
      hasSelfAt: hasSelfAt,
    );
  }

  /// 检查是否 @ 的是机器人自己（防自循环）
  bool _isBotContact(String? contactId) {
    if (contactId == null) return false;
    // 获取机器人自己的联系人 ID
    final botContactId = _getBotContactId();
    return contactId == botContactId;
  }

  String? _getBotContactId() {
    // 从配置或服务获取机器人自己的 ID
    return null; // TODO: 实现
  }

  List<GroupMember> _getGroupMembersSync(String groupId) {
    // 同步获取群成员
    return []; // TODO: 实现
  }

  /// 判断是否为 AI 联系人
  bool _isAIContact(String contactId) {
    final contact = _contactService.getContactSync(contactId);
    return contact?.isAI ?? false;
  }
}
```

#### 4.1.3 防自循环机制

```dart
/// 自循环检测与防止
class SelfLoopProtection {
  /// 消息来源追踪（用于检测循环）
  static final Map<String, Set<String>> _messageTrace = {};

  /// 最大递归深度
  static const int maxRecursionDepth = 3;

  /// 检测是否可能产生循环
  static bool detectLoop({
    required String groupId,
    required String sourceContactId,
    required String targetContactId,
  }) {
    // 目标是自己
    if (sourceContactId == targetContactId) {
      return true;
    }

    // 检查消息追踪
    final traceKey = '$groupId:$sourceContactId';
    final trace = _messageTrace[traceKey] ?? {};

    // 如果目标已经在追踪中，说明可能形成循环
    if (trace.contains(targetContactId)) {
      return true;
    }

    // 追踪深度检查
    if (trace.length >= maxRecursionDepth) {
      return true;
    }

    return false;
  }

  /// 记录消息轨迹
  static void recordTrace({
    required String groupId,
    required String sourceContactId,
    required String targetContactId,
  }) {
    final traceKey = '$groupId:$sourceContactId';
    _messageTrace[traceKey] ??= {};
    _messageTrace[traceKey]!.add(targetContactId);

    // 清理过期轨迹（保留最近 100 条）
    if (_messageTrace.length > 100) {
      _messageTrace.remove(_messageTrace.keys.first);
    }
  }

  /// 清理指定群聊的轨迹
  static void clearTrace(String groupId) {
    _messageTrace.removeWhere((key, _) => key.startsWith('$groupId:'));
  }
}
```

### 4.2 AI 联系人服务 (AIContactService)

```dart
// lib/services/ai_contact_service.dart

class AIContactService {
  final WebSocketService _wsService;
  final ContactSessionMapper _sessionMapper;
  final NotificationService _notificationService;

  /// 触发 AI 响应
  Future<void> triggerAIResponse({
    required String agentId,
    required String sessionKey,
    required String message,
    required String groupId,
    required String senderName,
    Function(String)? onChunk,      // 流式输出回调
    Function(String)? onComplete,    // 完成回调
  }) async {
    // 1. 构建上下文消息（包含是谁发的）
    final contextMessage = _buildContextMessage(message, senderName, groupId);

    // 2. 发送消息到 ACP Agent
    await _wsService.sendMessageWithAttachments(
      contextMessage,
      [],
      sessionKey: sessionKey,
    );

    // 3. 监听响应（复用现有的流式处理）
    _wsService.messages.listen((msg) {
      if (!msg.isUser && msg.id == sessionKey) {
        onChunk?.call(msg.text);
      }
    });

    // 4. 响应完成后，推送到群聊
    final response = await _waitForComplete(sessionKey);
    await _pushToGroupChat(groupId, response);
  }

  /// 构建上下文消息
  String _buildContextMessage(String message, String senderName, String groupId) {
    return '''[群消息] 来自: $senderName (群: $groupId)
---
$message''';
  }

  /// 推送 AI 响应到群聊
  Future<void> _pushToGroupChat(String groupId, String response) async {
    // TODO: 实现群消息推送（根据实际后端能力）
    // 可能需要通过 Webhook 或其他 API 推送
  }

  /// 创建新的 AI 会话
  Future<String> createAISession({
    required String contactId,
    required String groupId,
    required String agentId,
    String? title,
  }) async {
    // 1. 在 ACP Agent 创建 session
    final session = await _wsService.createGatewaySession(
      title ?? '群聊-$groupId',
    );

    // 2. 保存映射关系
    await _sessionMapper.saveMapping(
      contactId: contactId,
      groupId: groupId,
      sessionKey: session.key,
    );

    return session.key;
  }

  /// 获取 AI 联系人列表
  List<Contact> getAIContacts() {
    // 从 ContactService 获取所有 isAI=true 的联系人
    return _contactService.getContacts().where((c) => c.isAI).toList();
  }
}
```

### 4.3 会话映射管理器 (ContactSessionMapper)

```dart
// lib/services/contact_session_mapper.dart

class ContactSessionMapper {
  final DatabaseService _db;

  /// 获取或创建会话映射
  Future<String> getOrCreateSession({
    required String contactId,
    required String groupId,
    required String agentId,
  }) async {
    // 1. 查找现有映射
    final existing = await _db.getMapping(contactId, groupId);
    if (existing != null) {
      // 更新最后活跃时间
      await _db.updateMappingLastActive(existing.id);
      return existing.sessionKey;
    }

    // 2. 创建新映射
    final newSessionKey = await _createNewSession(contactId, groupId, agentId);

    await _db.saveMapping(ContactSessionMapping(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      contactId: contactId,
      groupId: groupId,
      sessionKey: newSessionKey,
      createdAt: DateTime.now(),
      lastActiveAt: DateTime.now(),
    ));

    return newSessionKey;
  }

  /// 创建新会话
  Future<String> _createNewSession(String contactId, String groupId, String agentId) async {
    // 通过 WebSocketService 创建
    // 注意：需要在 WebSocketService 添加对应方法
    final session = await wsService.createGatewaySession(
      'AI-$contactId-$groupId',
    );
    return session.key;
  }

  /// 清理不活跃的会话（可选）
  Future<void> cleanupInactiveSessions({Duration maxInactive = const Duration(days: 7)}) async {
    final inactiveMappings = await _db.getInactiveMappings(maxInactive);
    for (final mapping in inactiveMappings) {
      // 可选：通知 ACP Agent 删除 session
      await _db.deleteMapping(mapping.id);
    }
  }
}
```

---

## 五、业务流程

### 5.1 用户 @AI 流程

```
┌─────────┐    ┌──────────────┐    ┌─────────────┐    ┌──────────────┐
│ 用户发送 │ → │ 群消息监听   │ → │ 消息路由    │ → │ 查找/创建    │
│ @AI消息 │    │ GroupMsg    │    │ MessageRouter│   │ Session     │
└─────────┘    └──────────────┘    └─────────────┘    └──────────────┘
                                                              │
                                                              ▼
┌─────────┐    ┌──────────────┐    ┌─────────────┐    ┌──────────────┐
│ 群聊显示 │ ← │ 推送响应到群  │ ← │ 接收流式响应 │ ← │   ACP API    │
│ AI回复  │    │ (WebHook/API)│    │ WebSocket   │    │ agent        │
└─────────┘    └──────────────┘    └─────────────┘    └──────────────┘
```

### 5.2 AI @AI 流程

```
┌─────────┐    ┌──────────────┐    ┌─────────────┐    ┌──────────────┐
│ AI发送  │ → │ 群消息监听    │ → │ 识别source  │ → │ 解析 @目标   │
│ @其他AI │    │              │    │ isAI=true   │    │              │
└─────────┘    └──────────────┘    └─────────────┘    └──────────────┘
                                                              │
                                                              ▼
       ┌──────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────┐    ┌─────────────┐    ┌──────────────┐
│ 查找目标AI   │ → │ 获取目标Session │ → │   ACP API    │
│ Session      │    │              │    │ agent        │
└──────────────┘    └─────────────┘    └──────────────┘
```

---

## 六、数据库扩展

### 6.1 新增表

```sql
-- AI 联系人配置表
CREATE TABLE ai_contact_config (
  id TEXT PRIMARY KEY,
  contact_id TEXT NOT NULL,
  agent_id TEXT NOT NULL,
  model TEXT,
  system_prompt TEXT,
  tools TEXT,  -- JSON
  auto_reply INTEGER DEFAULT 0,
  keywords TEXT,  -- JSON array
  created_at TEXT,
  updated_at TEXT,
  FOREIGN KEY (contact_id) REFERENCES contacts(id)
);

-- 会话映射表
CREATE TABLE contact_session_mapping (
  id TEXT PRIMARY KEY,
  contact_id TEXT NOT NULL,
  group_id TEXT NOT NULL,
  session_key TEXT NOT NULL,
  created_at TEXT,
  last_active_at TEXT,
  message_count INTEGER DEFAULT 0,
  UNIQUE(contact_id, group_id)
);

-- 群聊消息表（扩展）
CREATE TABLE group_messages (
  id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL,
  sender_id TEXT NOT NULL,
  sender_name TEXT,
  content TEXT,
  at_list TEXT,  -- JSON array of AtInfo
  is_ai_response INTEGER DEFAULT 0,
  related_session_key TEXT,
  timestamp TEXT,
  created_at TEXT
);
```

---

## 七、实现步骤

### 阶段一：基础架构（1-2天）

| 序号 | 任务 | 产出 |
|------|------|------|
| 1.1 | 新增数据模型（AIContactConfig, SessionMapping, AtParseResult, MessageRoute） | `lib/models/` 新增文件 |
| 1.2 | 扩展数据库表 | SQLite schema 更新 |
| 1.3 | 实现 ContactSessionMapper | `lib/services/contact_session_mapper.dart` |

### 阶段二：消息路由（1-2天）

| 序号 | 任务 | 产出 |
|------|------|------|
| 2.1 | 实现 @ 解析逻辑 | `AtParseResult` 解析器 |
| 2.2 | 实现 MessageRouter | 路由决策逻辑 |
| 2.3 | 集成联系人服务，验证 @ 匹配 | 单元测试 |

### 阶段三：AI 响应（2-3天）

| 序号 | 任务 | 产出 |
|------|------|------|
| 3.1 | 扩展 WebSocketService 支持 session 创建 | ACP API 封装 |
| 3.2 | 实现 AIContactService.triggerAIResponse | 触发 AI 响应 |
| 3.3 | 流式响应处理与群聊推送 | 完整流程串通 |

### 阶段四：高级功能（1-2天）

| 序号 | 任务 | 产出 |
|------|------|------|
| 4.1 | AI @ AI 递归触发 | 循环检测与处理 |
| 4.2 | 自动回复（关键词/无@） | 配置化支持 |
| 4.3 | 会话清理与优化 | 定时任务 |

---

## 八、待确认事项

1. **群消息来源**：群消息是通过什么方式获取的？Webhook / 轮询 / 第三方 SDK？
2. **消息推送**：AI 响应后如何推送到群聊？是否有现成的 Webhook/API？
3. **Session 隔离**：是否需要为每个群聊的每个 AI 联系人创建独立 session？（当前方案是独立的）
4. **多平台支持**：是否需要支持同时对接多个聊天平台（微信+Telegram）？

---

## 十、补充模块设计

### 4.4 统一协调层 (GroupChatCoordinator)

```dart
// lib/services/group_chat_coordinator.dart

/// 群聊协调器 - 统一编排整个处理流程
class GroupChatCoordinator {
  final MessageRouter _router;
  final AIContactService _aiService;
  final RateLimiter _rateLimiter;
  final IdempotencyCache _idempotency;
  final EventBus _eventBus;

  /// 处理收到的群消息
  Future<void> handleMessage(GroupMessage message) async {
    final groupId = message.groupId;
    
    // 1. 幂等性检查
    if (!_idempotency.tryAcquire(message.id)) {
      _eventBus.emit(DuplicateMessageEvent(message.id));
      return;
    }

    // 2. 限流检查
    final rateLimitResult = await _rateLimiter.check(message);
    if (!rateLimitResult.allowed) {
      _eventBus.emit(RateLimitExceededEvent(
        message: message,
        retryAfter: rateLimitResult.retryAfter,
      ));
      return;
    }

    try {
      // 3. 消息路由
      _eventBus.emit(MessageReceivedEvent(message));
      
      final route = await _router.route(message, groupId);
      if (route == null) return;

      // 4. 执行路由
      switch (route.type) {
        case MessageRouteType.userToUser:
          // 普通消息，不处理
          break;
        case MessageRouteType.userToAI:
        case MessageRouteType.aiToAI:
          await _executeAIRoute(route);
          break;
      }
    } catch (e) {
      _eventBus.emit(ErrorOccurredEvent(e, message));
      // 降级处理
      await _handleError(e, message);
    }
  }

  Future<void> _executeAIRoute(MessageRoute route) async {
    _eventBus.emit(AIResponseStartEvent(route.targetContactId!));
    
    await _aiService.triggerAIResponse(
      agentId: route.targetAgentId!,
      sessionKey: route.targetSessionKey!,
      message: route.message,
      groupId: route.targetSessionKey!.split('-').first,
      senderName: route.sourceName ?? 'Unknown',
      onComplete: (response) {
        _eventBus.emit(AIResponseCompleteEvent(
          contactId: route.targetContactId!,
          response: response,
        ));
      },
    );
  }

  Future<void> _handleError(Object error, GroupMessage message) async {
    // 降级：记录错误，发送友好提示
    // 可以扩展为重试、降级通知等
  }
}
```

### 4.5 事件总线 (EventBus)

```dart
// lib/core/event_bus.dart

/// 事件类型
abstract class AppEvent {
  final DateTime timestamp = DateTime.now();
}

class MessageReceivedEvent extends AppEvent {
  final GroupMessage message;
  MessageReceivedEvent(this.message);
}

class AIResponseStartEvent extends AppEvent {
  final String contactId;
  AIResponseStartEvent(this.contactId);
}

class AIResponseCompleteEvent extends AppEvent {
  final String contactId;
  final String response;
  AIResponseCompleteEvent({required this.contactId, required this.response});
}

class ErrorOccurredEvent extends AppEvent {
  final Object error;
  final GroupMessage? message;
  ErrorOccurredEvent(this.error, [this.message]);
}

class RateLimitExceededEvent extends AppEvent {
  final GroupMessage message;
  final Duration retryAfter;
  RateLimitExceededEvent({required this.message, required this.retryAfter});
}

class DuplicateMessageEvent extends AppEvent {
  final String messageId;
  DuplicateMessageEvent(this.messageId);
}

/// 事件总线
class EventBus {
  final _handlers = <Type, List<Function>>{};

  void on<T extends AppEvent>(void Function(T) handler) {
    _handlers[T] ??= [];
    _handlers[T]!.add(handler);
  }

  void off<T extends AppEvent>(void Function(T) handler) {
    _handlers[T]?.remove(handler);
  }

  void emit<T extends AppEvent>(T event) {
    final handlers = _handlers[T];
    if (handlers != null) {
      for (final h in handlers) {
        h(event);
      }
    }
  }
}
```

### 4.6 限流设计 (RateLimiter)

```dart
// lib/core/rate_limiter.dart

/// 限流规则
class RateLimitRule {
  final String key;           // 限流 key（如 "user:123", "group:456"）
  final int maxRequests;       // 时间窗口内最大请求数
  final Duration window;      // 时间窗口

  const RateLimitRule({
    required this.key,
    required this.maxRequests,
    required this.window,
  });
}

/// 限流检查结果
class RateLimitResult {
  final bool allowed;
  final Duration? retryAfter;
  final int remaining;

  const RateLimitResult({
    required this.allowed,
    this.retryAfter,
    this.remaining = 0,
  });
}

/// 限流器 - 滑动窗口算法
class RateLimiter {
  // 内存缓存（生产环境可用 Redis）
  final _counters = <String, List<DateTime>>{};

  // 默认规则
  static const defaultRules = {
    'user': RateLimitRule(key: 'user', maxRequests: 10, window: Duration(minutes: 1)),
    'group': RateLimitRule(key: 'group', maxRequests: 20, window: Duration(minutes: 1)),
    'global': RateLimitRule(key: 'global', maxRequests: 100, window: Duration(minutes: 1)),
  };

  /// 检查限流
  Future<RateLimitResult> check(GroupMessage message) async {
    final now = DateTime.now();
    
    // 1. 用户限流
    final userResult = _checkWindow('user:${message.senderId}', now);
    if (!userResult.allowed) return userResult;

    // 2. 群限流
    final groupResult = _checkWindow('group:${message.groupId}', now);
    if (!groupResult.allowed) return groupResult;

    // 3. 全局限流
    final globalResult = _checkWindow('global', now);
    if (!globalResult.allowed) return globalResult;

    return const RateLimitResult(allowed: true);
  }

  RateLimitResult _checkWindow(String key, DateTime now) {
    final rule = defaultRules[key] ?? defaultRules['global']!;
    _counters[key] ??= [];
    
    final timestamps = _counters[key]!;
    final windowStart = now.subtract(rule.window);
    
    // 清理过期的
    timestamps.removeWhere((t) => t.isBefore(windowStart));
    
    if (timestamps.length >= rule.maxRequests) {
      // 计算最早过期时间
      final earliest = timestamps.first;
      final retryAfter = earliest.difference(now) + rule.window;
      return RateLimitResult(
        allowed: false,
        retryAfter: retryAfter,
        remaining: 0,
      );
    }
    
    timestamps.add(now);
    return RateLimitResult(
      allowed: true,
      remaining: rule.maxRequests - timestamps.length,
    );
  }
}
```

### 4.7 消息幂等性 (IdempotencyCache)

```dart
// lib/core/idempotency_cache.dart

/// 幂等性缓存 - 防止重复处理消息
class IdempotencyCache {
  final _cache = <String, DateTime>{};
  final Duration _ttl;

  IdempotencyCache({Duration ttl = const Duration(minutes: 5)})
      : _ttl = ttl;

  /// 尝试获取锁 - 返回 true 表示可以处理
  bool tryAcquire(String messageId) {
    if (_cache.containsKey(messageId)) {
      return false; // 已处理过
    }
    _cache[messageId] = DateTime.now();
    _cleanup();
    return true;
  }

  void _cleanup() {
    final expireBefore = DateTime.now().subtract(_ttl);
    _cache.removeWhere((_, v) => v.isBefore(expireBefore));
  }
}
```

### 4.8 AIContactService 完善（超时 + 重试）

```dart
// lib/services/ai_contact_service.dart 补充

class AIContactService {
  // 重试配置
  static const maxRetries = 3;
  static const retryDelays = [Duration(seconds: 1), Duration(seconds: 3), Duration(seconds: 10)];
  static const defaultTimeout = Duration(seconds: 60);

  /// 带重试的 AI 响应触发
  Future<void> triggerAIResponseWithRetry({
    required String agentId,
    required String sessionKey,
    required String message,
    required String groupId,
    required String senderName,
    Function(String)? onChunk,
    Function(String)? onComplete,
  }) async {
    Object? lastError;
    
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      try {
        await triggerAIResponse(
          agentId: agentId,
          sessionKey: sessionKey,
          message: message,
          groupId: groupId,
          senderName: senderName,
          onChunk: onChunk,
          onComplete: onComplete,
        );
        return; // 成功
      } catch (e) {
        lastError = e;
        if (attempt < maxRetries - 1) {
          // 指数退避等待
          await Future.delayed(retryDelays[attempt]);
        }
      }
    }
    
    // 全部重试失败
    throw AIResponseException(
      'AI 响应失败，已重试 $maxRetries 次: $lastError',
    );
  }

  /// 带超时的响应触发
  Future<String> triggerAIResponseWithTimeout({
Id,
    required String sessionKey,
    required String agent    required String message,
    required String groupId,
    required String senderName,
    Duration timeout = defaultTimeout,
  }) async {
    final completer = Completer<String>();
    StreamSubscription? sub;
    
    // 超时处理
    sub = Timer(timeout, () {
      sub?.cancel();
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException('AI 响应超时'));
      }
    });
    
    try {
      await triggerAIResponse(
        agentId: agentId,
        sessionKey: sessionKey,
        message: message,
        groupId: groupId,
        senderName: senderName,
        onComplete: (response) {
          sub?.cancel();
          if (!completer.isCompleted) {
            completer.complete(response);
          }
        },
      );
    } catch (e) {
      sub?.cancel();
      if (!completer.isCompleted) {
        completer.completeError(e);
      }
    }
    
    return completer.future;
  }
}

class AIResponseException implements Exception {
  final String message;
  AIResponseException(this.message);
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);
}
```

---

## 十一、总结

本方案完整描述了 PocketBot AI 联系人群聊功能的技术实现，涵盖：

| 模块 | 功能 |
|------|------|
| MessageRouter | @ 解析、中文支持、多 @、防自循环 |
| AIContactService | 流式响应、超时重试 |
| ContactSessionMapper | 会话映射、生命周期管理 |
| GroupChatCoordinator | 统一编排、异常处理、降级 |
| EventBus | 事件驱动、解耦 |
| RateLimiter | 用户/群/全局限流 |
| IdempotencyCache | 消息幂等性 |

### 下一步

1. 确认群消息来源和推送方式
2. 实现数据库表结构
3. 按阶段编码实现
