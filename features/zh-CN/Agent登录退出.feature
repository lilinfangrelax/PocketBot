# language: zh-CN

@integration
功能: Agent 登录退出
  已连接代理时可以从设置退出 Agent 登录。

  场景: 从设置页退出 Agent 登录
    假如 已启用隔离的 E2E 数据库
    并且 已准备确定性 Mock ACP 代理
    并且 已连接 Mock 代理
    当 用户在设置中点击「退出 Agent 登录」
    那么 界面显示「退出 Agent 登录？」
    当 用户点击「退出登录」
    那么 界面显示「已退出 Agent 登录」
