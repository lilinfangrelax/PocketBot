# PocketBot E2E 验收

Windows 桌面端采用混合验收：

- `@uia` Feature 由 Teshi 的 winapp bridge 驱动真实窗口，验收应用外壳与底部导航。
- `@integration` Feature 由 Flutter `integration_test` 驱动真实应用逻辑与界面，使用确定性 Mock ACP 代理，不访问网络或真实代理。

Feature 位于 `features/zh-CN/`，步骤文本不包含选择器。

## 覆盖范围

| Feature | 标签 | 执行入口 | 验收内容 |
| --- | --- | --- | --- |
| 启动与底部导航 | `@uia` | `tool/e2e_uia.ps1` | 启动默认消息页、四个底部标签切换 |
| 本机ACP连接与聊天 | `@integration` | `acp_chat_test.dart` | 本机代理启动、会话建立、确定性回复 |
| 聊天消息与流式回复 | `@integration` | `chat_streaming_test.dart` | 分块流式呈现、空消息不发送、代码块复制 |
| 生成控制与异常恢复 | `@integration` | `generation_control_test.dart` | 停止生成、断线发送失败保留输入、重连重发 |
| 会话历史与多会话 | `@integration` | `session_history_test.dart` | 重启恢复历史、多会话切换互不串消息、删除会话同步移除存储 |
| 工具调用与权限确认 | `@integration` | `tool_permission_test.dart` | 允许一次后工具完成、拒绝后工具失败并继续回复 |
| 群聊@路由 | `@integration` | `group_at_routing_test.dart` | 真实群聊界面中被 @ 的联系人回复、未 @ 时不触发、多代理分别回复、失效连接仅提示失败 |
| ACP能力与计划 | `@integration` | `acp_capabilities_test.dart` | 代理配置选项（模型/模式）展示与切换、计划面板展开、`cursor/update_todos` 待办、`available_commands_update` 斜杠命令、代理 fs 读写 |
| 通讯录与AI联系人 | `@integration` | `ai_contact_test.dart` | AI 联系人创建与代理绑定、从通讯录打开聊天 |
| 通讯录联系人管理 | `@integration` | `contact_management_test.dart` | 详情中改名后详情与列表同步、删除后列表隐藏且存储中停用 |
| 设置与MCP | `@integration` | `settings_mcp_test.dart` | 添加 stdio MCP 服务器后列表与配置持久化、删除后列表与配置同步移除 |
| SSH远程连接 | `@integration` | `ssh_connection_test.dart` | 只填主机和用户名时阻止登录并提示缺少密码或私钥；真实 SSH 握手依赖外部主机，未纳入自动化 |

每个 `@integration` 场景都是独立的 `testWidgets` 用例，可单独运行；同一文件内的用例通过 `AppStateSnapshot` 备份并恢复用户状态，并在开始时重建隔离数据库。

## 集成测试

```powershell
powershell -ExecutionPolicy Bypass -File tool/e2e_integration.ps1
```

脚本会：

1. 在 `build/e2e/mock_agent_src` 中独立编译 `tool/mock_acp_agent.dart`，输出 `build/e2e/mock_acp_agent.exe`。
2. 通过 `POCKETBOT_E2E_DB_DIR=build/e2e/db` 将 SQLite 数据库隔离到工作区。
3. 通过 `POCKETBOT_E2E_MOCK_AGENT` 让应用以 `pocketbot-mock` 代理启动 Mock ACP 代理。
4. 依次运行 `integration_test/*_test.dart`（`flutter test -d windows`），任一失败即停止。

`-Only <名称片段>` 只运行匹配的测试文件，例如 `-Only group`。`-KeepDb` 会设置 `POCKETBOT_E2E_KEEP_DB=1`，跳过清空 `build/e2e/db`，保留上一次的数据库便于排查。

运行前请关闭已在运行的 PocketBot，避免它占用 SQLite 数据库文件。测试会备份并在结束时恢复用户的会话、已保存连接、MCP 配置与代理选择（Flutter secure storage 中的 `chat_sessions`、`gateways_config`、`last_connected_gateway`、`mcp_servers`，以及 SharedPreferences 中的 `acp_agent_id` / `acp_agent_label`）；恢复前会先卸载界面并等待防抖写入落盘，避免与退出保存竞态。测试中途强制结束进程时，这些数据可能停留在测试状态，请重新运行一次或手动恢复。

### 真实 SSH 手工验收

`integration_test/manual/real_ssh_test.dart` 针对真实 SSH 主机上的 ACP 代理做端到端验证：应用通过 SSH 登录，远端 helper 安装/探测代理，启动 Cursor ACP，建立会话并收到回复。该文件位于顶层 `*_test.dart` 之外，不会被 `tool/e2e_integration.ps1` 选中，需要手工运行。

```powershell
$env:POCKETBOT_REAL_SSH_HOST='47.119.137.225'
$env:POCKETBOT_REAL_SSH_PORT='37777'
$env:POCKETBOT_REAL_SSH_USER='enhook'
$env:POCKETBOT_REAL_SSH_KEY_FILE="$env:USERPROFILE\.ssh\id_rsa"
$env:NO_PROXY='127.0.0.1,localhost'
$env:no_proxy='127.0.0.1,localhost'
flutter test integration_test/manual/real_ssh_test.dart -d windows
```

`NO_PROXY` 必须包含本机回环地址：Flutter 测试驱动通过 VM Service 的 localhost WebSocket 连接被测进程，若系统代理（如 `HTTP_PROXY=127.0.0.1:10808`）同时生效，握手会被劫持并报 `was not upgraded to websocket`。测试会备份并恢复本机会话与连接配置，不会打印私钥内容。远端 helper 按设计在断开后保留代理进程，重复运行会以 `--fresh` 重建会话。

### Mock ACP 代理

`tool/mock_acp_agent.dart` 通过 stdin/stdout 收发 NDJSON JSON-RPC，实现 `initialize`、`session/new`、`session/resume`、`session/load`、`session/prompt`、`session/cancel`。默认将 `MOCK_AGENT_OK: <提示文本>` 拆成三块推送后返回 `stopReason: end_turn`，并可用特殊提示触发确定行为：

| 提示文本 | 行为 |
| --- | --- |
| `e2e-stream` | 间隔 900ms 推送 `MOCK_STREAM:1..3`，用于观察流式过程 |
| `e2e-slow` | 推送首块后等待取消；收到 `session/cancel` 返回 `stopReason: cancelled`，否则 30 秒后补发第二块 |
| `e2e-markdown` | 推送包含代码块的 Markdown 回复 |
| `e2e-plan` | 推送三步计划（1 完成、1 进行中、1 待办）后回复 `MOCK_PLAN_OK`，用于验收计划面板 |
| `e2e-todos` | 发送 `cursor/update_todos` 通知（1 完成、1 进行中）后回复 `MOCK_TODOS_OK`，用于验收待办横幅 |
| `e2e-fs` | 通过 `fs/write_text_file` 写入 `pocketbot-e2e-fs.txt`、读回并删除后回复 `MOCK_FS: E2E_FS_OK`，用于验收客户端文件系统能力 |
| `e2e-tool` | 发出 `pending` 工具调用「运行 E2E 命令」并请求 `session/request_permission`；选择 `allow_once` 时工具变为 `completed` 并回复 `MOCK_TOOL_ALLOWED`，选择 `reject_once` 时变为 `failed` 并回复 `MOCK_TOOL_DENIED` |

`session/new` 还会下发 `configOptions`（`model`: Mock Fast / Mock Smart，`mode`: Agent / Plan）与 `available_commands_update`（`/reset`、`/plan`）；`session/set_config_option`、`session/set_mode` 会更新会话状态并返回最新选项。

它只在 Debug 构建中、`agentId == "pocketbot-mock"` 且设置了 `POCKETBOT_E2E_MOCK_AGENT` 时启用，Release 构建不会包含该分支。

## UIA 验收

前置条件：Teshi winapp sidecar 已运行，`.teshi/cdp-endpoint.json` 的 `mode` 为 `winapp`。

```powershell
powershell -ExecutionPolicy Bypass -File tool/e2e_uia.ps1
```

脚本构建 Debug 版本（`flutter test` 会把 exe 覆盖为测试监听器，因此每次回放前都会重新构建）、以 `POCKETBOT_E2E_DB_DIR` 隔离数据库启动应用，按 PID 轮询附着窗口（最多 30 秒，应用提前退出会直接报错），并在 `teshi check` 通过后以 `--mode background` 回放 Feature。

`启动与底部导航.feature` 的 14 个步骤已绑定到 `uia:` 选择器。绑定保存在 Teshi 本机存储（`~/.teshi/store.db`），项目内的 `.teshi/` 只是运行时状态并已加入 `.gitignore`；换机器或 CI 需要重新绑定，或先用 `teshi export --target behave` 导出可提交的测试工程。每个切换场景都会先点击「消息」标签回到确定状态，因此场景可独立、顺序回放。修改 Feature 步骤文本后需要重新绑定：

```text
teshi check --feature features/zh-CN/启动与底部导航.feature --json
teshi steps list --feature features/zh-CN/启动与底部导航.feature
teshi winapp attach --pid <PID>
teshi winapp snapshot
```

底部标签与会话行已补充 `Semantics(onTap, label)`（会话行的 `label` 包含标题、未读数、预览与时间），普通按钮使用 Fluent 自带语义；UIA 回放只使用非侵入式点击，不需要物理鼠标输入。

## 可测性配套改动

- `lib/widgets/fluent_tab_bar.dart`、`lib/screens/wechat_session_list.dart`：底部标签与会话行补充 `onTap`/`label`，使 UIA InvokePattern 能够触发导航；切回「消息」标签时会刷新会话列表，避免从其他标签发起的聊天因缺少 WebSocket 通知而陈旧。
- `lib/screens/chat_screen.dart`：输入框增加 `chat-input` Key；发送失败提示改用 Fluent InfoBar（`showAppNotice`），因为 Fluent 页面没有 Material `Scaffold`，`ScaffoldMessenger` 会断言失败。
- `lib/screens/group_chat_screen.dart`：群聊输入框与发送按钮增加 `group-chat-input` / `group-chat-send` Key。
- `lib/widgets/fluent_page.dart`：返回按钮增加 `screen-back` Key，集成测试不再依赖 Material/Cupertino 的 `pageBack()`。
- `integration_test/e2e_harness.dart`：`sendChatMessage` 先点击输入框再注入文本（`integration_test` 使用真实文本输入通道，未聚焦时注入会被丢弃）；`resetE2eDatabase` 关闭数据库并清理 AI 联系人建表缓存；`AppStateSnapshot` 备份/恢复用户会话、连接、MCP 配置与代理选择。
- `lib/services/ai_contact_service.dart`：提供 `resetTableCache()`，数据库重建后重新建表（测试专用）。
- `lib/services/database_service.dart`：Windows/Linux 使用 `sqflite_common_ffi`，Debug 构建支持 `POCKETBOT_E2E_DB_DIR`。
- `lib/services/acp_registry.dart`：Debug 构建的 `pocketbot-mock` 代理从环境变量解析可执行文件。
- `lib/services/group_chat_service.dart`：建群时从 `at_name` 列读取成员 @ 名称。
