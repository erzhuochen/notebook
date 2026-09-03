# SSE (Server-Sent Events)

## 概述

### 是什么

SSE 是 HTML5 标准中的一种**服务器向浏览器单向推送数据**的技术。客户端发起一次普通 HTTP 请求后，服务器保持连接不关闭，持续往这个连接里写数据，浏览器边接收边处理。

一句话概括：**基于 HTTP 的长连接单向推送**。

> 这里的“长连接”指 HTTP 的 TCP 连接复用，与 SSE 的推送能力是两个不同层面的概念，详见 [HTTP-连接管理](../HTTP/notes.md)。

### 解决什么问题

传统 HTTP 是"请求-响应"模式，服务器无法主动通知客户端。在 SSE 出现前后的几种方案对比：

| 方案 | 原理 | 问题 |
|------|------|------|
| 轮询 (Polling) | 客户端定时发请求 | 浪费带宽，实时性差 |
| 长轮询 (Long Polling) | 服务器 hold 住请求直到有数据 | 每次推送都要重建连接 |
| **SSE** | 一次连接，持续推送 | 只能服务器 → 客户端 |
| WebSocket | 全双工双向通信 | 协议更复杂，需额外基建 |

### 适用场景

- **AI 流式输出**（ChatGPT / Claude 的打字机效果，OpenAI 兼容接口即基于 SSE）
- 实时通知、消息提醒
- 后台任务进度条
- 股票行情、监控大盘等只读数据流

## 核心概念

### 数据格式

SSE 的本质是一个 `Content-Type: text/event-stream` 的 HTTP 响应，响应体是纯文本，按约定格式分块：

```
data: 第一条消息

event: update
data: {"count": 42}

id: 100
retry: 3000
data: 带 id 的消息

```

四个字段：

| 字段 | 含义 |
|------|------|
| `data:` | 消息内容，可写多行，浏览器会用 `\n` 拼接成一个字符串 |
| `event:` | 自定义事件名，缺省为 `message` |
| `id:` | 消息 ID，浏览器自动记录，断线重连时通过 `Last-Event-ID` 请求头回传 |
| `retry:` | 断线后的重连间隔，单位毫秒 |

**关键规则：两个连续换行 `\n\n` 表示一条消息结束。** 这就是 SSE 全部的分帧机制。

此外，以冒号开头的行（如 `: ping`）是注释，会被浏览器忽略，常用来做保活心跳，防止中间代理因超时掐断空闲连接。

### 工作原理

1. 浏览器发起普通 GET 请求，携带 `Accept: text/event-stream`
2. 服务器返回 200，响应头声明 `text/event-stream`，**且不发送 `Content-Length`**，改用 `Transfer-Encoding: chunked`（HTTP/1.1）让响应体保持开放
3. 服务器每次 `write()` 都是往 TCP 流里追加一个 chunk。浏览器的 `EventSource` 内部维护一个解析器，**扫描到 `\n\n` 就切出一条完整消息**，触发对应事件回调
4. 连接断开后，浏览器等待 `retry` 毫秒自动重发请求，并带上 `Last-Event-ID: <最后收到的 id>`，服务端据此实现续传

自动重连与断点续传由浏览器原生提供，这是 SSE 相比手写 fetch 流最省事的地方。

## 基础使用

### 服务端（Node.js / Express）

```javascript
app.get('/events', (req, res) => {
  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive'
  });

  // 支持断点续传：客户端重连时会带上这个头
  const lastId = Number(req.headers['last-event-id'] || 0);
  let count = lastId;

  const timer = setInterval(() => {
    res.write(`id: ${++count}\n`);
    res.write(`data: ${JSON.stringify({ time: Date.now() })}\n\n`);
  }, 1000);

  // 客户端断开时务必清理，否则定时器泄漏
  req.on('close', () => clearInterval(timer));
});
```

### 服务端（Java / Spring Boot）

Spring 提供了 `SseEmitter` 封装：

```java
@GetMapping(value = "/events", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
public SseEmitter events() {
    SseEmitter emitter = new SseEmitter(0L); // 0 表示不超时
    ScheduledExecutorService executor = Executors.newSingleThreadScheduledExecutor();

    executor.scheduleAtFixedRate(() -> {
        try {
            emitter.send(SseEmitter.event()
                    .id(String.valueOf(System.currentTimeMillis()))
                    .name("update")
                    .data(Map.of("time", System.currentTimeMillis())));
        } catch (IOException e) {
            emitter.completeWithError(e);
        }
    }, 0, 1, TimeUnit.SECONDS);

    emitter.onCompletion(executor::shutdown);
    emitter.onTimeout(executor::shutdown);
    return emitter;
}
```

### 客户端

```javascript
const es = new EventSource('/events');

// 默认事件（服务端未指定 event: 时）
es.onmessage = (e) => {
  console.log(JSON.parse(e.data));
};

// 自定义事件（对应服务端的 event: update）
es.addEventListener('update', (e) => {
  console.log('update:', e.data);
});

es.onerror = (err) => {
  // 注意：浏览器会自动重连，这里通常不需要手动重建连接
  console.error('连接异常', err);
};

// 主动关闭，关闭后不会自动重连
es.close();
```

`EventSource` 的 `readyState` 有三个值：`0 CONNECTING`、`1 OPEN`、`2 CLOSED`。

## [进阶] 深入理解

### 为什么响应不能被缓冲

SSE 依赖数据"边产生边到达"。如果链路上任何一环做了缓冲，消息就会堆积到缓冲区满或连接结束才一次性吐出，实时性荡然无存。常见的坑：

- **Nginx 反向代理**：默认开启 `proxy_buffering`，必须关闭

  ```nginx
  location /events {
      proxy_pass http://backend;
      proxy_buffering off;
      proxy_cache off;
      proxy_read_timeout 24h;   # 默认 60s 会掐断长连接
      proxy_set_header Connection '';
      proxy_http_version 1.1;
  }
  ```

- **gzip 压缩**：压缩算法本身有缓冲窗口，需配合 flush 策略，或对该路由禁用压缩
- **应用层框架**：部分框架默认缓冲响应体，需显式调用 flush

### 连接数限制

HTTP/1.1 下浏览器对**同一域名的并发连接数限制为 6 个**。每个 SSE 连接会长期占用一个，用户开几个标签页就把配额吃光，后续普通请求全部排队阻塞。

解决办法：

- 升级到 **HTTP/2**，多路复用让所有请求共享一个 TCP 连接，上限提升到 100+（这是最推荐的做法）
- 使用 `SharedWorker` 或 `BroadcastChannel`，让多个标签页共用一条 SSE 连接

### EventSource 不支持自定义请求头

原生 `EventSource` 无法设置 `Authorization` 等请求头，这是它最常被吐槽的限制。三种绕法：

1. 把 token 放到 URL query 里（有泄漏到日志的风险）
2. 依赖 Cookie 携带凭证（需设置 `withCredentials: true`，并处理跨域）
3. 用 `fetch` + `ReadableStream` 手写解析，代价是自动重连要自己实现

第三种方式的骨架：

```javascript
const res = await fetch('/events', {
  headers: { Authorization: `Bearer ${token}` }
});

const reader = res.body.getReader();
const decoder = new TextDecoder();
let buffer = '';

while (true) {
  const { done, value } = await reader.read();
  if (done) break;

  buffer += decoder.decode(value, { stream: true });

  // 按 \n\n 切分完整消息，最后一段可能不完整，留在 buffer 里
  const parts = buffer.split('\n\n');
  buffer = parts.pop();

  for (const part of parts) {
    const data = part
      .split('\n')
      .filter(line => line.startsWith('data:'))
      .map(line => line.slice(5).trim())
      .join('\n');
    console.log(data);
  }
}
```

注意 `buffer = parts.pop()` 这一步：网络分片不保证和消息边界对齐，一条消息可能被拆到两次 `read()` 里，所以尾部残片必须留到下一轮拼接。

## [进阶] 最佳实践

### 生产环境注意事项

- **心跳保活**：每 15~30 秒发一条注释行 `: ping\n\n`，防止代理或负载均衡因空闲超时断开
- **清理资源**：服务端务必监听连接关闭事件，释放定时器、数据库游标、订阅等资源，否则连接数上去后会内存泄漏
- **设置 `retry`**：显式告知客户端重连间隔，避免服务重启时大量客户端同时重连造成雪崩；理想做法是配合随机抖动
- **鉴权超时**：长连接期间 token 可能过期，需要设计续期或主动断开重连的策略

### 常见坑点

| 现象 | 原因 |
|------|------|
| 消息延迟几十秒才一起到达 | 代理或 gzip 缓冲，需关闭 `proxy_buffering` |
| 连接每 60 秒断一次 | Nginx `proxy_read_timeout` 默认值太小 |
| 多标签页后请求全部卡住 | HTTP/1.1 的 6 连接限制被占满 |
| 前端收不到自定义事件 | 用了 `onmessage`，但服务端发的是 `event: xxx`，需改用 `addEventListener` |
| 服务端 CPU 持续上升 | 客户端断开后未清理定时器 |

### 与 WebSocket 的选型

| 维度 | SSE | WebSocket |
|------|-----|-----------|
| 通信方向 | 单向（服务器 → 客户端） | 全双工 |
| 协议 | 标准 HTTP | 独立协议，需 `Upgrade` 握手 |
| 数据类型 | 仅文本（二进制需 Base64） | 文本 + 二进制 |
| 自动重连 | 浏览器原生支持 | 需自行实现 |
| 代理/防火墙穿透 | 天然友好 | 部分环境需额外配置 |
| 实现复杂度 | 低 | 中 |

**选型结论**：需要高频双向交互（聊天室、协同编辑、多人游戏）选 WebSocket；只是服务器单向推送（通知、进度、流式输出）选 SSE，实现成本低得多。

## 参考资源

- [WebSocket-协议与实现原理](../websocket/notes.md) - 双向通信方案对比
- [HTML Living Standard - Server-Sent Events](https://html.spec.whatwg.org/multipage/server-sent-events.html) - 官方规范
- [MDN - Using server-sent events](https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events/Using_server-sent_events) - 使用指南
