# language: zh-CN

@real
功能: 真实远程 Agent
  用仓库根目录 .env 中的 SSH 主机登录，并让远程 Cursor agent 完成一轮对话。

  场景: 真实 SSH 主机上收到远程 agent 回复
    假如 已在 .env 中配置真实 SSH 主机和私钥
    当 用户使用该主机保存并登录
    并且 主机在线后选择目录并启动 Agent
    并且 发送要求只回复 REAL_AGENT_OK 的消息
    那么 聊天中显示用户消息和远程 agent 回复「REAL_AGENT_OK」
    并且 回复生成结束
