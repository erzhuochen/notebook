# 一、Linux 2.4.0 内核启动流程分析 (`init/main.c`)

这个文件是 Linux 内核的核心初始化文件，包含了从汇编代码跳转到 C 代码后的整个启动流程。

## 1.1 linux kernel中__setup()函数介绍
### 1.1.1 `__setup`使用示例
```c
static int __init skip_initramfs_param(char *str)
{
	if (*str)
		return 0;
	do_skip_initramfs = 1;
	return 1;
}
__setup("skip_initramfs", skip_initramfs_param);
```
### 1.1.2 `__setup`宏原理
```c
#define __setup(str, fn) \

static char __setup_str_##fn[] __initdata = str; \

static struct kernel_param __setup_##fn __attribute__((unused)) __initsetup = { __setup_str_##fn, fn }
```

| 属性                        | 作用                               |
| ------------------------- | -------------------------------- |
| `__initdata`              | 放入 `.data.init` 段，初始化期间使用，启动后可释放 |
| `__initsetup`             | 放入 `.setup.init` 段，初始化期间使用，供内核遍历 |
| `__attribute__((unused))` | 避免编译器"未使用变量"警告                   |
| `##`                      | 预处理器连接符，生成唯一变量名                  |
以 `main.c` 中的例子 `__setup("root=", root_dev_setup)` 为例，展开后变成：
```c
// 1. 创建一个字符串，存储参数名 "root="
static char __setup_str_root_dev_setup[] __initdata = "root=";

// 2. 创建一个 kernel_param 结构体，关联参数名和处理函数
static struct kernel_param __setup_root_dev_setup __initsetup = { 
    __setup_str_root_dev_setup,   // 参数字符串
    root_dev_setup                 // 处理函数
};
```
### 1.1.3   `__setup`注册的参数如何使用

```c
// 遍历所有注册的内核参数处理器，匹配并执行对应的处理函数。
static int __init checksetup(char *line)
{
    struct kernel_param *p;

    p = &__setup_start;           // 指向 .setup.init 段的起始地址
    do {
        int n = strlen(p->str);   // 获取参数名长度，如 "root=" 长度为 5
        if (!strncmp(line, p->str, n)) {  // 前 n 个字符是否匹配
            if (p->setup_func(line+n))    // 调用处理函数，传入参数值部分
                return 1;                  // 处理成功
        }
        p++;                       // 检查下一个注册项
    } while (p < &__setup_end);    // 直到段结束
    return 0;                      // 没有匹配的处理器
}
```
## 1.2 主要执行流程

### 1. `start_kernel()` - 内核主入口点（0号进程）

这是从架构相关汇编代码跳转过来的第一个 C 函数：
```c
asmlinkage void __init start_kernel(void){
    lock_kernel();              // 【新增】获取大内核锁，SMP 保护，防止多CPU同时执行内核初始化
    printk(linux_banner);
    setup_arch(&command_line);  // 架构相关初始化
    parse_options(command_line);// 解析命令行（类似0.11）
    
    trap_init();                // 初始化异常/陷阱（类似0.11）
    init_IRQ();                 // 初始化中断（类似0.11）
    sched_init();               // 调度器初始化（类似0.11）
    time_init();                // 时间初始化（类似0.11）
    softirq_init();             // 【新增】软中断初始化
    console_init();             // 控制台初始化
    
    kmem_cache_init();          // 【新增】slab 分配器
    mem_init();                 // 内存初始化
    fork_init(mempages);        // 进程创建初始化
    
    // ... 各子系统初始化 ...
    
    smp_init();                 // 【新增】启动其他 CPU
    kernel_thread(init, ...);   // 创建 init 内核线程（类似0.11的fork）
    unlock_kernel();
    cpu_idle();  // 空闲循环函数（在cpu空闲时运行的函数），仅在进程 PID 为0时进入无限循环
}
```
### 2. `init()` - 1号进程

由 `kernel_thread()` 创建，作为所有用户进程的祖先：
init()
    │
    ├── lock_kernel()
    ├── do_basic_setup()           // 设备和驱动初始化
    │       │
    │       ├── child_reaper = current  // 设置孤儿进程收割者
    │       ├── mtrr_init()             // MTRR 初始化
    │       ├── sysctl_init()           // sysctl 初始化
    │       │
    │       ├── pci_init()              // PCI 总线初始化
    │       ├── sbus_init()             // SBUS 初始化
    │       ├── mca_init()              // MCA 总线初始化
    │       ├── isapnp_init()           // ISA PnP 初始化
    │       │
    │       ├── sock_init()             // 网络套接字初始化
    │       ├── do_initcalls()          // 调用所有 __initcall 标记的函数
    │       ├── filesystem_setup()      // 文件系统设置
    │       ├── mount_root()            // 挂载根文件系统
    │       └── mount_devfs_fs()        // 挂载 devfs
    │
    ├── free_initmem()             // 释放 __init 段内存
    ├── unlock_kernel()
    │
    ├── open("/dev/console", ...)  // 打开控制台作为 stdin
    ├── dup(0)                     // 复制为 stdout
    ├── dup(0)                     // 复制为 stderr
    │
    └── execve(...)                // 尝试执行 init 程序
            ├── execute_command    // 命令行指定的 init=
            ├── /sbin/init         // 标准位置
            ├── /etc/init
            ├── /bin/init
            └── /bin/sh            // 最后尝试 shell

### 3. 重要辅助函数

|函数|作用|
|---|---|
|`calibrate_delay()`|校准 `loops_per_jiffy`，计算 BogoMIPS|
|`parse_options()`|解析内核命令行，设置环境变量和 init 参数|
|`name_to_kdev_t()`|将设备名 (如 `/dev/hda1`) 转换为设备号|
|`checksetup()`|检查并调用 `__setup()` 注册的参数处理函数|
|`do_initcalls()`|执行所有通过 `__initcall` 注册的初始化函数|

### 4. 启动参数处理

通过 `__setup()` 宏注册的命令行参数处理器：

- `root=` → 设置根设备
- `ro` → 只读挂载根文件系统
- `rw` → 读写挂载根文件系统
- `debug` → 提高日志级别
- `quiet` → 降低日志级别
- `init=` → 指定 init 程序路径
- `profile=` → 内核性能分析

### 5. 设备名映射表

`root_dev_names[]` 数组定义了设备名到设备号的映射：

- `hda`-`hdt`: IDE 硬盘
- `sda`-`sdp`: SCSI 硬盘
- `fd`: 软盘
- `md`: RAID 设备
- `ram`: 内存盘
- 等等...

## 流程总结图

 BIOS/Bootloader
        │
        ▼
 arch/xxx/boot/*  (汇编启动代码)
        │
        ▼
 start_kernel()   ──────────────────────────────────┐
        │                                           │
        │  [硬件初始化阶段]                          │
        ├── 中断、陷阱、调度器                       │
        ├── 内存管理                                │
        ├── 控制台                                  │
        │                                           │
        │  [子系统初始化]                            │
        ├── VFS、缓冲区、进程                        │
        │                                           │
        │  [多处理器启动]                            │
        ├── smp_init()                              │
        │                                           │
        ▼                                           │
 kernel_thread(init)  ◄─────────────────────────────┘
        │
        ▼
 init() [PID 1]
        │
        ├── 设备驱动初始化
        ├── 挂载根文件系统
        │
        ▼
 execve("/sbin/init")
        │
        ▼
 用户空间 init 进程


# 二、epoll
## 前言

Linux内核提供了3个关键函数供用户来操作epoll，分别是：

- epoll_create(), 创建eventpoll对象
- epoll_ctl(), 操作eventpoll对象
- epoll_wait(), 从eventpoll对象中返回活跃的事件

而操作系统内部会用到一个名叫epoll_event_callback()的回调函数来调度epoll对象中的事件，这个函数非常重要，故本文将会对上述4个函数进行源码分析。

## 源码来源

由于epoll的实现内嵌在内核中，直接查看内核源码的话会有一些无关代码影响阅读。为此在GitHub上写的简化版TCP/IP[协议栈](https://zhida.zhihu.com/search?content_id=210928563&content_type=Article&match_order=1&q=%E5%8D%8F%E8%AE%AE%E6%A0%88&zhida_source=entity)，里面实现了epoll逻辑。链接为：[https://github.com/wangbojing/NtyTcp](https://link.zhihu.com/?target=https%3A//github.com/wangbojing/NtyTcp)

存放着以上4个关键函数的文件是[src\nty_epoll_rb.c]，本文接下来通过分析该程序的代码来探索epoll能支持高[并发连接](https://zhida.zhihu.com/search?content_id=210928563&content_type=Article&match_order=1&q=%E5%B9%B6%E5%8F%91%E8%BF%9E%E6%8E%A5&zhida_source=entity)的秘密。

## 两个核心数据结构

### (1)[epitem](https://zhida.zhihu.com/search?content_id=210928563&content_type=Article&match_order=1&q=epitem&zhida_source=entity)

![](https://pic3.zhimg.com/v2-81634d6162b04a52392571e608a62252_1440w.jpg)

如图所示，epitem是中包含了两个主要的成员变量，分别是rbn和rdlink，前者是红黑树的节点，而后者是双链表的节点，也就是说一个epitem对象即可作为红黑树中的一个节点又可作为双链表中的一个节点。并且每个epitem中存放着一个event，对event的查询也就转换成了对epitem的查询。

```text
struct epitem {
	RB_ENTRY(epitem) rbn;
	/*  RB_ENTRY(epitem) rbn等价于
	struct {											
		struct type *rbe_left;		//指向左子树
		struct type *rbe_right;		//指向右子树
		struct type *rbe_parent;	//指向父节点
		int rbe_color;			    //该节点的颜色
	} rbn
	*/
 
	LIST_ENTRY(epitem) rdlink;
	/* LIST_ENTRY(epitem) rdlink等价于
	struct {									
		struct type *le_next;	//指向下个元素
		struct type **le_prev;	//前一个元素的地址
	}*/
 
	int rdy; //判断该节点是否同时存在与红黑树和双向链表中
	
	int sockfd; //socket句柄
	struct epoll_event event;  //存放用户填充的事件
};
```

### (2)[eventpoll](https://zhida.zhihu.com/search?content_id=210928563&content_type=Article&match_order=4&q=eventpoll&zhida_source=entity)

![](https://picx.zhimg.com/v2-2844a72b6efbb90ab0de45e122c12365_1440w.jpg)

如图所示，eventpoll中包含了两个主要的成员变量，分别是rbr和rdlist，前者指向红黑树的[根节点](https://zhida.zhihu.com/search?content_id=210928563&content_type=Article&match_order=1&q=%E6%A0%B9%E8%8A%82%E7%82%B9&zhida_source=entity)，后者指向双链表的[头结点](https://zhida.zhihu.com/search?content_id=210928563&content_type=Article&match_order=1&q=%E5%A4%B4%E7%BB%93%E7%82%B9&zhida_source=entity)。即一个eventpoll对象对应二个epitem的容器。对epitem的检索，将发生在这两个容器上（红黑树和双链表）。

```text
struct eventpoll {
	/*
	struct ep_rb_tree {
		struct epitem *rbh_root; 			
	}
	*/
	ep_rb_tree rbr;      //rbr指向红黑树的根节点
	
	int rbcnt; //红黑树中节点的数量（也就是添加了多少个TCP连接事件）
	
	LIST_HEAD( ,epitem) rdlist;    //rdlist指向双向链表的头节点；
	/*	这个LIST_HEAD等价于 
		struct {
			struct epitem *lh_first;
		}rdlist;
	*/
	
	int rdnum; //双向链表中节点的数量（也就是有多少个TCP连接来事件了）
 
	// ...略...
	
};
```

## 四个关键函数

### (1) epoll_create()

```c
//创建epoll对象，包含一颗空红黑树和一个空双向链表
int epoll_create(int size) {

	//与很多内核版本一样，size参数没有作用，只要保证大于0即可
	if (size <= 0) return -1;
	
	nty_tcp_manager *tcp = nty_get_tcp_manager(); //获取tcp对象
	if (!tcp) return -1;
	
	struct _nty_socket *epsocket = nty_socket_allocate(NTY_TCP_SOCK_EPOLL);
	if (epsocket == NULL) {
		nty_trace_epoll("malloc failed\n");
		return -1;
	}
 
	// 1° 开辟了一块内存用于填充eventpoll对象
	struct eventpoll *ep = (struct eventpoll*)calloc(1, sizeof(struct eventpoll));
	if (!ep) {
		nty_free_socket(epsocket->id, 0);
		return -1;
	}
 
	ep->rbcnt = 0;
 
	// 2° 让红黑树根指向空
	RB_INIT(&ep->rbr);       //等价于ep->rbr.rbh_root = NULL;
 
	// 3° 让双向链表的头指向空
	LIST_INIT(&ep->rdlist);  //等价于ep->rdlist.lh_first = NULL;
 
	// 4° 并发环境下进行互斥
	// ...该部分代码与主线逻辑无关，可自行查看...
 
	//5° 保存epoll对象
	tcp->ep = (void*)ep;
	epsocket->ep = (void*)ep;
 
	return epsocket->id;
}
```

对以上代码的逻辑进行梳理，可以总结为以下6步：

1. 创建eventpoll对象
2. 让eventpoll中的rbr指向空
3. 让eventpoll中的rdlist指向空
4. 在并发环境下进行互斥
5. 保存eventpoll对象
6. 返回eventpoll对象的句柄(id)

### (2)epoll_ctl()

该函数的逻辑其实很简单，无非就是将用户传入的参数封装为一个epitem对象，然后根据传入的op是①EPOLL_CTL_ADD、②EPOLL_CTL_MOD还是③EPOLL_CTL_DEL，来决定是①将epitem对象插入红黑树中，②更新红黑树中的epitem对象，还是③移除红黑树中的epitem对象。

```c
//往红黑树中加每个tcp连接以及相关的事件
int epoll_ctl(int epid, int op, int sockid, struct epoll_event *event) {
 
	nty_tcp_manager *tcp = nty_get_tcp_manager();
	if (!tcp) return -1;
 
	nty_trace_epoll(" epoll_ctl --> 1111111:%d, sockid:%d\n", epid, sockid);
	struct _nty_socket *epsocket = tcp->fdtable->sockfds[epid];
 
	if (epsocket->socktype == NTY_TCP_SOCK_UNUSED) {
		errno = -EBADF;
		return -1;
	}
 
	if (epsocket->socktype != NTY_TCP_SOCK_EPOLL) {
		errno = -EINVAL;
		return -1;
	}
 
	nty_trace_epoll(" epoll_ctl --> eventpoll\n");
 
	struct eventpoll *ep = (struct eventpoll*)epsocket->ep;
	if (!ep || (!event && op != EPOLL_CTL_DEL)) {
		errno = -EINVAL;
		return -1;
	}
 
	if (op == EPOLL_CTL_ADD) {
		//添加sockfd上关联的事件
		pthread_mutex_lock(&ep->mtx);
 
		struct epitem tmp;
		tmp.sockfd = sockid;
		struct epitem *epi = RB_FIND(_epoll_rb_socket, &ep->rbr, &tmp); //先在红黑树上找，根据key来找，也就是这个sockid，找的速度会非常快
		if (epi) {
			//原来有这个节点，不能再次插入
			nty_trace_epoll("rbtree is exist\n");
			pthread_mutex_unlock(&ep->mtx);
			return -1;
		}
 
		//只有红黑树上没有该节点【没有用过EPOLL_CTL_ADD的tcp连接才能走到这里】；
 
		//(1)生成了一个epitem对象，这个结构对象，其实就是红黑的一个节点；
		epi = (struct epitem*)calloc(1, sizeof(struct epitem));
		if (!epi) {
			pthread_mutex_unlock(&ep->mtx);
			errno = -ENOMEM;
			return -1;
		}
		
		//(2)把socket(TCP连接)保存到节点中；
		epi->sockfd = sockid;  //作为红黑树节点的key，保存在红黑树中
 
		//(3)我们要增加的事件也保存到节点中；
		memcpy(&epi->event, event, sizeof(struct epoll_event));
 
		//(4)把这个节点插入到红黑树中去
		epi = RB_INSERT(_epoll_rb_socket, &ep->rbr, epi); //实际上这个时候epi的rbn成员就会发挥作用，如果这个红黑树中有多个节点，那么RB_INSERT就会epi->rbi相应的值：可以参考图来理解
		assert(epi == NULL);
		ep->rbcnt ++;
		
		pthread_mutex_unlock(&ep->mtx);
 
	} else if (op == EPOLL_CTL_DEL) {
		pthread_mutex_lock(&ep->mtx);
 
		struct epitem tmp;
		tmp.sockfd = sockid;
		
		struct epitem *epi = RB_FIND(_epoll_rb_socket, &ep->rbr, &tmp);//先在红黑树上找，根据key来找，也就是这个sockid，找的速度会非常快
		if (!epi) {
			nty_trace_epoll("rbtree no exist\n");
			pthread_mutex_unlock(&ep->mtx);
			return -1;
		}
		
		//只有在红黑树上找到该节点【用过EPOLL_CTL_ADD的tcp连接才能走到这里】；
 
		//从红黑树上把这个节点移除
		epi = RB_REMOVE(_epoll_rb_socket, &ep->rbr, epi);
		if (!epi) {
			nty_trace_epoll("rbtree is no exist\n");
			pthread_mutex_unlock(&ep->mtx);
			return -1;
		}
 
		ep->rbcnt --;
		free(epi);
		
		pthread_mutex_unlock(&ep->mtx);
 
	} else if (op == EPOLL_CTL_MOD) {
		struct epitem tmp;
		tmp.sockfd = sockid;
		struct epitem *epi = RB_FIND(_epoll_rb_socket, &ep->rbr, &tmp); //先在红黑树上找，根据key来找，也就是这个sockid，找的速度会非常快
		if (epi) {
			//红黑树上有该节点，则修改对应的事件
			epi->event.events = event->events;
			epi->event.events |= EPOLLERR | EPOLLHUP;
		} else {
			errno = -ENOENT;
			return -1;
		}
 
	} else {
		nty_trace_epoll("op is no exist\n");
		assert(0);
	}
 
	return 0;
}
```

### (3)epoll_wait()

```c
//到双向链表中去取相关的事件通知
int epoll_wait(int epid, struct epoll_event *events, int maxevents, int timeout) {
 
	nty_tcp_manager *tcp = nty_get_tcp_manager();
	if (!tcp) return -1;
 
	struct _nty_socket *epsocket = tcp->fdtable->sockfds[epid];
 
	struct eventpoll *ep = (struct eventpoll*)epsocket->ep;
	
    // ...此处主要是一些负责验证性工作的代码...
 
	//(1)当eventpoll对象的双向链表为空时，程序会在这个while中等待一定时间，
	//直到有事件被触发，操作系统将epitem插入到双向链表上使得rdnum>0时，程序才会跳出while循环
	while (ep->rdnum == 0 && timeout != 0) {
		// ...此处主要是一些与等待时间相关的代码...
	}
 
 
	pthread_spin_lock(&ep->lock);
 
	int cnt = 0;
 
	//(1)取得事件的数量
	//ep->rdnum：代表双向链表里边的节点数量（也就是有多少个TCP连接来事件了）
	//maxevents：此次调用最多可以收集到maxevents个已经就绪【已经准备好】的读写事件
	int num = (ep->rdnum > maxevents ? maxevents : ep->rdnum); //哪个数量少，就取得少的数字作为要取的事件数量
	int i = 0;
	
	while (num != 0 && !LIST_EMPTY(&ep->rdlist)) { //EPOLLET
 
		//(2)每次都从双向链表头取得 一个一个的节点
		struct epitem *epi = LIST_FIRST(&ep->rdlist);
 
		//(3)把这个节点从双向链表中删除【但这并不影响这个节点依旧在红黑树中】
		LIST_REMOVE(epi, rdlink); 
 
		//(4)这是个标记，标记这个节点【这个节点本身是已经在红黑树中】已经不在双向链表中；
		epi->rdy = 0;  //当这个节点被操作系统 加入到 双向链表中时，这个标记会设置为1。
 
		//(5)把事件标记信息拷贝出来；拷贝到提供的events参数中
		memcpy(&events[i++], &epi->event, sizeof(struct epoll_event));
		
		num --;
		cnt ++;       //拷贝 出来的 双向链表 中节点数目累加
		ep->rdnum --; //双向链表里边的节点数量减1
	}
	
	pthread_spin_unlock(&ep->lock);
 
	//(5)返回 实际 发生事件的 tcp连接的数目；
	return cnt; 
}
```

该函数的逻辑也十分简单，就是让先看一下eventpoll对象的双链表中是否有节点。如果有节点的话则取出节点中的事件填充到用户传入的指针所指向的内存中。如果没有节点的话，则在while循环中等待一定时间，直到有事件被触发后操作系统会将epitem插入到双向链表上使得rdnum>0时(这个过程是由操作系统调用epoll_event_callback函数完成的)，程序才会跳出while循环，去双向链表中取数据。

### (4)epoll_event_callback()

通过跟踪epoll_event_callback在内核中被调用的位置。可知，当服务器在以下5种情况会调用epoll_event_callback：

1. 客户端connect()连入，服务器处于SYN_RCVD状态时
2. 三路握手完成，服务器处于ESTABLISHED状态时
3. 客户端close()断开连接，服务器处于FIN_WAIT_1和FIN_WAIT_2状态时
4. 客户端send/write()数据，服务器可读时
5. 服务器可以发送数据时

接下来，我们来看一下epoll_event_callback的源码：

```text
//当发生客户端三路握手连入、可读、可写、客户端断开等情况时，操作系统会调用这个函数，用以往双向链表中增加一个节点【该节点同时 也在红黑树中】
int epoll_event_callback(struct eventpoll *ep, int sockid, uint32_t event) {
	struct epitem tmp;
	tmp.sockfd = sockid;
 
	//(1)根据给定的key【这个TCP连接的socket】从红黑树中找到这个节点
	struct epitem *epi = RB_FIND(_epoll_rb_socket, &ep->rbr, &tmp);
	if (!epi) {
		nty_trace_epoll("rbtree not exist\n");
		assert(0);
	}
 
	//(2)从红黑树中找到这个节点后，判断这个节点是否已经被连入到双向链表里【判断的是rdy标志】
	if (epi->rdy) {
		//这个节点已经在双向链表里，那无非是把新发生的事件标志增加到现有的事件标志中
		epi->event.events |= event;
		return 1;
	} 
 
	//走到这里，表示 双向链表中并没有这个节点，那要做的就是把这个节点连入到双向链表中
 
	nty_trace_epoll("epoll_event_callback --> %d\n", epi->sockfd);
	
	pthread_spin_lock(&ep->lock);
 
	//(3)标记这个节点已经被放入双向链表中，我们刚才研究epoll_wait()的时候，从双向链表中把这个节点取走的时候，这个标志被设置回了0
	epi->rdy = 1;  
 
	//(4)把这个节点链入到双向链表的表头位置
	LIST_INSERT_HEAD(&ep->rdlist, epi, rdlink);
 
	//(5)双向链表中的节点数量加1，刚才研究epoll_wait()的时候，从双向链表中把这个节点取走的时候，这个数量减了1
	ep->rdnum ++;
 
	pthread_spin_unlock(&ep->lock);
	pthread_mutex_lock(&ep->cdmtx);
	pthread_cond_signal(&ep->cond);
	pthread_mutex_unlock(&ep->cdmtx);
 
	return 0;
}
```

以上代码的逻辑也十分简单，就是将eventpoll所指向的红黑树的节点插入到双向链表中。

## 总结

epoll底层实现中有两个关键的数据结构，一个是eventpoll另一个是epitem，其中eventpoll中有两个成员变量分别是rbr和rdlist,前者指向一颗红黑树的根，后者指向双向链表的头。而epitem则是红黑树节点和双向链表节点的综合体，也就是说epitem即可作为树的节点，又可以作为链表的节点，并且epitem中包含着用户注册的事件。

- 当用户调用epoll_create()时，会创建eventpoll对象（包含一个红黑树和一个双链表）；
- 而用户调用epoll_ctl(ADD)时，会在红黑树上增加节点（epitem对象）；
- 接下来，操作系统会默默地在通过epoll_event_callback()来管理eventpoll对象。当有事件被触发时，操作系统则会调用epoll_event_callback函数，将含有该事件的epitem添加到双向链表中。
- 当用户需要管理连接时，只需通过epoll_wait()从eventpoll对象中的双链表下"摘取"epitem并取出其包含的事件即可。