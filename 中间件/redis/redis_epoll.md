# 个人总结
### 混淆点：
- read()：tcp接收缓冲区有数据时把数据拷贝到用户态。
- write()：把用户态的数据拷贝到tcp发送缓冲区。
- AE_READABLE：接收缓冲区有数据了 → 通知你可以调 read() 了
- AE_WRITABLE：发送缓冲区有空间了 → 通知你可以调 write() 了

### redis数据类型：
- String：
	- int：如果字符串是纯整数。实现：指向实际对象的指针是8字节的，直接把整数放进去。
	- sds：embstr 嵌入式字符串（长度小于44字节） --> raw 原始字符串（长度大于44字节） 
- List：listpack+双向链表=quicklist
- Set：intset/listpack（小容量）--> dict（大容量）
- ZSet：listpack（小容量）--> skiplist+dict（大容量）
- Hash：listpack（小容量）--> dict（大容量）

RDB和AOF：
- RDB：内存快照，fork一个子进程来生成rdb文件（二进制）存储redis中数据。
	- 优点：二进制文件恢复数据快
	- 缺点：实时性差
- AOF：把redis命令附加到aof文件中。文件过大时会触发AOF重写，AOF重写根据redis当前内容生成对应的set语句放进AOF重写缓冲区。
	- 优点：实时性强
	- 缺点：aof文件存储的是redis指令，需要占用的空间大，恢复数据慢。

### RDB和AOF
#### 1. RDB (Redis DataBase) - 内存快照

- **底层机制：** 主线程调用 Linux `fork()` 系统调用创建子进程生成 `.rdb`（紧凑的二进制文件）。
    
- **核心考点（COW 写时复制）：** `fork` 瞬间并不复制几十 GB 的物理内存，只复制**页表（Page Table）**。主子进程共享物理内存，权限降级为只读。只有当主线程处理新写请求触发缺页中断（Page Fault）时，OS 才会为修改的数据分配新的物理页。
    
- **优缺点：**
    
    - _优：_ 二进制格式紧凑，直接 load 进内存，**恢复速度极快**。
        
    - _缺：_ 实时性差，两次快照之间宕机数据全丢。`fork` 操作在内存巨大或开启了 Linux 大页机制（THP）时，依然会阻塞单线程的主事件循环。
        

#### 2. AOF (Append Only File) - 命令日志

- **底层机制：** 记录每一次写命令。写入过程依赖 Linux 的 **VFS（虚拟文件系统）和 Page Cache**。
    
- **核心考点（刷盘策略与假死）：** 真正的实时性取决于 `appendfsync` 配置。生产默认 `everysec`（每秒由后台 BIO 线程调用 `fsync` 刷盘）。**注意陷阱**：如果宿主机磁盘 I/O 极差导致 `fsync` 阻塞超过 2 秒，主线程为了防止数据丢失会强行发起 `write` 产生 VFS inode 锁竞争，直接导致主线程（epoll 循环）假死。
    
- **AOF 重写：** 绕过旧文件，直接扫描当前内存状态生成最简命令。Redis 7.0 之前利用 AOF 重写缓冲区解决增量一致性；7.0 之后引入 Multi-Part AOF 彻底废弃了重写缓冲区，消除了双写的内存开销。
    
- **优缺点：**
    
    - _优：_ 实时性强，最多丢 1 秒数据。
        
    - _缺：_ 纯文本追加，文件膨胀快。故障恢复时需要重放大量命令，**恢复速度极慢**。
#### 3. 终极防御：混合持久化（面试绝杀话术）

不要孤立地评价这两个机制。在实际生产环境（Redis 4.0 之后），我们默认开启 **混合持久化 (`aof-use-rdb-preamble`)**。

- **回答话术：** “在 AOF 重写时，`fork` 出的子进程会先把当前内存数据以 **RDB 的二进制格式**写入新文件的头部，重写期间产生的新增命令则以 **AOF 文本格式**追加到尾部。这样在重启恢复时，既能享受 RDB 极快的加载速度，又能利用少量的 AOF 增量日志保证极高的数据完整性。”


### 主从同步
1. 从库和主库建连
- 全量复制：从库刚启动或断连太久时使用全量复制
  1. 主库主线程触发RDB，fork一个子进程生成rdb文件。
  2. 在子进程生成rdb文件期间，为从库单独生成一个缓冲区（写入主库生成期间执行的redis命令）
  3. 发送rdb文件给从库。
  4. 发送缓冲区内容给从库。
  5. 结束同步
- 增量复制
  1. 主库维护一个环形队列，里面记录最近执行的redis指令。发送环形队列给从库。
  2. 从库根据之前同步时的断点在环形队列中查找。
  3. 若找到，就从断点开始执行之后的redis指令。若没找到，说明断连太久，需要全量复制。





# Redis 线程模型 & epoll 使用源码学习指南

本文档引导你学习 Redis 如何使用 epoll 构建其事件驱动的服务器模型，以及 Redis 6.0 多线程 I/O 的实现原理。配套源码文件已放在同目录下。

> [!NOTE]
> 本指南基于 **Redis 7.2** 源码。建议先阅读完 [epoll.md](file:///d:/workspace/linux/epoll/epoll.md) 再开始本文。

---

## 全局架构一览

```mermaid
graph TB
    subgraph "Redis 启动"
        A["main()"] --> B["initServer()"]
        B --> C["aeCreateEventLoop()"]
        C --> D["aeApiCreate() → epoll_create()"]
        B --> E["listenToPort() → socket + bind + listen"]
        E --> F["aeCreateFileEvent(listen_fd, AE_READABLE, acceptTcpHandler)"]
        F --> G["aeApiAddEvent() → epoll_ctl(ADD, EPOLLIN)"]
        B --> H["aeCreateTimeEvent(serverCron)"]
        B --> I["initThreadedIO()"]
    end

    subgraph "Redis 主循环"
        J["aeMain()"] --> K["while (!stop)"]
        K --> L["aeProcessEvents()"]
        L --> M["beforeSleep()"]
        M --> N["handleClientsWithPendingWritesUsingThreads()"]
        L --> O["aeApiPoll() → epoll_wait()"]
        O --> P["处理就绪的文件事件"]
        P --> Q["处理到期的时间事件"]
        Q --> K
    end

    D -.-> O
    G -.-> O
```

---

## 第一阶段：事件循环抽象层 (ae)

> 📍 配套源码: [redis_ae_epoll.c](file:///d:/workspace/linux/epoll/redis_ae_epoll.c) + [redis_ae.c](file:///d:/workspace/linux/epoll/redis_ae.c)

### 1.1 为什么 Redis 要自己封装 epoll？

Redis 需要在 Linux/macOS/Solaris/BSD 上运行，不同系统有不同的 I/O 多路复用 API：

| 系统 | API | Redis 后端文件 |
|------|-----|---------------|
| Linux | epoll | `ae_epoll.c` |
| macOS/BSD | kqueue | `ae_kqueue.c` |
| Solaris | evport | `ae_evport.c` |
| 其他 | select | `ae_select.c` |

Redis 通过 `ae.c` 定义统一接口，然后用 **`#include "ae_epoll.c"`** 在编译时"内联"具体实现：

```c
// ae.c 中的平台选择
#ifdef HAVE_EVPORT
#include "ae_evport.c"
#elif defined(HAVE_EPOLL)
#include "ae_epoll.c"          // ← Linux 上走这里
#elif defined(HAVE_KQUEUE)
#include "ae_kqueue.c"
#else
#include "ae_select.c"
#endif
```

> [!TIP]
> 这里用 `#include ".c"` 而不是 `.h` + 链接。这使得 `ae_epoll.c` 中的 `static` 函数被直接编译进 `ae.c`，**避免了函数指针的间接调用开销**。这是一种编译期多态，比虚函数表更高效。

### 1.2 统一接口 → epoll 映射

| ae 统一接口 | epoll 实现 | 对应的 epoll 系统调用 |
|------------|-----------|---------------------|
| `aeApiCreate()` | 创建 epoll 实例 | `epoll_create(1024)` |
| `aeApiAddEvent()` | 注册/修改事件 | `epoll_ctl(ADD/MOD)` |
| `aeApiDelEvent()` | 删除事件 | `epoll_ctl(DEL/MOD)` |
| `aeApiPoll()` | 等待事件 | `epoll_wait()` |
| `aeApiResize()` | 调整大小 | `zrealloc(events)` |
| `aeApiFree()` | 释放资源 | `close(epfd)` |

### 1.3 核心数据结构

```
aeEventLoop (事件循环主结构)
  │
  ├── events[]        ── aeFileEvent 数组（以 fd 为索引）
  │                      每个元素: { mask, rfileProc, wfileProc, clientData }
  │
  ├── fired[]         ── aeFiredEvent 数组（epoll_wait 的结果）
  │                      每个元素: { fd, mask }
  │
  ├── timeEventHead   ── aeTimeEvent 链表（定时器）
  │                      每个元素: { id, when, timeProc }
  │
  ├── apidata         ── aeApiState* ← 指向 epoll 状态！
  │                      内含: { epfd, events[] }
  │
  ├── beforesleep     ── 每次 epoll_wait 前的回调
  └── aftersleep      ── 每次 epoll_wait 后的回调
```

> [!IMPORTANT]
> **与内核 epoll 的对比**：内核用**红黑树**管理所有被监听的 fd，但 Redis 用的是简单的**数组**（以 fd 为下标）。这是因为 Redis 在用户态已经知道 fd 的范围（maxclients + 128），用数组 O(1) 访问比红黑树 O(log N) 更快。

---

## 第二阶段：ae_epoll.c 逐函数解读

> 📍 配套源码: [redis_ae_epoll.c](file:///d:/workspace/linux/epoll/redis_ae_epoll.c)

### 2.1 `aeApiCreate()` — 创建 epoll

```c
static int aeApiCreate(aeEventLoop *eventLoop) {
    aeApiState *state = zmalloc(sizeof(aeApiState));
    state->events = zmalloc(sizeof(struct epoll_event) * eventLoop->setsize);
    state->epfd = epoll_create(1024);   // ← 你在 epoll.md 中学过的！
    anetCloexec(state->epfd);           // fork 时自动关闭
    eventLoop->apidata = state;
    return 0;
}
```

对比你之前学的内核 `epoll_create` 流程：
- 内核会分配 `struct eventpoll`（红黑树 + 就绪链表 + 等待队列）
- Redis 这边额外分配了 `events[]` 数组用于接收 `epoll_wait` 的结果

### 2.2 `aeApiAddEvent()` — ADD 还是 MOD？自动判断

```c
static int aeApiAddEvent(aeEventLoop *eventLoop, int fd, int mask) {
    // ⭐ 关键：自动判断用 ADD 还是 MOD
    int op = eventLoop->events[fd].mask == AE_NONE ?
            EPOLL_CTL_ADD : EPOLL_CTL_MOD;
    
    mask |= eventLoop->events[fd].mask;  // 合并新旧事件
    
    // 转换: AE_READABLE → EPOLLIN, AE_WRITABLE → EPOLLOUT
    if (mask & AE_READABLE) ee.events |= EPOLLIN;
    if (mask & AE_WRITABLE) ee.events |= EPOLLOUT;
    
    epoll_ctl(state->epfd, op, fd, &ee);
}
```

> [!NOTE]
> Redis **不使用 EPOLLET（边缘触发）**，使用的是默认的**水平触发 (LT)**。这与 Nginx 不同（Nginx 使用 ET）。原因：Redis 的单线程模型下，LT 更简单且不会丢事件。

### 2.3 `aeApiPoll()` — 事件循环的阻塞点

```c
static int aeApiPoll(aeEventLoop *eventLoop, struct timeval *tvp) {
    // ⭐ 整个 Redis 主线程在这里阻塞等待！
    retval = epoll_wait(state->epfd, state->events,
                        eventLoop->setsize,
                        tvp ? (tvp->tv_sec*1000 + ...) : -1);
    
    // 将 epoll 的事件格式转换为 Redis 的事件格式
    for (j = 0; j < numevents; j++) {
        if (e->events & EPOLLIN)  mask |= AE_READABLE;
        if (e->events & EPOLLOUT) mask |= AE_WRITABLE;
        if (e->events & EPOLLERR) mask |= AE_WRITABLE | AE_READABLE; // ⭐
        if (e->events & EPOLLHUP) mask |= AE_WRITABLE | AE_READABLE; // ⭐
        
        eventLoop->fired[j].fd = e->data.fd;
        eventLoop->fired[j].mask = mask;
    }
}
```

> [!IMPORTANT]
> **EPOLLERR 和 EPOLLHUP 的处理**：当 socket 出错或对端关闭时，Redis 将其同时标记为可读可写。这确保了读回调（`readQueryFromClient`）能检测到连接关闭，写回调（`sendReplyToClient`）能检测到写入失败。

---

## 第三阶段：一个请求的完整生命周期

> 📍 配套源码: [redis_networking.c](file:///d:/workspace/linux/epoll/redis_networking.c) + [redis_server.c](file:///d:/workspace/linux/epoll/redis_server.c)

以一个客户端执行 `SET mykey myvalue` 命令为例：

```mermaid
sequenceDiagram
    participant Client as 客户端
    participant Kernel as Linux 内核 (epoll)
    participant Main as Redis 主线程
    participant IO as I/O 线程池

    Note over Main: initServer() 已注册 listen_fd → EPOLLIN
    
    rect rgb(40, 40, 80)
    Note over Client,Main: 阶段 1: 建立连接
    Client->>Kernel: connect()
    Kernel->>Main: epoll_wait 返回: listen_fd 可读
    Main->>Main: acceptTcpHandler() → accept()
    Main->>Main: createClient() → 设置非阻塞
    Main->>Kernel: epoll_ctl(ADD, client_fd, EPOLLIN)
    Note over Main: 注册回调: readQueryFromClient
    end

    rect rgb(40, 80, 40)
    Note over Client,IO: 阶段 2: 读取请求
    Client->>Kernel: send("*3\r\n$3\r\nSET\r\n...")
    Kernel->>Main: epoll_wait 返回: client_fd 可读
    Main->>Main: readQueryFromClient() 被调用
    alt 单线程模式
        Main->>Main: read() + 解析 RESP 协议
    else 多线程 I/O
        Main->>IO: 分发到 I/O 线程
        IO->>IO: read() + 解析 RESP 协议
        IO->>Main: 完成通知
    end
    end

    rect rgb(80, 40, 40)
    Note over Main: 阶段 3: 执行命令 (始终单线程!)
    Main->>Main: processCommand()
    Main->>Main: setCommand() → dictAdd(db->dict, "mykey", "myvalue")
    Main->>Main: addReply(c, "+OK\r\n")
    Main->>Main: 标记 CLIENT_PENDING_WRITE
    end

    rect rgb(80, 80, 40)
    Note over Client,IO: 阶段 4: 发送响应
    Note over Main: beforeSleep() 被调用
    alt 单线程模式
        Main->>Main: handleClientsWithPendingWrites()
        Main->>Client: write("+OK\r\n") 直接写
    else 多线程 I/O
        Main->>IO: 分发待写客户端
        IO->>Client: 各线程并行 write()
        IO->>Main: 完成通知
    end
    Note over Main: 如果没写完 → epoll_ctl(ADD, EPOLLOUT)
    end
```

### 3.1 连接建立

```
initServer()
  └─ aeCreateFileEvent(listen_fd, AE_READABLE, acceptTcpHandler)
       └─ aeApiAddEvent() → epoll_ctl(epfd, EPOLL_CTL_ADD, listen_fd, {EPOLLIN})

客户端 connect() →
  → 内核 TCP 三次握手完成
  → listen socket 等待队列唤醒
  → epoll_wait() 返回 listen_fd 可读
  → acceptTcpHandler() 被调用
    ├─ accept() 获取 client_fd
    ├─ 设置非阻塞、TCP_NODELAY、keepalive
    └─ aeCreateFileEvent(client_fd, AE_READABLE, readQueryFromClient)
         └─ epoll_ctl(epfd, EPOLL_CTL_ADD, client_fd, {EPOLLIN})
```

### 3.2 响应发送的优化（beforesleep 直接写）

这是 Redis 6.0+ 的重要优化：

```
旧方式 (Redis 5.x):
  addReply() → epoll_ctl(ADD, EPOLLOUT) → epoll_wait → write()
  问题: 每个响应都需要 2 次系统调用 (epoll_ctl + epoll_wait)

新方式 (Redis 6.0+):
  addReply() → 加入 clients_pending_write 链表
  beforeSleep() → 直接 write()     ← 大部分响应在这里就写完了！
  只有写不完时 → epoll_ctl(ADD, EPOLLOUT) → epoll_wait → write()
```

> [!TIP]
> 大多数 Redis 响应（如 `+OK`、`$5\r\nhello`）都很小，一次 `write()` 就能完成。这个优化**避免了绝大部分 `epoll_ctl` 系统调用**，显著提升性能。

---

## 第四阶段：事件循环主逻辑

> 📍 配套源码: [redis_ae.c](file:///d:/workspace/linux/epoll/redis_ae.c) `aeProcessEvents()`

```
aeMain()                          ← Redis 的一生就是这个 while 循环
  └─ while (!stop) {
       aeProcessEvents()          ← 每次迭代处理所有事件
         │
         ├─ Step 1: 计算 epoll_wait 的超时时间
         │   找到最近的 aeTimeEvent（如 serverCron 100ms 后到期）
         │   → 超时值 = min(最近定时事件时间, 当前时间差)
         │
         ├─ Step 2: beforesleep(eventLoop)
         │   ├─ handleClientsWithPendingWritesUsingThreads()  ← 多线程写
         │   ├─ handleClientsWithPendingReadsUsingThreads()   ← 多线程读
         │   ├─ flushAppendOnlyFile()                        ← AOF 写入
         │   └─ handleClientsBlockedOnKeys()                 ← 解除阻塞客户端
         │
         ├─ Step 3: aeApiPoll() = epoll_wait() ← 阻塞等待！
         │
         ├─ Step 4: aftersleep(eventLoop)
         │
         ├─ Step 5: 遍历 fired[] 处理文件事件
         │   for (j = 0; j < numevents; j++) {
         │     fd = fired[j].fd
         │     mask = fired[j].mask
         │     if (可读) → rfileProc(fd)  // 如 acceptTcpHandler 或 readQueryFromClient
         │     if (可写) → wfileProc(fd)  // 如 sendReplyToClient
         │   }
         │
         └─ Step 6: processTimeEvents()
             遍历 timeEvent 链表
             if (te->when <= now) → te->timeProc()  // 如 serverCron
     }
```

### AE_BARRIER 标志

正常情况下，同一个 fd 同时可读可写时，Redis 先执行读回调再执行写回调。但有时需要反转顺序：

```c
// 场景: AOF always fsync 模式
// 1. beforeSleep 中 write() 把回复写给客户端
// 2. beforeSleep 中 fsync() 确保 AOF 落盘
// 3. epoll_wait 返回后，需要先确认写入完成，再处理新请求
// → 设置 AE_BARRIER 让写回调先于读回调执行
```

---


## 第五阶段：Redis 6.0 多线程 I/O

> 📍 配套源码: [redis_server.c](file:///d:/workspace/linux/epoll/redis_server.c) 下半部分

### 5.1 架构总览

```
                    ┌─────────────────────────────────────────────┐
                    │              Redis 主线程                    │
                    │                                             │
                    │  ┌─── beforesleep ──────────────────────┐   │
                    │  │                                      │   │
                    │  │  ① 多线程读: 分发待读客户端到 I/O 线程  │   │
                    │  │  ② 主线程也读自己分到的那份             │   │
                    │  │  ③ 等待所有线程完成                     │   │
                    │  │  ④ 主线程串行执行所有命令 ← 关键!       │   │
                    │  │  ⑤ 多线程写: 分发待写客户端到 I/O 线程  │   │
                    │  │  ⑥ 主线程也写自己分到的那份             │   │
                    │  │  ⑦ 等待所有线程完成                     │   │
                    │  └──────────────────────────────────────┘   │
                    │                                             │
                    │  epoll_wait() ← 阻塞等待下一批事件          │
                    │                                             │
                    │  处理就绪事件 + 定时事件                     │
                    └─────────────────────────────────────────────┘
                         ↕           ↕           ↕
                    ┌─────────┐ ┌─────────┐ ┌─────────┐
                    │ IO 线程1 │ │ IO 线程2 │ │ IO 线程3 │
                    │         │ │         │ │         │
                    │ 自旋等待 │ │ 自旋等待 │ │ 自旋等待 │
                    │ read()  │ │ read()  │ │ read()  │
                    │ write() │ │ write() │ │ write() │
                    └─────────┘ └─────────┘ └─────────┘
```

### 5.2 为什么命令执行必须单线程？

```
多线程执行命令的问题:
  线程 A: SET key 100
  线程 B: INCR key        ← 同时操作同一个 key！
  
  如果并行执行，需要对每个 key 加锁 → 锁竞争严重 → 反而更慢
  
Redis 的选择:
  I/O 是并行的（read/write 不访问共享数据）
  执行是串行的（不需要任何锁！）
  → 简洁、正确、高性能
```

### 5.3 I/O 线程的同步机制

Redis 没有使用 `pthread_mutex` 或 `pthread_cond` 来同步 I/O 线程，而是使用 **原子变量 + 自旋等待**：

```c
// I/O 线程: 自旋等待任务
while (1) {
    for (int j = 0; j < 1000000; j++)
        if (io_threads_pending[id] != 0) break;  // ← busy-wait
    // 有任务了 → 执行 read/write
    // 完成后: io_threads_pending[id] = 0
}

// 主线程: 自旋等待所有线程完成
while (1) {
    unsigned long pending = 0;
    for (int j = 1; j < io_threads_num; j++)
        pending += io_threads_pending[j];
    if (pending == 0) break;                      // ← busy-wait
}
```

> [!IMPORTANT]
> **为什么用自旋而不用 mutex/condition？** 因为 Redis 多线程 I/O 是"脉冲式"的——只在 `beforesleep` 中短暂并行，其余时间线程空闲。mutex 唤醒需要内核态切换（~微秒级），自旋在空闲 CPU 核上几乎零延迟。代价是线程空闲时会占用 CPU。

### 5.4 多线程 I/O 与 epoll 的关系

```
关键理解: I/O 线程完全不接触 epoll！

epoll_wait → 只有主线程调用
epoll_ctl  → 只有主线程调用

I/O 线程只做:
  read(client_fd, buf, len)    — 从 socket 读数据
  write(client_fd, buf, len)   — 往 socket 写数据
  解析 RESP 协议               — 纯内存操作

所有 epoll 操作都由主线程完成:
  注册新连接 → 主线程 epoll_ctl(ADD)
  注册写事件 → 主线程 epoll_ctl(MOD)
  删除事件   → 主线程 epoll_ctl(DEL)
  等待事件   → 主线程 epoll_wait()
```

---

## 第六阶段：Redis vs 内核 epoll 的对应关系

| 你在 epoll.md 学到的内核概念 | Redis 中的对应 |
|:---|:---|
| `epoll_create()` → `struct eventpoll` | `aeApiCreate()` → `aeApiState{epfd, events[]}` |
| `epoll_ctl(ADD)` → `ep_insert()` → 红黑树 + 回调注册 | `aeCreateFileEvent()` → `aeApiAddEvent()` → `epoll_ctl()` |
| `epoll_wait()` → `ep_poll()` → 睡眠 → 就绪链表 | `aeApiPoll()` → `epoll_wait()` → `fired[]` 数组 |
| `ep_poll_callback()` — fd 有事件时回调 | 内核自动处理，Redis 不需要关心 |
| 红黑树管理所有 fd | Redis 用 `events[fd]` 数组，O(1) 访问 |
| 就绪链表 `rdllist` | `fired[]` 数组（从 `epoll_wait` 填充） |
| LT vs ET（水平/边缘触发） | Redis 使用 **LT**（不设置 EPOLLET） |
| `ovflist` 溢出链表 | Redis 不需要（用户态不存在这个问题） |

---

## 关键总结

### Redis 使用 epoll 的 5 个关键点

1. **LT 模式，不用 ET** — 简单可靠，不丢事件
2. **只有主线程操作 epoll** — 所有 `epoll_ctl`/`epoll_wait` 都在主线程，I/O 线程只做 `read`/`write`
3. **beforesleep 直接写优化** — 大多数响应不经过 `epoll_ctl(EPOLLOUT) → epoll_wait` 的路径
4. **自动判断 ADD/MOD** — `aeApiAddEvent` 根据 fd 当前状态自动选择 `EPOLL_CTL_ADD` 或 `EPOLL_CTL_MOD`
5. **超时由定时事件驱动** — `epoll_wait` 的超时值 = 最近定时事件的触发时间

### Redis 线程模型的 3 个层次

| 层次 | 线程模型 | 说明 |
|:---|:---|:---|
| 事件监听 | **单线程** | 只有主线程调用 `epoll_wait` |
| 网络 I/O | **多线程**（6.0+） | `read()`/`write()` 可分发到 I/O 线程 |
| 命令执行 | **单线程** | `processCommand()` 始终在主线程，不需要锁 |

---

## 推荐阅读顺序

建议按以下顺序阅读配套源码文件：

1. **[redis_ae_epoll.c](file:///d:/workspace/linux/epoll/redis_ae_epoll.c)** — epoll 后端，最小最核心，~180 行
2. **[redis_ae.c](file:///d:/workspace/linux/epoll/redis_ae.c)** — 事件循环框架，重点看 `aeProcessEvents` 和 `aeMain`
3. **[redis_networking.c](file:///d:/workspace/linux/epoll/redis_networking.c)** — 网络事件处理，看 accept/read/write 如何与 epoll 集成
4. **[redis_server.c](file:///d:/workspace/linux/epoll/redis_server.c)** — 服务器初始化 + 多线程 I/O，看全局如何串联

> 如果你想进一步深入，可以问我关于以下主题：
> - Redis 如何处理 `BLPOP` 等阻塞命令（与 epoll 的交互）
> - Redis Cluster 模式下的事件循环
> - Redis 与 Nginx epoll 使用方式的对比（ET vs LT、多进程 vs 多线程）
> - `AE_BARRIER` 标志的完整工作原理
