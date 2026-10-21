# language: zh-CN

@integration
功能: 通讯录与 AI 联系人
  验收 AI 联系人的创建、代理绑定以及在通讯录中打开聊天。

  场景: 创建 AI 联系人并绑定 Mock 代理
    假如 已启用隔离的 E2E 数据库
    并且 已准备确定性 Mock ACP 代理
    当 创建名为「E2E助手」的 AI 联系人并绑定 Mock 代理
    那么 通讯录中可见联系人「E2E助手」

  场景: 从通讯录打开 AI 联系人聊天
    假如 已启用隔离的 E2E 数据库
    并且 已准备确定性 Mock ACP 代理
    并且 已创建名为「E2E助手」并绑定 Mock 代理的 AI 联系人
    当 在通讯录中点按联系人「E2E助手」并打开消息
    并且 发送消息「e2e-contact」
    那么 聊天中显示代理回复「MOCK_AGENT_OK: e2e-contact」
