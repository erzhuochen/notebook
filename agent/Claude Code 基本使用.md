# Claude Code 基本使用

> 面向 Java 开发的入门笔记 · 整理于 2026-08-30
> 项目栈参考：Spring + Shiro + MyBatis（manager-data / manager-shiro / manager-website）

## 目录

- [一、第一天就该做的：/init](#一第一天就该做的init)
- [二、按开发场景选命令](#二按开发场景选命令)
- [三、输入框的四个前缀](#三输入框的四个前缀)
- [四、三个键盘操作](#四三个键盘操作)
- [五、会话管理](#五会话管理)
- [六、Java 场景实战示例](#六java-场景实战示例)
- [七、给新手的提醒](#七给新手的提醒)
- [附录 A：CodeGraph 配合使用](#附录-acodegraph-配合使用)
- [附录 B：如何把对话存成 Markdown](#附录-b如何把对话存成-markdown)

---

## 一、第一天就该做的：/init

```
/init
```

扫描项目结构，生成 `CLAUDE.md`。该文件会在**每次会话自动加载**，相当于给 Claude 一份项目说明书：模块划分、构建命令、代码规范、踩坑点。

多项目工作区建议**每个项目各跑一次**。

后续发现 Claude 反复搞错某个约定（例如"DAO 层统一用 MyBatis 注解不用 XML"），把它补进 `CLAUDE.md`，之后无需重复说明。

---

## 二、按开发场景选命令

### 2.1 看懂别人的代码

不需要命令，自然语言提问即可：

```
Shiro 的登录鉴权流程是怎么走的？从 Controller 到 Realm
manager-data 里 OrderMapper 的 SQL 是在哪定义的
这个 @Transactional 为什么没生效
```

### 2.2 提交 PR 之前：`/code-review`

```
/code-review              # 审当前改动
/code-review high         # 更严格，覆盖面更广
/code-review --fix        # 审完直接把问题改掉
/code-review --comment    # 以 inline comment 形式发到 PR
```

**新人刚需。** 先自查一遍，挡掉空指针、事务边界、并发、资源未关闭这类低级问题，再交给 mentor review。

效果分级：`low` / `medium` 更少但更确定的问题；`high` / `max` 覆盖面更广，可能包含不确定的推测。

### 2.3 只想让代码更干净：`/simplify`

```
/simplify
```

与 `/code-review` 的区别：**不找 bug**，只做质量重构——消除重复、简化逻辑、复用已有工具类。适合写完"能跑但很丑"的代码之后。

### 2.4 涉及登录/权限/加密：`/security-review`

```
/security-review
```

改到鉴权、密码、Session、SQL 拼接时跑一下。Shiro 相关改动尤其建议。

### 2.5 想看改动真跑起来：`/run`

```
/run
```

启动项目并验证改动生效，而不只是"测试通过"。

---

## 三、输入框的四个前缀

比记命令更实用。

| 前缀 | 作用 | 示例 |
|---|---|---|
| `!` | 直接执行 shell，输出进入对话 | `!mvn -q compile` |
| `@` | 引用文件/目录，触发路径补全 | `帮我看看 @UserServiceImpl.java` |
| `#` | 快速写入记忆 | `# 本项目 JDK 是 8，别用 var` |
| `/` | 命令菜单，**打个斜杠就能看全量列表** | `/` |

> `!` 尤其好用：`!mvn test` 后的报错堆栈会直接落入对话，Claude 能立刻分析，不用手动复制粘贴。

---

## 四、三个键盘操作

| 按键 | 作用 |
|---|---|
| `Shift + Tab` | 循环切换权限模式，重点是进入 **Plan Mode（计划模式）** |
| `Esc` | 打断当前执行。发现跑偏立刻按，别等它跑完 |
| `Esc` `Esc` | 回退到之前的状态（撤销 Claude 做的改动） |

**Plan Mode 是安全带。** 该模式下 Claude 只读不写，先输出方案与你对齐，确认后才动手。改动较大的需求务必先进 Plan Mode，否则可能一口气改十个文件而方向是错的。

---

## 五、会话管理

| 命令 | 场景 |
|---|---|
| `/clear` | **换任务时必按。** 清空上下文重开，否则旧上下文会干扰判断 |
| `/compact` | 同一任务聊太长，压缩历史但保留结论 |
| `/resume` | 恢复之前的会话（接着昨天没做完的） |
| `/cost` | 查看本次会话消耗的 token |
| `/model` | 切换模型。简单活切快的，硬骨头切强的 |
| `/config` | 配置项（主题、模型等） |
| `/export` | 导出整个会话到文件或剪贴板 |
| `/mcp` | 管理 MCP 服务器 |
| `/agents` | 管理子 agent |
| `/status` | 查看当前会话状态 |

> **核心习惯：一个会话 = 一个任务。** `/clear` 是新手最容易忽略的命令。

---

## 六、Java 场景实战示例

### 写单元测试

```
给 OrderServiceImpl.createOrder 写 JUnit 5 + Mockito 单测，
覆盖库存不足和重复下单两个分支
```

### 排查异常

```
!cat error.log
```
```
这个 LazyInitializationException 是怎么来的，怎么修
```

### 理解遗留 SQL

```
@OrderMapper.xml 这个多表关联查询在做什么，能不能加索引优化
```

### 批量重构

```
把 manager-data 里所有 System.out.println 换成 slf4j 的 log.debug
```

### 写 Git 提交

```
帮我提交一下，commit message 按项目现有风格写
```

---

## 七、给新手的提醒

1. **Plan Mode 是安全带。**
   需求规模超过"改一个方法"，先 `Shift+Tab` 进计划模式。看完方案再放行，比事后 review 一堆错误改动省事。

2. **不要全盘信任生成的代码。**
   可能编译不过，或不符合团队规范。养成 `!mvn compile` / `!mvn test` 验证的习惯——这也是 mentor 会问你的第一个问题。

3. **把踩过的坑写进 `CLAUDE.md`。**
   例如"本项目 Spring 版本低，不支持 XX 写法"。写一次永久生效，比每次会话重新解释强。

---

## 附录 A：CodeGraph 配合使用

CodeGraph 是一个本地代码知识图谱（SQLite + tree-sitter），一次调用返回**相关符号的带行号源码 + 调用链 + 影响范围**，替代 grep + 逐个读文件的往返。

仓库地址：https://github.com/colbymchenry/codegraph

### 安装三步

```bash
# 1. 装 CLI（Windows PowerShell）
irm https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.ps1 | iex

# 2. 接入 agent（自动识别 Claude Code）
codegraph install

# 3. 逐个项目建索引
cd your-project && codegraph init
```

> `init` = 创建 `.codegraph/` + 建图，一步到位。之后自带文件监听器自动增量同步，不需要手动 `sync`。新索引会被实时识别，**无需重启 Claude Code**。

### 建完之后怎么用

**什么都不用做，正常提问即可。** 只要目录下存在 `.codegraph/`，Claude 会在 grep / 读文件之前优先调用它。

多项目工作区注意：workspace 根目录本身没有索引，提问时**带上项目名**能省一轮猜测。

### 常用 CLI 命令

```bash
codegraph status                    # 索引统计、待同步情况
codegraph explore "OrderService"    # 源码 + 调用链
codegraph impact UserService.login  # 改动的爆炸半径
codegraph affected                  # 受影响的测试文件（可接 git diff 做 CI 门禁）
codegraph query <keyword>           # 符号搜索
codegraph node <symbol|file>        # 单个符号的源码 + 调用者
```

CI 示例：

```bash
AFFECTED=$(git diff --name-only HEAD | codegraph affected --stdin --quiet)
if [ -n "$AFFECTED" ]; then npx vitest run $AFFECTED; fi
```

### 两个注意点

- **上下文权衡。** 官方文档明确说明：处理的 token 总量下降（少了大量 grep/Read 往返），但**常驻上下文增长约 80%**（一次返回完整源码而非片段）。长会话 + 小上下文窗口需心里有数。
- **别让 Claude 派 sub-agent 去读文件。** 那样等于绕过 CodeGraph，收益归零。

---

## 附录 B：如何把对话存成 Markdown

**问题：** 从终端直接复制 Claude 的回复，粘贴出来不是 Markdown 格式。

**原因：** 终端里看到的是**渲染后的结果**，不是源码。`**加粗**` 已被转成 ANSI 转义序列，表格的 `|` 已被转成 `─│┌┐` 制表符。复制到的是渲染产物，Markdown 符号在渲染那一步就被消耗了。等同于在浏览器里复制网页文字拿不到 HTML。

### 解决办法

| 方式 | 做法 | 适用场景 |
|---|---|---|
| **让 Claude 写文件**（推荐） | `把刚才的内容写成 markdown 存到 D:\notes\xxx.md` | 存单篇笔记，还能顺手让它调整结构 |
| `/export` | 导出整个会话到文件或剪贴板 | 完整对话留档，但会带上工具调用等噪音 |
| 翻原始记录 | `C:\Users\<用户名>\.claude\projects\<项目>\*.jsonl` | 批量脚本处理历史会话，日常用不上 |

`.jsonl` 一行一条消息，存的是**未渲染的原始 Markdown**。
