# language: zh-CN

@integration
功能: SSH 远程连接
  验收 SSH 连接表单在缺少凭据时阻止登录。真实主机和远程 Agent 见 `@real` 的「真实远程 Agent」，由 tool/e2e_real_ssh.ps1 读取仓库根目录 .env 后执行。

  场景: 缺少密码或私钥时提示
    假如 应用已打开「发现」页
    当 用户填写主机「example.invalid」和用户名「tester」但不填密码或私钥
    并且 用户点击「保存并登录」
    那么 界面提示「请填写 SSH 密码或私钥」
