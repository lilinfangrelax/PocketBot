# PocketBot E2E 验收

Windows 桌面端采用混合验收：

- `@uia` Feature 由 Teshi 的 winapp bridge 驱动真实窗口，验收应用外壳与底部导航。
- `@integration` Feature 由 Flutter `integration_test` 驱动真实应用逻辑与界面，使用确定性 Mock ACP 代理，不访问网络或真实代理。

Feature 位于 `features/zh-CN/`，步骤文本不包含选择器。

## 覆盖范围

| Feature | 标签 | 验收内容 |
| --- | --- | --- |
| 启动与底部导航 | `@uia` | 启动默认消息页、四个底部标签切换 |
| 本机ACP连接与聊天 | `@integration` | 本机代理启动、会话建立、流式回复 |
| 通讯录与AI联系人 | `@integration` | AI 联系人创建、代理绑定、从通讯录打开聊天 |
| 群聊@路由 | `@integration` | 被 @ 的 AI 联系人回复、未 @ 时不触发 |

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

运行前请关闭已在运行的 PocketBot，避免它占用 SQLite 数据库文件。测试会备份并在结束时恢复用户的会话、已保存连接与代理选择（Flutter secure storage 中的 `chat_sessions`、`gateways_config`、`last_connected_gateway`，以及 SharedPreferences 中的 `acp_agent_id` / `acp_agent_label`）；恢复前会先卸载界面并等待防抖写入落盘，避免与退出保存竞态。测试中途强制结束进程时，这些数据可能停留在测试状态，请重新运行一次或手动恢复。

### Mock ACP 代理

`tool/mock_acp_agent.dart` 通过 stdin/stdout 收发 NDJSON JSON-RPC，实现：

- `initialize`（protocolVersion 1，无认证方式）
- `session/new`
- `session/prompt`：分块推送 `agent_message_chunk`，内容为 `MOCK_AGENT_OK: <提示文本>`，随后返回 `stopReason: end_turn`

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

- `lib/widgets/fluent_tab_bar.dart`、`lib/screens/wechat_session_list.dart`：底部标签与会话行补充 `onTap`/`label`，使 UIA InvokePattern 能够触发导航。
- `lib/screens/chat_screen.dart`：输入框增加 `chat-input` Key，供集成测试定位。
- `lib/services/database_service.dart`：Windows/Linux 使用 `sqflite_common_ffi`，Debug 构建支持 `POCKETBOT_E2E_DB_DIR`。
- `lib/services/acp_registry.dart`：Debug 构建的 `pocketbot-mock` 代理从环境变量解析可执行文件。
- `lib/services/group_chat_service.dart`：建群时从 `at_name` 列读取成员 @ 名称。
