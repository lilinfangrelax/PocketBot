# language: zh-CN

@integration
功能: 群聊 @ 路由
  验收群聊仅把被 @ 的 AI 联系人路由到其代理，并记录代理回复。

  场景: 被 @ 的 AI 联系人回复群消息
    假如 已启用隔离的 E2E 数据库
    并且 已准备确定性 Mock ACP 代理
    并且 群聊「E2E群」包含 AI 联系人「E2E助手」
    当 群成员发送「@e2e_helper e2e-group」
    那么 群聊中出现来自「E2E助手」的回复
    并且 回复内容包含「MOCK_AGENT_OK」

  场景: 未被 @ 的 AI 联系人不回复
    假如 已启用隔离的 E2E 数据库
    并且 已准备确定性 Mock ACP 代理
    并且 群聊「E2E群」包含 AI 联系人「E2E助手」
    当 群成员发送「e2e-silent」
    那么 群聊中不出现来自「E2E助手」的新回复
