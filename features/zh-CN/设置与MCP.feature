# language: zh-CN

@integration
功能: 设置与 MCP 服务器
  验收在设置中维护 MCP 服务器并持久化到配置。

  场景: 添加 stdio MCP 服务器
    假如 已启用隔离的 E2E 数据库
    并且 MCP 服务器列表为空
    当 用户在设置中添加名为「E2E MCP」、命令为「node」的服务器
    那么 MCP 服务器列表显示「E2E MCP」
    并且 MCP 配置中保存该服务器

  场景: 删除 MCP 服务器
    假如 已启用隔离的 E2E 数据库
    并且 MCP 配置中已有名为「E2E MCP」的服务器
    当 用户在 MCP 服务器列表中删除「E2E MCP」
    那么 MCP 服务器列表不再显示「E2E MCP」
    并且 MCP 配置中不再包含该服务器
