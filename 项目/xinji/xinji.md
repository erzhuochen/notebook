# "心迹"心理健康服务系统 API 文档

**版本**: v1.0.0  
**基础URL**: `https://api.xiniji.com/api`  
**协议**: HTTPS  
**认证方式**: JWT Bearer Token

---

## 目录

1. 认证模块 (Auth)
2. 用户模块 (User)
3. 日记模块 (Diary)
4. AI分析模块 (Analysis)
5. 报告模块 (Report)
6. 订单模块 (Order)
7. 支付模块 (Payment)
8. 通用说明

---

## 1. 认证模块

### 1.1 发送验证码

**接口**: [POST /auth/send-code](vscode-file://vscode-app/usr/share/code/resources/app/out/vs/code/electron-browser/workbench/workbench.html)

**描述**: 向用户手机号发送6位数字验证码，5分钟有效

**请求头**: 无需认证

**请求体**:
{
"phone": "13800138000"
}
**请求参数**:

|参数|类型|必填|说明|
|---|---|---|---|
|phone|string|是|11位手机号|

**响应示例**:
{
  "code": 200,
  "message": "验证码已发送",
  "data": null,
  "timestamp": "2025-12-19T10:30:00Z"
}
**限流规则**:

- 同一手机号：1分钟1次，1小时5次，1天10次

**错误码**:

- `400`: 手机号格式错误
- `429`: 请求过于频繁
- `500`: 短信服务异常

### 1.2 用户登录/注册

**接口**: [POST /auth/login](vscode-file://vscode-app/usr/share/code/resources/app/out/vs/code/electron-browser/workbench/workbench.html)

**描述**: 手机号+验证码登录，新用户自动注册

**请求头**: 无需认证

**请求体**:
{
  "phone": "13800138000",
  "code": "123456"
}
**请求参数**:

|参数|类型|必填|说明|
|---|---|---|---|
|phone|string|是|11位手机号|
|code|string|是|6位验证码|

**响应示例**:
{
  "code": 200,
  "message": "登录成功",
  "data": {
    "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "expiresIn": 604800,
    "user": {
      "id": "u123456",
      "phone": "138****8000",
      "memberStatus": "FREE",
      "memberExpireTime": null,
      "registerTime": "2025-12-19T10:30:00Z"
    }
  },
  "timestamp": "2025-12-19T10:30:00Z"
}
**返回字段说明**:

| 字段                    | 类型          | 说明             |
| --------------------- | ----------- | -------------- |
| token                 | string      | JWT访问令牌        |
| expiresIn             | number      | 令牌有效期(秒)       |
| user.memberStatus     | string      | 会员状态: FREE/PRO |
| user.memberExpireTime | string/null | 会员到期时间         |

**错误码**:

- `400`: 验证码错误或已过期
- `500`: 登录失败

---

### 1.3 退出登录

**接口**: [POST /auth/logout](vscode-file://vscode-app/usr/share/code/resources/app/out/vs/code/electron-browser/workbench/workbench.html)

**描述**: 客户端删除Token即可，服务端无状态

**请求头**:
Authorization: Bearer {token}

**响应示例**:
{
  "code": 200,
  "message": "退出登录成功",
  "data": null,
  "timestamp": "2025-12-19T10:30:00Z"
}

### 1.4 刷新Token

**接口**: [POST /auth/refresh-token](vscode-file://vscode-app/usr/share/code/resources/app/out/vs/code/electron-browser/workbench/workbench.html)

**描述**: Token过期前1天可刷新，延长7天有效期

**请求头**:
Authorization: Bearer {token}

**响应示例**:
{
  "code": 200,
  "message": "Token刷新成功",
  "data": {
    "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "expiresIn": 604800
  },
  "timestamp": "2025-12-19T10:30:00Z"
}

## 2. 用户模块

### 2.1 获取用户信息

**接口**: `GET /user/profile`

**描述**: 获取当前登录用户详细信息

**请求头**:
Authorization: Bearer {token}

**响应示例**:
{
  "code": 200,
  "message": "成功",
  "data": {
    "id": "u123456",
    "phone": "138****8000",
    "memberStatus": "PRO",
    "memberExpireTime": "2026-12-19T00:00:00Z",
    "registerTime": "2025-01-01T08:00:00Z",
    "diaryCount": 128,
    "todayAiQuota": 1000,
    "usedAiQuota": 2
  },
  "timestamp": "2025-12-19T10:30:00Z"
}

**返回字段说明**:

| 字段           | 类型     | 说明                           |
| ------------ | ------ | ---------------------------- |
| diaryCount   | number | 累计日记数量                       |
| todayAiQuota | number | 今日AI分析配额(免费用户为5次，pro用户1000次) |
| usedAiQuota  | number | 今日已使用配额                      |

---

### 2.2 更新用户信息

**接口**: `PUT /user/profile`

**描述**: 更新用户基本信息(预留接口)

**请求头**:
Authorization: Bearer {token}

**请求体**:
{
  "nickname": "小明",
  "avatar": "https://oss.xiniji.com/avatar/xxx.jpg"
}

**响应示例**:
{
  "code": 200,
  "message": "更新成功",
  "data": null,
  "timestamp": "2025-12-19T10:30:00Z"
}

---

### 2.3 导出用户数据

**接口**: `POST /user/export`

**描述**: 导出用户所有数据(JSON格式)，符合《个人信息保护法》

**请求头**:
Authorization: Bearer {token}

**响应示例**:
{
  "code": 200,
  "message": "导出成功",
  "data": {
    "exportUrl": "https://oss.xiniji.com/export/u123456_20251219.zip",
    "expiresAt": "2025-12-26T10:30:00Z"
  },
  "timestamp": "2025-12-19T10:30:00Z"
}

**说明**:

- 异步处理，生成后通过链接下载
- 链接有效期7天
- 包含内容：个人信息、所有日记、AI分析结果

---

### 2.4 注销账号

**接口**: [POST /user/delete](vscode-file://vscode-app/usr/share/code/resources/app/out/vs/code/electron-browser/workbench/workbench.html)

**描述**: 永久删除账号及所有数据，不可恢复

**请求头**:
Authorization: Bearer {token}

**请求体**:
{
  "phone": "13800138000",
  "code": "123456",
  "confirmText": "我确认删除账号"
}

**响应示例**:
{
  "code": 200,
  "message": "账号已删除",
  "data": null,
  "timestamp": "2025-12-19T10:30:00Z"
}

---

## 3. 日记模块

### 3.1 创建日记

**接口**: [POST /diary/create](vscode-file://vscode-app/usr/share/code/resources/app/out/vs/code/electron-browser/workbench/workbench.html)

**描述**: 创建新日记，支持草稿

**请求头**:
Authorization: Bearer {token}

**请求体**:
{
  "title": "今天的心情",
  "content": "今天天气很好，心情也不错...",
  "isDraft": false,
  "diaryDate": "2025-12-19"
}

**请求参数**:

| 参数        | 类型      | 必填  | 说明          |
| --------- | ------- | --- | ----------- |
| title     | string  | 否   | 标题(最多50字)   |
| content   | string  | 是   | 正文(最多5000字) |
| isDraft   | boolean | 否   | 是否草稿，默认true |
| diaryDate | string  | 否   | 日记日期，默认当天   |

**响应示例**:
{
  "code": 200,
  "message": "创建成功",
  "data": {
    "id": "d123456",
    "userId": "u123456",
    "title": "今天的心情",
    "content": "今天天气很好，心情也不错...",
    "isDraft": false,
    "diaryDate": "2025-12-19",
    "createdAt": "2025-12-19T10:30:00Z",
    "updatedAt": "2025-12-19T10:30:00Z",
    "analyzed": false
  },
  "timestamp": "2025-12-19T10:30:00Z"
}

**错误码**:

- `400`: 内容为空或超长
- `401`: 未登录
- `429`: 创建频率限制(1分钟最多1条)

---

### 3.2 获取日记列表

**接口**: `GET /diary/list`

**描述**: 分页获取用户日记列表

**请求头**:
Authorization: Bearer {token}

**查询参数**:

| 参数        | 类型      | 必填  | 说明              |
| --------- | ------- | --- | --------------- |
| page      | number  | 否   | 页码，默认1          |
| pageSize  | number  | 否   | 每页数量，默认20，最大100 |
| startDate | string  | 否   | 开始日期 YYYY-MM-DD |
| endDate   | string  | 否   | 结束日期 YYYY-MM-DD |
| keyword   | string  | 否   | 关键词搜索           |

**响应示例**:
{

"code": 200,

"message": "成功",

"data": {

"total": 128,

"page": 1,

"pageSize": 20,

"list": [

{

"id": "d123456",

"title": "今天的心情",

"preview": "今天天气很好，心情也不错...",

"diaryDate": "2025-12-19",

"createdAt": "2025-12-19T10:30:00Z",

"isDraft": false,

"analyzed": true,

"emotion": {

"primary": "HAPPY",

"intensity": 0.85

}

}

]

},

"timestamp": "2025-12-19T10:30:00Z"

}

**返回字段说明**:

|字段|类型|说明|
|---|---|---|
|preview|string|内容预览(前100字)|
|analyzed|boolean|是否已AI分析|
|emotion.primary|string|主导情绪|
|emotion.intensity|number|情绪强度 0-1|

---

### 3.3 获取日记详情

**接口**: `GET /diary/{id}`

**描述**: 获取单条日记完整内容

**请求头**:
Authorization: Bearer {token}

**路径参数**:

|参数|类型|说明|
|---|---|---|
|id|string|日记ID|

**响应示例**:
{
  "code": 200,
  "message": "成功",
  "data": {
    "id": "d123456",
    "userId": "u123456",
    "title": "今天的心情",
    "content": "今天天气很好，心情也不错...",
    "isDraft": false,
    "diaryDate": "2025-12-19",
    "createdAt": "2025-12-19T10:30:00Z",
    "updatedAt": "2025-12-19T10:30:00Z",
    "analyzed": true,
    "analysisId": "a123456"
  },
  "timestamp": "2025-12-19T10:30:00Z"
}

**错误码**:

- `404`: 日记不存在
- `403`: 无权访问(非本人日记)

---

### 3.4 更新日记

**接口**: `PUT /diary/{id}`

**描述**: 更新日记内容

**请求头**:
Authorization: Bearer {token}

**请求体**:
{
  "title": "今天的心情(修改)",
  "content": "更新后的内容...",
  "isDraft": false
}

**响应示例**:
{
  "code": 200,
  "message": "更新成功",
  "data": {
    "id": "d123456",
    "updatedAt": "2025-12-19T11:00:00Z"
  },
  "timestamp": "2025-12-19T11:00:00Z"
}

---

### 3.5 删除日记

**接口**: `DELETE /diary/{id}`

**描述**: 删除日记(软删除)

**请求头**:
Authorization: Bearer {token}

**响应示例**:
{
  "code": 200,
  "message": "删除成功",
  "data": null,
  "timestamp": "2025-12-19T10:30:00Z"
}

---

## 4. AI分析模块

### 4.1 提交AI分析

**接口**: `POST /analysis/submit`

**描述**: 提交日记进行AI情绪分析

**请求头**:
Authorization: Bearer {token}

**请求体**:
{
  "diaryId": "d123456"
}

**响应示例**:
{
  "code": 200,
  "message": "分析中，请稍候",
  "data": {
    "analysisId": "a123456",
    "status": "PROCESSING"
  },
  "timestamp": "2025-12-19T10:30:00Z"
}

**限流规则**:

- 免费用户：每日5次
- Pro用户：每日1000次
- 同一日记重复分析间隔：2分钟

**错误码**:

- `403`: 超出配额限制
- `404`: 日记不存在
- `429`: 分析频率过快

---

### 4.2 获取分析结果

**接口**: `GET /analysis/{id}`

**描述**: 获取AI分析详细结果

**请求头**:
Authorization: Bearer {token}

**路径参数**:

|参数|类型|说明|
|---|---|---|
|id|string|分析ID|

**响应示例**:
{
  "code": 200,
  "message": "成功",
  "data": {
    "id": "a123456",
    "diaryId": "d123456",
    "status": "COMPLETED",
    "emotions": {
      "HAPPY": 0.75,
      "SAD": 0.15,
      "ANGRY": 0.05,
      "FEAR": 0.02,
      "SURPRISE": 0.01,
      "DISGUST": 0.01,
      "NEUTRAL": 0.01,
      "ANXIOUS": 0.00
    },
    "primaryEmotion": "HAPPY",
    "emotionIntensity": 0.75,
    "keywords": ["天气", "心情", "不错", "开心"],
    "cognitiveDistortions": [
      {
        "type": "NONE",
        "description": "未检测到明显认知偏差"
      }
    ],
    "suggestions": [
      "您的情绪状态良好，建议保持当前积极心态",
      "可以尝试记录让你快乐的具体事件"
    ],
    "riskLevel": "LOW",
    "analyzedAt": "2025-12-19T10:31:00Z"
  },
  "timestamp": "2025-12-19T10:31:00Z"
}

**返回字段说明**:

|字段|类型|说明|
|---|---|---|
|emotions|object|8类情绪强度分布|
|primaryEmotion|string|主导情绪类型|
|emotionIntensity|number|主导情绪强度 0-1|
|keywords|array|关键词列表(最多10个)|
|cognitiveDistortions|array|认知偏差列表|
|suggestions|array|AI调节建议|
|riskLevel|string|风险等级: LOW/MEDIUM/HIGH|

**认知偏差类型**:

- `CATASTROPHIZING`: 灾难化思维
- `BLACK_WHITE`: 非黑即白
- `OVERGENERALIZATION`: 过度概括
- `MIND_READING`: 读心术
- `EMOTIONAL_REASONING`: 情绪推理
- `SHOULD_STATEMENTS`: 应该句式
- `LABELING`: 贴标签
- `PERSONALIZATION`: 个人化
- `MENTAL_FILTER`: 心理过滤
- `DISQUALIFYING_POSITIVE`: 否定正面

**风险等级触发规则**:

- `LOW`: 正常情绪状态
- `MEDIUM`: 连续3天负面情绪强度>0.7
- `HIGH`: 连续5天负面情绪强度>0.8 或 检测到自杀意念关键词

---

## 5. 报告模块

### 5.1 获取周报数据

**接口**: `GET /report/weekly`

**描述**: 获取指定周的情绪周报数据

**请求头**:
Authorization: Bearer {token}

**查询参数**:

|参数|类型|必填|说明|
|---|---|---|---|
|startDate|string|否|周开始日期 YYYY-MM-DD，默认本周一|

**响应示例**:
{
  "code": 200,
  "message": "成功",
  "data": {
    "weekStart": "2025-12-15",
    "weekEnd": "2025-12-21",
    "diaryCount": 7,
    "analyzedCount": 7,
    "emotionTrend": [
      {
        "date": "2025-12-15",
        "emotion": "HAPPY",
        "intensity": 0.75
      },
      {
        "date": "2025-12-16",
        "emotion": "NEUTRAL",
        "intensity": 0.50
      }
    ],
    "emotionDistribution": {
      "HAPPY": 3,
      "SAD": 1,
      "ANXIOUS": 2,
      "NEUTRAL": 1
    },
    "averageIntensity": 0.68,
    "mostFrequentEmotion": "HAPPY",
    "keywords": ["工作", "压力", "放松", "周末"],
    "summary": "本周整体情绪状态良好，周中有轻微焦虑..."
  },
  "timestamp": "2025-12-19T10:30:00Z"
}

**返回字段说明**:

|字段|类型|说明|
|---|---|---|
|emotionTrend|array|每日情绪折线数据(ECharts)|
|emotionDistribution|object|情绪出现次数统计|
|averageIntensity|number|平均情绪强度|
|mostFrequentEmotion|string|出现最多的情绪|

---

### 5.2 获取深度洞察报告

**接口**: `GET /report/insights`

**描述**: Pro用户专属深度分析报告

**请求头**:
Authorization: Bearer {token}

**查询参数**:

|参数|类型|必填|说明|
|---|---|---|---|
|timeRange|string|否|时间范围: week/month/all，默认month|

**响应示例**:
{
  "code": 200,
  "message": "成功",
  "data": {
    "timeRange": "month",
    "startDate": "2025-11-19",
    "endDate": "2025-12-19",
    "insights": [
      {
        "type": "EMOTION_PATTERN",
        "title": "情绪波动规律",
        "content": "您的情绪在周一至周三较为稳定，周四周五易出现焦虑情绪",
        "confidence": 0.85
      },
      {
        "type": "COGNITIVE_PATTERN",
        "title": "认知偏差倾向",
        "content": "检测到您有轻微的'应该句式'认知偏差，建议...",
        "confidence": 0.72
      }
    ],
    "growthPlan": [
      "建议每天进行10分钟正念冥想",
      "尝试记录3件积极事件",
      "周四周五注意压力管理"
    ],
    "emotionForecast": {
      "nextWeekRisk": "MEDIUM",
      "triggers": ["工作deadline", "人际关系"]
    },
    "mindfulnessSuggestions": [
      {
        "title": "呼吸冥想",
        "duration": "10分钟",
        "url": "/mindfulness/breathing"
      }
    ]
  },
  "timestamp": "2025-12-19T10:30:00Z"
}

**洞察类型**:

- `EMOTION_PATTERN`: 情绪规律
- `COGNITIVE_PATTERN`: 认知模式
- `TRIGGER_ANALYSIS`: 触发因素
- `GROWTH_TRAJECTORY`: 成长轨迹

**权限校验**:

- 免费用户访问返回 `403 Forbidden`

---

## 6. 订单模块

### 6.1 创建订单

**接口**: [POST /order/create](vscode-file://vscode-app/usr/share/code/resources/app/out/vs/code/electron-browser/workbench/workbench.html)

**描述**: 创建会员订阅订单

**请求头**:
Authorization: Bearer {token}

**请求体**:
{
  "planType": "MONTHLY",
  "autoRenew": false
}

**请求参数**:

|参数|类型|必填|说明|
|---|---|---|---|
|planType|string|是|套餐类型: MONTHLY/QUARTERLY/ANNUAL|
|autoRenew|boolean|否|是否自动续费，默认false|

**套餐价格**:

- `MONTHLY`: 0.029元/月
- `QUARTERLY`: 0.078元/季
- `ANNUAL`: 0.288元/年

**响应示例**:
{
  "code": 200,
  "message": "订单创建成功",
  "data": {
    "orderId": "o202512191030001",
    "userId": "u123456",
    "planType": "MONTHLY",
    "amount": 0.029,
    "status": "PENDING",
    "autoRenew": false,
    "createdAt": "2025-12-19T10:30:00Z",
    "expireAt": "2025-12-19T10:45:00Z"
  },
  "timestamp": "2025-12-19T10:30:00Z"
}

**订单状态**:

- `PENDING`: 待支付
- `PAID`: 已支付
- `CANCELLED`: 已取消
- `REFUNDED`: 已退款
- `EXPIRED`: 已过期

**订单有效期**: 15分钟，超时自动取消

---

### 6.2 获取订单列表

**接口**: `GET /order/list`

**描述**: 获取用户订单列表

**请求头**:
Authorization: Bearer {token}

**查询参数**:

|参数|类型|必填|说明|
|---|---|---|---|
|page|number|否|页码，默认1|
|pageSize|number|否|每页数量，默认10|
|status|string|否|订单状态筛选|

**响应示例**:
{
  "code": 200,
  "message": "成功",
  "data": {
    "total": 5,
    "page": 1,
    "pageSize": 10,
    "list": [
      {
        "orderId": "o202512191030001",
        "planType": "MONTHLY",
        "amount": 0.029,
        "status": "PAID",
        "createdAt": "2025-12-19T10:30:00Z",
        "paidAt": "2025-12-19T10:32:00Z"
      }
    ]
  },
  "timestamp": "2025-12-19T10:30:00Z"
}

---

### 6.3 获取订单详情

**接口**: `GET /order/{orderId}`

**描述**: 获取订单详细信息

**请求头**:
Authorization: Bearer {token}

**响应示例**:

{
  "code": 200,
  "message": "成功",
  "data": {
    "orderId": "o202512191030001",
    "userId": "u123456",
    "planType": "MONTHLY",
    "amount": 0.029,
    "status": "PAID",
    "autoRenew": false,
    "createdAt": "2025-12-19T10:30:00Z",
    "paidAt": "2025-12-19T10:32:00Z",
    "paymentMethod": "WECHAT",
    "transactionId": "wx20251219103200001"
  },
  "timestamp": "2025-12-19T10:30:00Z"
} 

---

### 6.4 取消订单

**接口**: `POST /order/{orderId}/cancel`

**描述**: 取消待支付订单

**请求头**:
Authorization: Bearer {token}

**响应示例**:
{
  "code": 200,
  "message": "订单已取消",
  "data": null,
  "timestamp": "2025-12-19T10:30:00Z"
}

**错误码**:

- `400`: 订单状态不允许取消(已支付/已取消)

---

## 7. 支付模块

### 7.1 微信支付下单

**接口**: `POST /payment/wechat/prepay`

**描述**: 调起微信支付

**请求头**:
Authorization: Bearer {token}

**请求体**:
{
  "orderId": "o202512191030001"
}

**响应示例**:
{
  "code": 200,
  "message": "成功",
  "data": {
    "prepayId": "wx191030000100001",
    "appId": "wxxxxxxxxxxx",
    "timeStamp": "1734595800",
    "nonceStr": "5K8264ILTKCH16CQ2502SI8ZNMTM67VS",
    "package": "prepay_id=wx191030000100001",
    "signType": "RSA",
    "paySign": "xxxxxxxxxxxxx"
  },
  "timestamp": "2025-12-19T10:30:00Z"
}

**前端调用示例**:
wx.requestPayment({
  timeStamp: data.timeStamp,
  nonceStr: data.nonceStr,
  package: data.package,
  signType: data.signType,
  paySign: data.paySign,
  success: () => { /* 支付成功 */ },
  fail: () => { /* 支付失败 */ }
})

---

### 7.2 微信支付回调

**接口**: `POST /payment/wechat/notify`

**描述**: 微信支付异步通知接口(微信服务器调用)

**请求头**:
Content-Type: application/json

**请求体**: (微信签名加密数据)

**响应格式**:
{
  "code": "SUCCESS",
  "message": "成功"
}

**业务逻辑**:

1. 验证签名
2. 检查订单状态(幂等性)
3. 更新订单为已支付
4. 激活用户会员权限
5. 返回成功响应

---

### 7.3 查询支付状态

**接口**: [GET /payment/order/{orderId}/status](vscode-file://vscode-app/usr/share/code/resources/app/out/vs/code/electron-browser/workbench/workbench.html)

**描述**: 主动查询订单支付状态

**请求头**:
Authorization: Bearer {token}

**响应示例**:
{
  "code": 200,
  "message": "成功",
  "data": {
    "orderId": "o202512191030001",
    "paymentStatus": "PAID",
    "paidAt": "2025-12-19T10:32:00Z",
    "transactionId": "wx20251219103200001"
  },
  "timestamp": "2025-12-19T10:33:00Z"
}

**支付状态**:

- `UNPAID`: 未支付
- `PAID`: 已支付
- `REFUNDING`: 退款中
- `REFUNDED`: 已退款

---
## 8.定时任务

### 1. **ScheduledTasks.java** - 定时任务实现类

包含7个定时任务：

- 📊 **周报生成任务** - 每周一凌晨2点，生成上周所有用户周报
- 👤 **会员到期检查** - 每日凌晨1点，检查即将到期会员并通知
- 🎯 **AI配额重置** - 每日凌晨0点，重置免费用户每日5次配额，pro用户1000次配额
- 📦 **订单超时取消** - 每5分钟，取消15分钟未支付订单
- 💾 **数据备份任务** - 每日凌晨3点，备份MySQL/MongoDB到OSS
- 🗑️ **日志清理任务** - 每周日凌晨4点，清理30天前日志
- 🚨 **高风险监控** - 每小时，检测连续负面情绪用户并预警

### 2. **ScheduleConfig.java** - 定时任务配置类

- 配置线程池（10个核心线程）
- 优雅关闭策略
- 拒绝策略配置

### 3. **API_SCHEDULE.md** - 定时任务文档

详细说明每个任务的：

- 执行时间和Cron表达式
- 功能描述和执行逻辑
- Redis/数据库操作细节
- 日志输出示例
- 监控和手动触发接口

### 核心特性

1. **任务隔离** - 单个任务失败不影响其他任务
2. **日志完整** - 每个任务记录开始/结束/异常日志
3. **性能优化** - 批量处理，避免阻塞主线程
4. **灵活配置** - 支持动态开关任务
5. **监控友好** - 清晰的执行统计和错误追踪

### 执行时间表
00:00 - AI配额重置
01:00 - 会员到期检查
02:00 - 周报生成（仅周一）
03:00 - 数据备份
04:00 - 日志清理（仅周日）
每5分钟 - 订单超时取消

## 9. 通用说明

### 9.1 统一响应格式

所有接口响应均遵循以下格式：
{
  "code": 200,
  "message": "成功",
  "data": {},
  "timestamp": "2025-12-19T10:30:00Z"
}

**字段说明**:

|字段|类型|说明|
|---|---|---|
|code|number|业务状态码|
|message|string|响应消息|
|data|any|响应数据|
|timestamp|string|服务器时间(ISO 8601)|

---

### 9.2 状态码说明

**成功状态码**:

- `200`: 请求成功

**客户端错误 (4xx)**:

- `400`: 请求参数错误
- `401`: 未授权(Token缺失/失效)
- `403`: 无权限(非Pro用户/非本人资源)
- `404`: 资源不存在
- `429`: 请求过于频繁

**服务端错误 (5xx)**:

- `500`: 服务器内部错误
- `503`: 服务不可用(AI服务异常)

---

### 9.3 认证机制

**JWT Token格式**:
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...

**Token有效期**: 7天

**刷新策略**: 过期前1天可调用 [/auth/refresh-token](vscode-file://vscode-app/usr/share/code/resources/app/out/vs/code/electron-browser/workbench/workbench.html) 刷新

**失效处理**:

1. Token过期返回 `401`
2. 前端跳转登录页
3. 用户重新登录获取新Token

---

### 9.4 分页规范

**查询参数**:
GET /api/xxx?page=1&pageSize=20

**响应格式**:
{
  "code": 200,
  "data": {
    "total": 128,
    "page": 1,
    "pageSize": 20,
    "list": []
  }
}

**默认值**:

- `page`: 1
- `pageSize`: 20
- `maxPageSize`: 100

---

### 9.5 日期时间格式

**ISO 8601标准**:

- 日期: `YYYY-MM-DD` (如 `2025-12-19`)
- 日期时间: `YYYY-MM-DDTHH:mm:ssZ` (如 `2025-12-19T10:30:00Z`)
- 时区: UTC(0时区)

**时区转换**: 前端根据用户时区展示本地时间

---

### 9.6 数据加密

**传输加密**:

- 全站HTTPS(TLS 1.2+)

**存储加密**:

- 日记正文: AES-256-CBC加密
- 手机号: 脱敏存储(138****8000)
- 密码: BCrypt哈希(不可逆)

---

### 9.7 限流策略

**全局限流**:

- 单用户: 100次/分钟

**接口级限流**:

|接口|限制|
|---|---|
|发送验证码|1次/分钟，5次/小时，10次/天|
|创建日记|1次/分钟|
|AI分析(免费)|5次/天|
|AI分析(Pro)|无限制|

**超限响应**:
{
  "code": 429,
  "message": "请求过于频繁，请1分钟后重试",
  "data": {
    "retryAfter": 60
  }
}

---

### 9.8 错误处理

**错误响应示例**:
{
  "code": 400,
  "message": "手机号格式错误",
  "data": {
    "field": "phone",
    "value": "123",
    "constraint": "must be 11 digits"
  },
  "timestamp": "2025-12-19T10:30:00Z"
}

**前端处理建议**:

1. 显示 [message](vscode-file://vscode-app/usr/share/code/resources/app/out/vs/code/electron-browser/workbench/workbench.html) 给用户
2. 记录详细错误到日志
3. `401` 跳转登录
4. `500` 提示"服务异常，请稍后重试"

---

### 9.9 数据合规

**个人信息保护**:

- 最小化收集原则(仅收集手机号)
- 用户可导出/删除所有数据
- 日记内容端到端加密

**数据保留期**:

- 活跃用户: 永久保留
- 注销用户: 立即删除
- 日志数据: 30天

**隐私政策**: `/legal/privacy`  
**用户协议**: `/legal/terms`

---

### 9.10 版本管理

**当前版本**: v1.0.0

**版本前缀**: `/api` (无版本号，后续迭代为 `/api/v2`)

**向后兼容**: 重大变更提前6个月通知

---

## 附录

### A. 情绪类型枚举
enum EmotionType {
  HAPPY = "快乐",
  SAD = "悲伤",
  ANGRY = "愤怒",
  FEAR = "恐惧",
  SURPRISE = "惊讶",
  DISGUST = "厌恶",
  NEUTRAL = "平静",
  ANXIOUS = "焦虑"
}

### B. 会员套餐类型
enum PlanType {
  MONTHLY = "月卡",    // 0.029元/月
  QUARTERLY = "季卡",  // 0.078元/季
  ANNUAL = "年卡"      // 0.288元/年
}

### C. 订单状态
enum OrderStatus {
  PENDING = "待支付",
  PAID = "已支付",
  CANCELLED = "已取消",
  REFUNDED = "已退款",
  EXPIRED = "已过期"
}

### D. 风险等级
enum RiskLevel {
  LOW = "低风险",      // 正常
  MEDIUM = "中风险",   // 需关注
  HIGH = "高风险"      // 紧急干预
}
