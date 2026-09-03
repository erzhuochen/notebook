# WebSocket

## 概述

### 是什么
WebSocket 是一种在单个 **TCP 连接**上进行**全双工**通信的协议，允许服务器主动向客户端推送数据。

### 解决什么问题
传统 HTTP 是请求-响应模式，服务器无法主动推送数据。要实现实时通信，只能用以下低效方案：
- **短轮询**：客户端每隔几秒发一次请求，大量请求浪费带宽
- **长轮询**：服务器收到请求后不立即响应，等有数据才返回。但每次响应后需要重新建立连接

WebSocket 建立一次连接后保持开启，双方随时可以发送数据，避免重复握手开销。

### 适用场景
- 实时聊天、弹幕系统
- 在线协同编辑（多人同时编辑文档）
- 股票行情、体育赛事实时推送
- 在线游戏（需要低延迟双向通信）

## 核心概念

### 全双工通信
**底层实现**：建立 WebSocket 连接后，这个 TCP 连接的读写权限同时交给双方。不像 HTTP 那样"客户端说完，服务器才能说"，双方可以同时发送数据，互不干扰。

### 协议升级（从 HTTP 到 WebSocket）
**底层实现过程**：
1. 客户端发送 HTTP 请求，请求头包含：
   ```
   Upgrade: websocket
   Connection: Upgrade
   ```
2. 服务器同意升级，返回 `101 Switching Protocols`
3. 握手完成后，这个 TCP 连接不再是 HTTP 协议，改用 WebSocket 帧格式传输数据

### 帧（Frame）协议
**底层实现**：数据不是直接发送字符串，而是封装成帧。每个帧包含：
- **Opcode**：帧类型（文本帧、二进制帧、ping/pong 心跳帧、关闭帧）
- **Payload**：实际数据
- **Mask**：客户端发送的帧必须掩码处理（防止缓存污染攻击）

这样设计的好处是可以区分数据类型和控制指令（如心跳）。

### 持久连接
一次握手后连接保持打开，直到一方主动关闭或网络断开。

需要注意的是，**HTTP/1.1 默认也有 keep-alive 长连接**，同样能复用 TCP、省掉重复的三次握手，所以 WebSocket 的优势不在这里。真正的区别有两点：

1. **语义上服务器可主动推送**。keep-alive 只是让连接不关闭，HTTP 的「请求 → 响应」语义没变，服务器无法在没有请求时主动发数据；WebSocket 握手后双方地位对等，随时可发。
2. **单条消息开销极小**。HTTP 每次请求都要携带完整头部（Cookie、User-Agent 等，通常 500B ~ 2KB），而 WebSocket 帧头最小只有 2 字节。高频通信场景下差距是数量级的。

此外 keep-alive 连接有空闲超时会被回收（Nginx 默认 75 秒），WebSocket 则通过 ping/pong 心跳长期保活。

## 基础使用

### 创建连接
```javascript
// 创建 WebSocket 连接（ws:// 或 wss:// 加密）
const ws = new WebSocket('ws://localhost:8080');

// 连接成功建立
ws.onopen = () => {
  console.log('连接已建立');
  ws.send('Hello Server!');  // 发送文本消息
};

// 接收服务器消息
ws.onmessage = (event) => {
  console.log('收到消息:', event.data);
};

// 连接关闭
ws.onclose = (event) => {
  console.log('连接关闭', event.code, event.reason);
};

// 错误处理
ws.onerror = (error) => {
  console.error('WebSocket 错误:', error);
};
```

**底层发生了什么**：
- `new WebSocket(url)` 触发浏览器发送 HTTP 升级请求
- 握手成功后，`onopen` 被触发
- `ws.send()` 将数据封装成 WebSocket 帧发送到 TCP 连接
- 服务器发来的帧被解析后，触发 `onmessage`

### 发送不同类型的数据
```javascript
// 发送文本
ws.send('Hello');

// 发送 JSON
ws.send(JSON.stringify({ type: 'message', text: 'Hello' }));

// 发送二进制数据（Blob）
const blob = new Blob(['binary data'], { type: 'application/octet-stream' });
ws.send(blob);

// 发送二进制数据（ArrayBuffer）
const buffer = new ArrayBuffer(8);
ws.send(buffer);
```

### 连接状态
```javascript
// WebSocket.CONNECTING (0) - 正在连接
// WebSocket.OPEN (1) - 已连接
// WebSocket.CLOSING (2) - 正在关闭
// WebSocket.CLOSED (3) - 已关闭

if (ws.readyState === WebSocket.OPEN) {
  ws.send('消息');
}
```

### 主动关闭连接
```javascript
// 关闭连接（可选：状态码和原因）
ws.close(1000, '正常关闭');
```

**底层实现**：`close()` 发送一个关闭帧（opcode=8），包含状态码和原因，对方收到后也发送关闭帧确认，然后双方关闭 TCP 连接。

## [进阶] 深入理解

### 握手细节
**客户端请求头**：
```
GET /chat HTTP/1.1
Host: example.com
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==
Sec-WebSocket-Version: 13
```

**服务器响应头**：
```
HTTP/1.1 101 Switching Protocols
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=
```

**底层验证机制**：
- `Sec-WebSocket-Key` 是客户端生成的随机字符串（Base64 编码）
- 服务器用固定的 GUID `258EAFA5-E914-47DA-95CA-C5AB0DC85B11` 拼接 Key，做 SHA-1 哈希后 Base64 编码，得到 `Sec-WebSocket-Accept`
- 客户端验证这个值，确认服务器真的支持 WebSocket，而不是随便返回 101 的中间代理

### 心跳机制（Ping/Pong）
**为什么需要心跳**：
- TCP 连接空闲时，中间的路由器、负载均衡可能认为连接已死，主动断开
- 通过定期发送 ping 帧，保持连接活跃

**底层实现**：
- WebSocket 协议定义了 ping 帧（opcode=9）和 pong 帧（opcode=10）
- 一方发送 ping，另一方必须立即回复 pong
- 浏览器自动处理收到的 ping，开发者无需手动回复

**代码实现**（服务器端需要）：
```javascript
// 客户端定期发送自定义心跳消息
let heartbeatTimer;
function startHeartbeat(ws) {
  heartbeatTimer = setInterval(() => {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({ type: 'ping' }));
    }
  }, 30000); // 每 30 秒
}

// 清理定时器
ws.onclose = () => {
  clearInterval(heartbeatTimer);
};
```

注意：浏览器 WebSocket API 不支持直接发送协议级别的 ping/pong 帧，只能发送应用层的心跳消息。

### 重连机制
**为什么会断开**：
- 网络波动（切换 WiFi、信号弱）
- 服务器重启
- 中间代理超时断开

**底层策略 - 指数退避**：
```javascript
class ReconnectingWebSocket {
  constructor(url) {
    this.url = url;
    this.reconnectDelay = 1000;  // 初始 1 秒
    this.maxReconnectDelay = 30000;  // 最大 30 秒
    this.reconnectAttempts = 0;
    this.connect();
  }

  connect() {
    this.ws = new WebSocket(this.url);
    
    this.ws.onopen = () => {
      console.log('连接成功');
      this.reconnectAttempts = 0;  // 重置重连次数
      this.reconnectDelay = 1000;  // 重置延迟
    };

    this.ws.onclose = () => {
      console.log('连接关闭，准备重连...');
      this.reconnect();
    };

    this.ws.onerror = (error) => {
      console.error('连接错误:', error);
    };
  }

  reconnect() {
    this.reconnectAttempts++;
    console.log(`第 ${this.reconnectAttempts} 次重连，延迟 ${this.reconnectDelay}ms`);

    setTimeout(() => {
      this.connect();
      // 指数退避：每次重连延迟翻倍
      this.reconnectDelay = Math.min(
        this.reconnectDelay * 2,
        this.maxReconnectDelay
      );
    }, this.reconnectDelay);
  }
}
```

**指数退避的原因**：
- 如果服务器真的崩了，立即重连会加重服务器压力（雪崩效应）
- 逐渐增加延迟给服务器恢复时间
- 设置上限避免等待时间过长

## [进阶] 最佳实践

### 1. 生产环境必须使用 wss://
```javascript
// 开发环境
const ws = new WebSocket('ws://localhost:8080');

// 生产环境（加密传输）
const ws = new WebSocket('wss://example.com/socket');
```

**底层实现**：wss 就是 WebSocket over TLS，类似 HTTPS。数据经过 SSL/TLS 加密后再发送，防止中间人监听和篡改。

### 2. 区分正常关闭和异常关闭
```javascript
ws.onclose = (event) => {
  if (event.code === 1000) {
    console.log('正常关闭，不需要重连');
  } else {
    console.log('异常关闭，尝试重连');
    reconnect();
  }
};
```

常见关闭码：
- `1000`：正常关闭
- `1001`：端点离开（如页面刷新）
- `1006`：连接异常关闭（网络问题）
- `1009`：消息过大
- `1011`：服务器遇到意外错误

### 3. 消息队列缓冲
**问题**：连接断开时发送消息会失败，消息丢失。

**解决方案**：
```javascript
class BufferedWebSocket {
  constructor(url) {
    this.url = url;
    this.messageQueue = [];  // 消息队列
    this.connect();
  }

  connect() {
    this.ws = new WebSocket(this.url);
    
    this.ws.onopen = () => {
      // 连接成功后，发送队列中的消息
      while (this.messageQueue.length > 0) {
        const msg = this.messageQueue.shift();
        this.ws.send(msg);
      }
    };
  }

  send(data) {
    if (this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(data);
    } else {
      // 连接未就绪，加入队列
      this.messageQueue.push(data);
    }
  }
}
```

### 4. 浏览器连接数限制
**底层限制**：浏览器对同一域名的 WebSocket 连接数有限制（通常 6-10 个）。

**避免方案**：
- 一个页面只创建一个 WebSocket 连接
- 使用消息路由机制（在一个连接上区分不同业务）
- 必要时使用 WebSocket 子协议或多个子域名

### 5. 大数据传输
**问题**：一次发送大量数据可能导致：
- 浏览器卡顿（单线程阻塞）
- 服务器内存溢出
- 中间代理断开连接

**解决方案 - 分片发送**：
```javascript
function sendLargeData(ws, data, chunkSize = 64 * 1024) {
  const totalChunks = Math.ceil(data.length / chunkSize);
  
  for (let i = 0; i < totalChunks; i++) {
    const start = i * chunkSize;
    const end = Math.min(start + chunkSize, data.length);
    const chunk = data.slice(start, end);
    
    ws.send(JSON.stringify({
      type: 'chunk',
      index: i,
      total: totalChunks,
      data: chunk
    }));
  }
}
```

### 6. 页面关闭时清理连接
```javascript
window.addEventListener('beforeunload', () => {
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.close(1000, '页面关闭');
  }
});
```

## 参考资源
- [MDN WebSocket API](https://developer.mozilla.org/zh-CN/docs/Web/API/WebSocket) - 浏览器 API 详细文档
- [RFC 6455 - WebSocket 协议](https://datatracker.ietf.org/doc/html/rfc6455) - 官方协议规范
- [[HTTP 协议-连接管理]](../http/notes.md) - 了解协议升级机制
- [[TCP 协议-全双工通信]](../tcp/notes.md) - 理解 WebSocket 的传输层基础

