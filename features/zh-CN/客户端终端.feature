# language: zh-CN

@integration
功能: 客户端终端
  代理通过 terminal 能力在会话目录执行命令，并读到退出码和输出。

  场景: 代理执行终端命令并读到输出
    假如 已启用隔离的 E2E 数据库
    并且 已准备确定性 Mock ACP 代理
    并且 已打开与 Mock 代理的聊天
    当 发送消息「e2e-terminal」
    那么 聊天中显示代理回复「MOCK_TERMINAL: exit=0 output=terminal-e2e released=true」
