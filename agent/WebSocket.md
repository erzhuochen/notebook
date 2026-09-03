

## WebSocket 底层实现原理

### 1. 握手过程（HTTP 升级）

WebSocket 连接从一个特殊的 HTTP 请求开始，这个过程叫"协议升级"。

**客户端发送的握手请求：**
```http
GET /chat HTTP/1.1
Host: server.example.com
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==
Sec-WebSocket-Version: 13
```

关键字段说明：
- `Upgrade: websocket` - 告诉服务器要升级到 WebSocket 协议
- `Connection: Upgrade` - 指示这是一个升级请求
- `Sec-WebSocket-Key` - 随机生成的 Base64 编码字符串，用于验证
- `Sec-WebSocket-Version` - WebSocket 协议版本（目前是 13）

**服务器的响应：**
```http
HTTP/1.1 101 Switching Protocols
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=
```

关键点：
- `101 Switching Protocols` - 表示协议切换成功
- `Sec-WebSocket-Accept` - 服务器根据客户端的 Key 计算得出，用于验证

**验证机制：**
```javascript
// 服务器计算 Accept 的方式
const crypto = require('crypto');
const key = 'dGhlIHNhbXBsZSBub25jZQ==';
const magic = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'; // 固定字符串
const accept = crypto
  .createHash('sha1')
  .update(key + magic)
  .digest('base64');
// 结果: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=
```

这个验证机制确保了服务器真的支持 WebSocket，而不是随便一个 HTTP 服务器。

### 2. 数据帧结构

握手完成后，数据通过"帧"传输。每个帧包含头部信息和实际数据。

**基本帧结构：**
```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-------+-+-------------+-------------------------------+
|F|R|R|R| opcode|M| Payload len |    Extended payload length    |
|I|S|S|S|  (4)  |A|     (7)     |             (16/64)           |
|N|V|V|V|       |S|             |   (if payload len==126/127)   |
| |1|2|3|       |K|             |                               |
+-+-+-+-+-------+-+-------------+-------------------------------+
```

**初级开发需要理解的关键字段：**

**FIN（1 bit）**  
标识这是否是消息的最后一个片段。大消息可以分成多个帧发送。

**Opcode（4 bits）**  
数据类型标识：
- `0x1` - 文本数据（UTF-8）
- `0x2` - 二进制数据
- `0x8` - 连接关闭
- `0x9` - Ping（心跳检测）
- `0xA` - Pong（心跳响应）

**MASK（1 bit）**  
客户端发送的数据必须掩码，服务器发送的不能掩码。这是安全设计，防止缓存投毒攻击。

**Payload Length（7 bits）**  
数据长度：
- 0-125：实际长度
- 126：后面 2 字节表示长度
- 127：后面 8 字节表示长度

**简化的帧解析示例：**
```javascript
function parseFrame(buffer) {
  const firstByte = buffer[0];
  const secondByte = buffer[1];
  
  const fin = (firstByte & 0b10000000) !== 0;
  const opcode = firstByte & 0b00001111;
  const masked = (secondByte & 0b10000000) !== 0;
  let payloadLen = secondByte & 0b01111111;
  
  let offset = 2;
  
  // 处理扩展长度
  if (payloadLen === 126) {
    payloadLen = buffer.readUInt16BE(offset);
    offset += 2;
  } else if (payloadLen === 127) {
    payloadLen = buffer.readBigUInt64BE(offset);
    offset += 8;
  }
  
  // 处理掩码
  let maskKey;
  if (masked) {
    maskKey = buffer.slice(offset, offset + 4);
    offset += 4;
  }
  
  // 提取数据
  let payload = buffer.slice(offset, offset + payloadLen);
  
  // 解码掩码数据
  if (masked) {
    for (let i = 0; i < payload.length; i++) {
      payload[i] ^= maskKey[i % 4];
    }
  }
  
  return { fin, opcode, payload };
}
```

### 3. 心跳机制（Ping/Pong）

WebSocket 连接可能因为网络问题"僵死"，但双方都不知道。心跳机制用来检测连接是否还活着。

**工作原理：**
```javascript
// 服务端实现
class WebSocketServer {
  constructor() {
    this.clients = new Map();
  }
  
  setupHeartbeat(ws) {
    // 每 30 秒发送一次 ping
    const interval = setInterval(() => {
      if (ws.readyState === WebSocket.OPEN) {
        ws.ping();
        
        // 设置超时：如果 5 秒内没收到 pong，认为连接断开
        ws.isAlive = false;
        setTimeout(() => {
          if (!ws.isAlive) {
            console.log('连接超时，主动关闭');
            ws.terminate();
          }
        }, 5000);
      }
    }, 30000);
    
    // 收到 pong 响应
    ws.on('pong', () => {
      ws.isAlive = true;
    });
    
    // 清理定时器
    ws.on('close', () => {
      clearInterval(interval);
    });
  }
}
```

**客户端通常自动响应 Ping**，浏览器的 WebSocket API 会自动处理，不需要手动写代码。

### 4. 连接状态管理

WebSocket 有明确的状态机：

```javascript
WebSocket.CONNECTING  // 0 - 正在连接
WebSocket.OPEN        // 1 - 连接已建立
WebSocket.CLOSING     // 2 - 正在关闭
WebSocket.CLOSED      // 3 - 连接已关闭
```

**状态转换：**
```
CONNECTING --握手成功--> OPEN
OPEN --调用close()--> CLOSING --收到关闭帧--> CLOSED
OPEN --网络断开--> CLOSED
```

**正确的发送数据方式：**
```javascript
function safeSend(ws, data) {
  if (ws.readyState === WebSocket.OPEN) {
    ws.send(data);
  } else {
    console.warn('连接未就绪，状态:', ws.readyState);
    // 可以选择缓存数据或重连
  }
}
```

### 5. 关闭握手

关闭连接也需要握手，不能直接断开 TCP 连接。

**关闭帧格式：**
```
+--------+--------+------------------+
| Opcode | Length | Close Code + Msg |
|  0x8   |   2+   |  1000 "Normal"   |
+--------+--------+------------------+
```

**常见关闭码：**
```javascript
1000 - 正常关闭
1001 - 端点离开（如页面关闭）
1002 - 协议错误
1003 - 收到不支持的数据类型
1006 - 异常关闭（没有收到关闭帧）
1009 - 消息太大
1011 - 服务器内部错误
```

**完整的关闭流程：**
```javascript
// 客户端主动关闭
ws.close(1000, '用户退出');

// 服务端处理
ws.on('close', (code, reason) => {
  console.log(`连接关闭: ${code} - ${reason}`);
  // 清理资源
});
```

### 6. 常见问题和解决方案

**问题 1：断线重连**
```javascript
class ReconnectWebSocket {
  constructor(url) {
    this.url = url;
    this.reconnectDelay = 1000;
    this.maxReconnectDelay = 30000;
    this.connect();
  }
  
  connect() {
    this.ws = new WebSocket(this.url);
    
    this.ws.onopen = () => {
      console.log('连接成功');
      this.reconnectDelay = 1000; // 重置延迟
    };
    
    this.ws.onclose = () => {
      console.log(`${this.reconnectDelay}ms 后重连...`);
      setTimeout(() => this.connect(), this.reconnectDelay);
      // 指数退避
      this.reconnectDelay = Math.min(
        this.reconnectDelay * 2, 
        this.maxReconnectDelay
      );
    };
  }
}
```

**问题 2：消息顺序保证**  
WebSocket 基于 TCP，天然保证顺序。同一连接上发送的消息按顺序到达。

**问题 3：消息分片**  
大消息会被分成多个帧。应用层通常不需要处理，WebSocket 库会自动组装。

**问题 4：跨域问题**  
WebSocket 不受浏览器同源策略限制，但服务器可以检查 `Origin` 头来控制访问：
```javascript
wss.on('connection', (ws, req) => {
  const origin = req.headers.origin;
  if (!allowedOrigins.includes(origin)) {
    ws.close(1008, 'Origin not allowed');
    return;
  }
  // 继续处理
});
```

### 核心要点总结

1. **握手本质是 HTTP 升级** - 利用现有基础设施，穿透防火墙
2. **数据通过帧传输** - 有明确的格式和类型
3. **客户端必须掩码** - 安全设计，防止攻击
4. **需要心跳保活** - 检测僵尸连接
5. **有完整的状态机** - 发送数据前要检查状态
6. **关闭需要握手** - 优雅关闭，传递关闭原因


我的理解：
1. WebSocket是HTTP协议加上