# language: zh-CN

@integration
功能: 本机 ACP 连接与聊天
  使用确定性 Mock ACP 代理验收本机代理启动、会话建立与流式回复。

  场景: 连接本机代理并收到确定性回复
    假如 已启用隔离的 E2E 数据库
    并且 已准备确定性 Mock ACP 代理
    当 在发现页启动本机 Mock 代理
    那么 发现页显示已连接
    并且 可以进入与该代理的聊天
    当 发送消息「e2e-ping」
    那么 聊天中显示代理回复「MOCK_AGENT_OK: e2e-ping」
