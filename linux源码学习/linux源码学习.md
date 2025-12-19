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
# 1.2 主要执行流程

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



