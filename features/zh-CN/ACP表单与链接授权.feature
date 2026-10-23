# language: zh-CN

@integration
功能: ACP 表单与链接授权
  代理发起的表单由用户填写后回传，外部链接需授权后才打开。

  场景: 填写 elicitation 表单并回传
    假如 已启用隔离的 E2E 数据库
    并且 已准备确定性 Mock ACP 代理
    并且 已打开与 Mock 代理的聊天
    当 发送消息「e2e-elicit-form」
    那么 界面显示「需要你的输入」
    并且 界面显示「请填写 E2E 表单」
    并且 界面显示「名称 *」
    当 用户在名称中填写「pocketbot」并点击「提交」
    那么 聊天中显示代理回复「MOCK_ELICIT: accept pocketbot|3000|true|balanced」

  场景: 授权外部链接后显示完成通知
    假如 已启用隔离的 E2E 数据库
    并且 已准备确定性 Mock ACP 代理
    并且 已打开与 Mock 代理的聊天
    当 发送消息「e2e-elicit-url」
    那么 界面显示「需要你的授权」
    并且 界面显示「目标网站：example.com」
    并且 界面显示「https://example.com/authorize」
    当 用户点击「打开链接」
    那么 聊天中显示代理回复「MOCK_ELICIT_URL: accept」
    并且 界面显示「外部授权流程已完成。」
