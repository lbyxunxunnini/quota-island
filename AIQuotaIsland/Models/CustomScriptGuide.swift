import Foundation

enum CustomScriptGuide {
    static let starter = """
    ({
      request: {
        url: "{{baseUrl}}/api/usage",
        method: "GET",
        headers: { Authorization: "Bearer {{apiKey}}" }
      },
      extractor: function (response) {
        return {
          isValid: true,
          remaining: response.balance,
          unit: "CNY"
        };
      }
    })
    """

    static let text = """
    请为 AIQuotaIsland 生成一份额度查询脚本，只返回完整 JavaScript 配置。
    我会另行提供查询接口与脱敏响应；如果资料不足，请先问我，不编造接口或余额。

    配置必须是用圆括号包裹的对象表达式：
    ({
      request: {
        url: "{{baseUrl}}/api/usage",
        method: "GET",
        headers: { Authorization: "Bearer {{apiKey}}" }
      },
      extractor: function(response) {
        return { isValid: true, remaining: response.balance, unit: "CNY" };
      }
    })

    请求配置：
    request.url 为 HTTP/HTTPS 地址；method 支持 GET、POST 等 HTTP 方法。
    headers 为字符串对象；body 可为 JSON 对象或字符串。
    {{baseUrl}}、{{apiKey}}、{{cookie}} 在请求发送前替换，凭据在页面单独填写。
    不把真实 Key、Token、Cookie 或个人标识写进脚本、示例和错误信息。
    请用 Authorization: "Bearer {{apiKey}}"、Cookie: "{{cookie}}" 引用凭据。
    每次查询只发送一个 request；不生成登录流程、多次请求或浏览器自动化。
    extractor 接收已解析的 JSON 响应，在独立 JavaScriptCore 中执行。
    支持系统 JavaScriptCore 的 ES2020+；没有 fetch、require、文件系统和原生桥接。
    return 的所有数值必须是有限数，0 是有效值。不能缺数据就返回0。

    基础返回字段：
    isValid：布尔值；false 时以 invalidMessage 说明失效原因。
    invalidMessage：简短错误说明，不拼接凭据或原始响应。
    remaining：真实剩余数量。可选 total、used。
    unit：tokens、CNY、USD、次、credits 等真实单位。
    planName：可选套餐名称；extra：可选简短说明。
    expiresAt：可选到期时间；resetsAt：可选重置时间。
    时间统一使用带时区的 ISO 8601 字符串，或 Unix 秒时间戳。

    单额度：
    返回原始 tokens 数量，不提前除以K、M或亿；App 自动格式化，最多两位小数。
    次数、credits 不换算成 tokens。没有 total 就省略，不编造总量或百分比。
    CNY、USD 表示金额余额，使用水缸卡片，不把累计充值当总额度。

    多周期额度：
    返回 windows 数组，按以下格式提供各个真实周期：
    windows: [{
      id: "5h",
      title: "5 小时",
      durationSeconds: 18000,
      remainingPercent: 80,
      resetsAt: "2027-01-01T12:00:00+08:00"
    }]
    可用 remaining、total、unit 代替 remainingPercent，提供实际数量。
    remainingPercent 是剩余百分比，范围0至100；不是已用百分比。
    每个窗口 id 唯一，durationSeconds 为真实周期长度。
    有 tokens 时提供原始数量。没有时间就省略，不推测重置时间。
    多周期圆环取最短周期，底部重置时间取最大周期，由App选择。
    自定义不能生成内置 ChatGPT 或重置次数；无需在脚本中处理布局。

    完成后自行核对响应字段、成功判断、单位和时间来源，并保留必要的失败判断。
    """
}
