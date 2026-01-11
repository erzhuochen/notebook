# 多用户文件系统

  

## 目录

- [1. 系统概述](#1-系统概述)

- [2. 功能框架和流程图](#2-功能框架和流程图)

- [3. 模块描述](#3-模块描述)

- [4. UML图](#4-uml图)

- [5. 数据结构](#5-数据结构)

- [6. 关键技术](#6-关键技术)

- [7. 运行说明](#7-运行说明)

  

---

  

不支持&&

  

## 1. 系统概述

  

本系统是一个模拟Linux的多用户文件系统，采用Spring Boot框架实现依赖注入管理。系统支持：

- 多用户管理与权限控制

- 树状目录结构

- 基本文件操作（create/open/close/read/write）

- 文件保护机制（读读允许/读写互斥/写写互斥）

- Linux风格命令行界面

  

---

  

## 2. 功能框架和流程图

  

### 2.1 系统架构图

  

```

┌─────────────────────────────────────────────────────────────┐

│ 用户界面层 (CLI Layer) │

│ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ │

│ │ Terminal │──│CommandExecutor│──│CommandParser │ │

│ └──────────────┘ └──────────────┘ └──────────────┘ │

├─────────────────────────────────────────────────────────────┤

│ 核心服务层 (Core Layer) │

│ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ │

│ │ FileSystem │ │ FileManager │ │ UserManager │ │

│ └──────────────┘ └──────────────┘ └──────────────┘ │

│ ┌──────────────┐ │

│ │FileProtection│ │

│ └──────────────┘ │

├─────────────────────────────────────────────────────────────┤

│ 数据模型层 (Model Layer) │

│ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ │

│ │ FileNode │ │DirectoryNode │ │ Permission │ │

│ └──────────────┘ └──────────────┘ └──────────────┘ │

│ ┌──────────────┐ │

│ │ User │ │

│ └──────────────┘ │

└─────────────────────────────────────────────────────────────┘

```

  

### 2.2 系统流程图

  

```

┌─────────┐ ┌─────────────┐ ┌────────────────┐

│ 启动 │────▶│ Spring容器 │────▶│ 依赖注入完成 │

└─────────┘ │ 初始化 │ └────────────────┘

└─────────────┘ │

▼

┌─────────┐ ┌─────────────┐ ┌────────────────┐

│ 退出 │◀────│ 执行命令 │◀────│ Terminal启动 │

└─────────┘ └─────────────┘ │ 默认root登录 │

▲ │ └────────────────┘

│ ▼

│ ┌─────────────┐

│ │ 命令解析 │

│ │CommandParser│

│ └─────────────┘

│ │

│ ▼

│ ┌─────────────┐

│ │ 命令执行 │

│ │ 权限检查 │

│ │ 文件保护 │

│ └─────────────┘

│ │

└────────────────┘

```

  

---

  

## 3. 模块描述

  

### 3.1 CLI层模块

  

| 模块 | 功能 | 职责 |

|------|------|------|

| Terminal | 终端界面 | 显示提示符、读取用户输入、启动/退出系统 |

| CommandParser | 命令解析器 | 解析命令行参数、处理引号、解析重定向操作 |

| CommandExecutor | 命令执行器 | 分发命令、调用核心服务、返回执行结果 |

  

### 3.2 Core层模块

  

| 模块 | 功能 | 职责 |

|------|------|------|

| FileSystem | 文件系统 | 管理目录树结构、路径解析、目录切换 |

| FileManager | 文件管理器 | 文件CRUD操作、权限验证、调用文件保护 |

| UserManager | 用户管理器 | 用户登录/登出、用户增删、权限判断 |

| FileProtection | 文件保护 | 读写锁管理、并发控制、锁状态查询 |

  

### 3.3 Model层模块

  

| 模块 | 功能 | 职责 |

|------|------|------|

| FileNode | 文件节点 | 存储文件属性（名称、内容、权限、时间等） |

| DirectoryNode | 目录节点 | 继承FileNode，管理子节点集合 |

| Permission | 权限 | rwx权限的存储和计算 |

| User | 用户 | 用户属性（用户名、密码、用户组） |

  

---

  

## 4. UML图

  

### 4.1 类图

  

```

┌────────────────────────────────────────────────────────────────────────┐

│ FileNode │

├────────────────────────────────────────────────────────────────────────┤

│ - name: String │

│ - content: String │

│ - permission: Permission │

│ - owner: String │

│ - group: String │

│ - createTime: long │

│ - modifyTime: long │

│ - parent: DirectoryNode │

├────────────────────────────────────────────────────────────────────────┤

│ + getName(): String │

│ + setContent(content: String): void │

│ + getPermission(): Permission │

│ + isDirectory(): boolean │

│ + getAbsolutePath(): String │

└────────────────────────────────────────────────────────────────────────┘

△

│ 继承

│

┌────────────────────────────────────────────────────────────────────────┐

│ DirectoryNode │

├────────────────────────────────────────────────────────────────────────┤

│ - children: Map<String, FileNode> │

├────────────────────────────────────────────────────────────────────────┤

│ + getChild(name: String): FileNode │

│ + addChild(node: FileNode): void │

│ + removeChild(name: String): void │

│ + getChildrenList(): List<FileNode> │

└────────────────────────────────────────────────────────────────────────┘

  

┌────────────────────────────────────────────────────────────────────────┐

│ Permission │

├────────────────────────────────────────────────────────────────────────┤

│ - ownerRead, ownerWrite, ownerExecute: boolean │

│ - groupRead, groupWrite, groupExecute: boolean │

│ - othersRead, othersWrite, othersExecute: boolean │

├────────────────────────────────────────────────────────────────────────┤

│ + setMode(mode: int): void │

│ + canRead(user: User, owner: String, group: String): boolean │

│ + canWrite(user: User, owner: String, group: String): boolean │

│ + toSymbolic(): String │

│ + toNumeric(): int │

└────────────────────────────────────────────────────────────────────────┘

  

┌────────────────────────────────────────────────────────────────────────┐

│ FileProtection │

├────────────────────────────────────────────────────────────────────────┤

│ - fileLocks: Map<String, ReentrantReadWriteLock> │

│ - readCount: Map<String, Integer> │

│ - writeCount: Map<String, Integer> │

├────────────────────────────────────────────────────────────────────────┤

│ + acquireReadLock(path: String): void │

│ + releaseReadLock(path: String): void │

│ + acquireWriteLock(path: String): void │

│ + releaseWriteLock(path: String): void │

│ + getLockStatus(path: String): String │

└────────────────────────────────────────────────────────────────────────┘

```

  

### 4.2 用例图

  

```

┌─────────────────────────────────────┐

│ 多用户文件系统 │

└─────────────────────────────────────┘

│

┌─────────────────────────────────┼─────────────────────────────────┐

│ │ │

▼ ▼ ▼

┌───────────────┐ ┌───────────────┐ ┌───────────────┐

│ 文件操作 │ │ 用户管理 │ │ 权限管理 │

├───────────────┤ ├───────────────┤ ├───────────────┤

│ ○ 创建文件 │ │ ○ 用户登录 │ │ ○ 修改权限 │

│ ○ 读取文件 │ │ ○ 用户登出 │ │ ○ 修改所有者 │

│ ○ 写入文件 │ │ ○ 添加用户 │ │ ○ 权限检查 │

│ ○ 删除文件 │ │ ○ 删除用户 │ └───────────────┘

│ ○ 创建目录 │ │ ○ 查看用户 │

│ ○ 切换目录 │ └───────────────┘

│ ○ 列出目录 │

└───────────────┘

△ △

│ │

└───────────────┬─────────────────┘

│

┌─────────┐

│ 用户 │

│(Actor) │

└─────────┘

```

  

### 4.3 顺序图

  

#### 4.3.1 文件读取顺序图

  

```

用户 Terminal CommandExecutor FileManager FileProtection FileNode

│ │ │ │ │ │

│──cat file.txt─▶ │ │ │ │

│ │ │ │ │ │

│ │──execute()───▶│ │ │ │

│ │ │ │ │ │

│ │ │──readFile()───▶│ │ │

│ │ │ │ │ │

│ │ │ │──权限检查──────▶│ │

│ │ │ │◀───允许────────│ │

│ │ │ │ │ │

│ │ │ │──acquireReadLock()───────────▶│

│ │ │ │◀──────锁定成功──────────────────│

│ │ │ │ │ │

│ │ │ │──getContent()──────────────────────────▶│

│ │ │ │◀───────────返回内容───────────────────────│

│ │ │ │ │ │

│ │ │ │──releaseReadLock()──────────▶│

│ │ │ │◀──────释放成功──────────────────│

│ │ │ │ │ │

│ │ │◀──返回内容────│ │ │

│ │◀──显示内容───│ │ │ │

│◀──输出────────│ │ │ │ │

```

  

#### 4.3.2 用户登录顺序图

  

```

用户 Terminal CommandExecutor UserManager

│ │ │ │

│──login alice──▶ │ │

│ │ │ │

│ │──execute()───▶│ │

│ │ │ │

│ │ │──login()──────▶│

│ │ │ │

│ │ │ │──查找用户

│ │ │ │──设置currentUser

│ │ │ │

│ │ │◀──返回true────│

│ │ │ │

│ │◀──登录成功───│ │

│◀──显示结果────│ │ │

```

  

---

  

## 5. 数据结构

  

### 5.1 文件节点模块 (FileNode)

  

| 变量名 | 类型 | 作用 | 说明 |

|--------|------|------|------|

| `name` | String | 文件名 | 存储文件或目录的名称 |

| `content` | String | 文件内容 | 存储文件的文本内容 |

| `permission` | Permission | 权限对象 | 控制读/写/执行权限 |

| `owner` | String | 所有者 | 文件的拥有者用户名 |

| `group` | String | 用户组 | 文件所属的用户组 |

| `createTime` | long | 创建时间 | 文件创建的时间戳 |

| `modifyTime` | long | 修改时间 | 最后修改的时间戳 |

| `parent` | DirectoryNode | 父目录 | 指向父目录的引用，用于构建树结构 |

  

### 5.2 目录节点模块 (DirectoryNode)

  

| 变量名 | 类型 | 作用 | 说明 |

|--------|------|------|------|

| `children` | Map<String, FileNode> | **共享变量** | 存储子节点的HashMap，键为文件名，值为节点对象 |

  

### 5.3 权限模块 (Permission)

  

| 变量名 | 类型 | 作用 | 说明 |

|--------|------|------|------|

| `ownerRead` | boolean | 所有者读权限 | true表示允许读 |

| `ownerWrite` | boolean | 所有者写权限 | true表示允许写 |

| `ownerExecute` | boolean | 所有者执行权限 | true表示允许执行 |

| `groupRead/Write/Execute` | boolean | 用户组权限 | 同上 |

| `othersRead/Write/Execute` | boolean | 其他人权限 | 同上 |

  

### 5.4 文件保护模块 (FileProtection) - 互斥控制

  

| 变量名 | 类型 | 作用 | 说明 |

|--------|------|------|------|

| `fileLocks` | Map<String, ReentrantReadWriteLock> | **互斥变量** | 每个文件路径对应一个读写锁 |

| `readCount` | Map<String, Integer> | **共享变量** | 记录每个文件当前的读者数量 |

| `writeCount` | Map<String, Integer> | **共享变量** | 记录每个文件当前的写者数量 |

  

**互斥原理**：

- `ReentrantReadWriteLock.readLock()` - 读锁，多个线程可同时获取

- `ReentrantReadWriteLock.writeLock()` - 写锁，独占锁，与读锁互斥

  

### 5.5 用户管理模块 (UserManager)

  

| 变量名 | 类型 | 作用 | 说明 |

|--------|------|------|------|

| `users` | Map<String, User> | 用户列表 | 存储所有用户，键为用户名 |

| `currentUser` | User | **共享变量** | 当前登录的用户，全局唯一 |

  

### 5.6 文件管理模块 (FileManager)

  

| 变量名 | 类型 | 作用 | 说明 |

|--------|------|------|------|

| `openFiles` | Map<Integer, OpenFile> | 打开文件表 | 文件描述符映射到打开的文件 |

| `nextFd` | int | 下一个文件描述符 | 从3开始递增（0,1,2保留） |

  

---

  

## 6. 关键技术

  

### 6.1 文件保护机制（读写锁）

  

#### 6.1.1 为什么需要文件保护？

  

在多用户系统中，多个用户可能同时访问同一个文件。如果不加控制，可能出现以下问题：

- **数据不一致**：一个用户正在写入时，另一个用户读取到不完整的数据

- **数据丢失**：两个用户同时写入，后写入的覆盖先写入的内容

  

**文件保护的目标**：

- **读读允许**：多个用户可以同时读取同一文件（读操作不修改数据）

- **读写互斥**：有用户在写入时，其他用户不能读取

- **写写互斥**：同时只能有一个用户写入

  

#### 6.1.2 基本原理

  

使用**读写锁（ReadWriteLock）**实现：

- 读锁是**共享锁**：多个线程可同时持有

- 写锁是**独占锁**：只能一个线程持有，且与读锁互斥

  

```

┌─────────────────────────────────────────┐

│ 读写锁状态机 │

├─────────────────────────────────────────┤

│ │

│ ┌──────────┐ 获取读锁 ┌────────┐ │

│ │ 无锁定 │──────────────▶│ 读锁定 │ │

│ └──────────┘◀──────────────└────────┘ │

│ │ 释放读锁 │ │

│ │ │ │

│ 获取写锁 │ 阻塞 │

│ │ │ │

│ ▼ │ │

│ ┌──────────┐ │ │

│ │ 写锁定 │◀─────────────────┘ │

│ └──────────┘ │

│ │ │

│ │ 释放写锁 │

│ ▼ │

│ ┌──────────┐ │

│ │ 无锁定 │ │

│ └──────────┘ │

└─────────────────────────────────────────┘

```

  

#### 6.1.3 实现步骤

  

1. 为每个文件路径创建一个读写锁

2. 读取文件前，获取读锁

3. 写入文件前，获取写锁

4. 操作完成后，释放锁

  

#### 6.1.4 代码实现

  

```java

@Service

public class FileProtection {

// 互斥变量：每个文件路径对应一个读写锁

private Map<String, ReentrantReadWriteLock> fileLocks;

// 获取或创建文件的读写锁

private ReentrantReadWriteLock getLock(String path) {

// computeIfAbsent：如果不存在则创建新锁

return fileLocks.computeIfAbsent(path, k -> new ReentrantReadWriteLock());

}

/**

* 获取读锁 - 允许多个读者同时读取

*/

public void acquireReadLock(String path) {

ReentrantReadWriteLock lock = getLock(path);

lock.readLock().lock(); // 获取读锁（共享锁）

}

/**

* 释放读锁

*/

public void releaseReadLock(String path) {

ReentrantReadWriteLock lock = fileLocks.get(path);

if (lock != null) {

lock.readLock().unlock(); // 释放读锁

}

}

/**

* 获取写锁 - 独占访问，与读锁互斥

*/

public void acquireWriteLock(String path) {

ReentrantReadWriteLock lock = getLock(path);

lock.writeLock().lock(); // 获取写锁（独占锁）

}

/**

* 释放写锁

*/

public void releaseWriteLock(String path) {

ReentrantReadWriteLock lock = fileLocks.get(path);

if (lock != null) {

lock.writeLock().unlock(); // 释放写锁

}

}

}

```

  

**在FileManager中使用**：

  

```java

public String readFile(String path) {

// ... 权限检查 ...

String absolutePath = node.getAbsolutePath();

// 获取读锁（允许多个读者同时读）

fileProtection.acquireReadLock(absolutePath);

try {

return node.getContent(); // 读取文件内容

} finally {

// 确保释放锁，即使发生异常

fileProtection.releaseReadLock(absolutePath);

}

}

  

public boolean writeFile(String path, String content) {

// ... 权限检查 ...

String absolutePath = node.getAbsolutePath();

// 获取写锁（独占访问）

fileProtection.acquireWriteLock(absolutePath);

try {

node.setContent(content); // 写入文件内容

return true;

} finally {

// 确保释放锁

fileProtection.releaseWriteLock(absolutePath);

}

}

```

  

---

  

### 6.2 权限控制机制

  

#### 6.2.1 为什么需要权限控制？

  

在多用户系统中，不同用户有不同的访问需求：

- 用户的私人文件不应被其他人访问

- 系统文件不应被普通用户修改

- 共享文件需要控制谁可以读、谁可以写

  

**Linux权限模型**采用**三组权限**：

- **所有者权限（Owner）**：文件创建者的权限

- **用户组权限（Group）**：同组用户的权限

- **其他人权限（Others）**：其他所有用户的权限

  

每组包含**3种权限**：

- **r（读）**：可以读取文件内容

- **w（写）**：可以修改文件内容

- **x（执行）**：可以执行文件（对目录表示可以进入）

  

#### 6.2.2 权限表示

  

| 格式 | 示例 | 含义 |

|------|------|------|

| 符号格式 | `rwxr-xr--` | 所有者rwx，组r-x，其他r-- |

| 数字格式 | `754` | r=4, w=2, x=1，累加得到数字 |

  

**数字计算**：

- `rwx` = 4+2+1 = 7

- `r-x` = 4+0+1 = 5

- `r--` = 4+0+0 = 4

  

#### 6.2.3 代码实现

  

```java

public class Permission {

// 9个布尔变量存储权限

private boolean ownerRead, ownerWrite, ownerExecute;

private boolean groupRead, groupWrite, groupExecute;

private boolean othersRead, othersWrite, othersExecute;

/**

* 根据数字模式设置权限（如 755）

*/

public void setMode(int mode) {

// 分离三位数字

int owner = (mode / 100) % 10; // 百位：所有者权限

int group = (mode / 10) % 10; // 十位：组权限

int others = mode % 10; // 个位：其他人权限

// 使用位运算解析权限

// 4=100(二进制)表示读，2=010表示写，1=001表示执行

ownerRead = (owner & 4) != 0; // 检查第3位

ownerWrite = (owner & 2) != 0; // 检查第2位

ownerExecute = (owner & 1) != 0; // 检查第1位

groupRead = (group & 4) != 0;

groupWrite = (group & 2) != 0;

groupExecute = (group & 1) != 0;

othersRead = (others & 4) != 0;

othersWrite = (others & 2) != 0;

othersExecute = (others & 1) != 0;

}

/**

* 检查用户是否有读权限

*/

public boolean canRead(User user, String fileOwner, String fileGroup) {

// root用户拥有所有权限

if (user.isRoot()) return true;

// 按优先级检查：所有者 > 用户组 > 其他人

if (user.getUsername().equals(fileOwner)) {

return ownerRead;

}

if (user.getGroup().equals(fileGroup)) {

return groupRead;

}

return othersRead;

}

}

```

  

---

  

### 6.3 树状目录结构

  

#### 6.3.1 为什么使用树状结构？

  

文件系统需要层次化组织文件：

- 用户可以创建文件夹来分类管理文件

- 支持相对路径和绝对路径

- 方便权限的层级管理

  

**树结构的特点**：

- 有且只有一个根节点（/）

- 每个节点有一个父节点（根节点除外）

- 目录节点可以有多个子节点

  

#### 6.3.2 数据结构设计

  

```

根目录 (/)

├── home/

│ ├── alice/

│ │ └── file1.txt

│ └── bob/

├── etc/

└── tmp/

```

  

使用**HashMap**存储子节点，实现O(1)的查找效率。

  

#### 6.3.3 代码实现

  

```java

public class DirectoryNode extends FileNode {

// 使用HashMap存储子节点，键为文件名，值为节点对象

private Map<String, FileNode> children;

public DirectoryNode(String name, String owner, String group) {

super(name, owner, group);

this.children = new HashMap<>();

}

/**

* 添加子节点

*/

public void addChild(FileNode node) {

// 设置子节点的父引用，形成双向链接

node.setParent(this);

// 以文件名为键存储

children.put(node.getName(), node);

}

/**

* 获取子节点

*/

public FileNode getChild(String name) {

return children.get(name); // O(1)时间复杂度

}

/**

* 删除子节点

*/

public void removeChild(String name) {

FileNode child = children.remove(name);

if (child != null) {

child.setParent(null); // 断开父引用

}

}

}

```

  

**路径解析实现**：

  

```java

public FileNode resolvePath(String path) {

// 确定起始目录

DirectoryNode startDir;

if (path.startsWith("/")) {

startDir = root; // 绝对路径从根目录开始

path = path.substring(1); // 去掉开头的/

} else {

startDir = currentDir; // 相对路径从当前目录开始

}

// 按/分割路径

String[] parts = path.split("/");

FileNode current = startDir;

for (String part : parts) {

if (part.equals(".")) {

continue; // 当前目录，不变

}

if (part.equals("..")) {

// 上级目录

current = current.getParent();

if (current == null) current = root;

continue;

}

// 查找子节点

if (!(current instanceof DirectoryNode)) {

return null; // 路径无效

}

current = ((DirectoryNode) current).getChild(part);

if (current == null) {

return null; // 路径不存在

}

}

return current;

}

```

  

---

  

### 6.4 Spring Boot 依赖注入

  

#### 6.4.1 为什么使用依赖注入？

  

传统方式中，对象自己创建依赖：

```java

// 传统方式：硬编码依赖关系

public class Terminal {

private FileSystem fs = new FileSystem(); // 紧耦合

}

```

  

问题：

- 类之间**紧耦合**，难以测试和替换

- 依赖关系**分散**在各个类中，难以管理

  

**依赖注入**的解决方案：

- 由**容器**负责创建对象和注入依赖

- 类只声明需要什么依赖，不关心如何获取

- 实现**松耦合**，便于测试和维护

  

#### 6.4.2 Spring DI 原理

  

```

┌──────────────────────────────────────────┐

│ Spring IoC 容器 │

├──────────────────────────────────────────┤

│ 1. 扫描@Component/@Service等注解 │

│ 2. 创建Bean实例 │

│ 3. 分析构造器参数，注入依赖 │

│ 4. 完成所有Bean的初始化 │

└──────────────────────────────────────────┘

```

  

#### 6.4.3 代码实现

  

```java

// 标记为Spring管理的服务

@Service

public class FileManager {

// 声明依赖（final确保只能通过构造器注入）

private final FileSystem fileSystem;

private final UserManager userManager;

private final FileProtection fileProtection;

// Spring自动调用此构造器，注入依赖

public FileManager(FileSystem fileSystem,

UserManager userManager,

FileProtection fileProtection) {

this.fileSystem = fileSystem;

this.userManager = userManager;

this.fileProtection = fileProtection;

}

}

  

// 应用入口

@SpringBootApplication

public class FileSystemApplication implements CommandLineRunner {

private final Terminal terminal;

// 构造器注入Terminal

public FileSystemApplication(Terminal terminal) {

this.terminal = terminal;

}

public static void main(String[] args) {

// 启动Spring容器

SpringApplication.run(FileSystemApplication.class, args);

}

@Override

public void run(String... args) {

// 容器初始化完成后自动调用

terminal.start();

}

}

```

  

---

  

## 7. 运行说明

  

### 7.1 环境要求

  

- JDK 21+

- Maven 3.6+

  

### 7.2 编译运行

  

```bash

cd /home/erzhuochen/workspace/java/os

  

# 使用Maven运行

mvn spring-boot:run

  

# 或打包后运行

mvn clean package -DskipTests

java -jar target/multi-user-filesystem-1.0.0.jar

```

  

### 7.3 基本命令

  

```bash

help # 查看帮助

pwd # 显示当前路径

ls [-l] # 列出目录

cd <path> # 切换目录

mkdir <name> # 创建目录

touch <name> # 创建文件

cat <file> # 查看文件

echo "text" > f # 写入文件

chmod 755 <file> # 修改权限

login <user> # 登录用户

exit # 退出系统

```