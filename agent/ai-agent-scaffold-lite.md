# 整体架构

app中通过config注入配置，并通过`onApplicationEvent`执行决策树进行agent的初始化
决策树在domain中定义









---

- 2-1 创建项目
- 2-2 了解Spring AI等API
- 2-3 设置智能体的配置属性和注入
- 2-4 规则树脚手架的配置
- 2-5 api节点装填
- 2-6 model节点装填，重点是mcp的装填
- 2-7 agent节点装填
- 2-8 装配域节点AgentWorkflowNode(1)
- 2-9 (2) Loop, Parallel, Sequential装填
- 2-10 (3) Runner装填
- 2-11
  ```text
  config: 注入配置，并装填进service
	  -> service: 接收config中传入的配置，利用工厂创建agent示例
		  -> factory
test -> 调用被注入成bean的agent实例进行测试
  ```
- 2-12 原本runner强制指定agent，现在把它解耦了，让它能够在配置中设置

## 2-13 增强装配-AgentWorkflowNode
把 workflow 节点之间"两两互指"的**网状路由**，重构为以 AgentWorkflowNode 为中枢的**星型回环**调度，从此支持任意数量、任意顺序、可嵌套的 workflow

### 一、旧版的痛点（2-8 / 2-9 遗留）

  1. **破坏性消费**：每个节点用 `agentWorkflows.remove(0)` 取任务，把上下文里的 List 就地删空了 —— 配置被改写，不可重放、不可回溯。
  2. **O(n²) 互相耦合**：每个 workflow 节点的 `get()` 里都抄了一份"看下一个是什么类型 → switch 到兄弟节点"的代码。Loop 要认识 Parallel/Sequential，Parallel 要认识 Loop/Sequential……n 个类型就要写 n×(n-1) 条边。
  3. **扩展性差**：将来新增一种 workflow 类型，得回头改所有已有节点的 switch。
  4. `SequentialAgentNode.get()` 甚至直接写死 `return runnerNode` —— 等于规定 sequential 只能排在最后，排在它后面的 workflow 会被静默丢弃。**而本节的 demo 恰恰是 parallel 后面跟 sequential，不重构就跑不起来。**

### 二、新版做法：游标 + 中枢

  `DynamicContext` 里的 `List<AgentWorkflow> agentWorkflows` 换成两个字段：

  ```java
  private AtomicInteger currentStepIndex = new AtomicInteger(0);          // 走到第几个了
  private AiAgentConfigTableVO.Module.AgentWorkflow currentAgentWorkflow; // 当前该装配哪个
  ```

  - `AgentWorkflowNode.doApply()` 变成**循环控制器**：`index >= size` 就把 `currentAgentWorkflow` 置 null（表示没活了），否则取 `list.get(index)` 塞进上下文、然后 `index++`。原始配置 List 全程只读。
  - `AgentWorkflowNode.get()` 变成**纯分发器**：`currentAgentWorkflow == null` → 交给 RunnerNode 收尾；否则按 type 分发到 Loop / Parallel / Sequential。
  - 兜底分支也从 `default -> defaultStrategyHandler` 改成 `default -> runnerNode`，保证任何情况下都能走到终点产出 Runner。

### 三、啊哈时刻：一坨 switch 塌缩成一行

  ```java
  // ❌ 旧：Loop / Parallel 两个节点里各抄了一份这样的代码
  public StrategyHandler<...> get(...) {
      List<AgentWorkflow> agentWorkflows = dynamicContext.getAgentWorkflows();
      if (null == agentWorkflows || agentWorkflows.isEmpty()) return defaultStrategyHandler;
      String node = AgentTypeEnum.formType(agentWorkflows.get(0).getType()).getNode();
      return switch (node) {
          case "parallelAgentNode"   -> getBean("parallelAgentNode");
          case "sequentialAgentNode" -> getBean("sequentialAgentNode");
          default -> defaultStrategyHandler;
      };
  }

  // ✅ 新：Loop / Parallel / Sequential 三个节点统统只剩这一行
  public StrategyHandler<...> get(...) {
      return getBean("agentWorkflowNode");
  }
  ```

  子节点从此**只负责"建 agent"，不负责"决定下一步"** —— 单一职责。路由知识收敛到中枢一处，新增类型只需改 AgentWorkflowNode 的 switch + 枚举。

### 四、节点流转图（星型回环）

  ```text
                          AgentNode
                              │
                              ▼
         ┌──────────► AgentWorkflowNode ─────────► RunnerNode ─► AiAgentRegisterVO
         │            取第 index 个，index++        (currentAgentWorkflow == null)
         │                   │
         │                   │ 按 type 分发
         │         ┌─────────┼──────────┐
         │         ▼         ▼          ▼
         │  LoopAgentNode Parallel   Sequential
         │         │         │          │
         └─────────┴─────────┴──────────┘
              全部 return getBean("agentWorkflowNode")
  ```

  > 对比：旧版这里是三个子节点**两两互指**的网状，且没有回到中枢的边，所以只能"一趟走完"，走不了循环。

### 五、验证场景：`parallel_research_app.yml`（新增 demo）

  嵌套 workflow —— sequential 里套 parallel，正好证明重构有效（旧版第 2 个 workflow 根本轮不到装配）：

  ```yaml
  agent-workflows:
    - type: parallel            # 先并行跑 3 个研究 agent
      name: ParallelWebResearchAgent
      sub-agents: [ RenewableEnergyResearcher, EVResearcher, CarbonCaptureResearcher ]
    - type: sequential          # 再串行：并行结果 → 汇总 agent
      name: ResearchAndSynthesisPipeline
      sub-agents: [ ParallelWebResearchAgent, SynthesisAgent ]
  runner:
    agent-name: ResearchAndSynthesisPipeline
  ```

  **agent 间数据怎么传？** 靠 ADK 的 `output-key` + instruction 占位符：
  - 每个研究 agent 声明 `output-key: renewable_energy_result`，它的输出会写进 session state。
  - 汇总 agent 的 instruction 里写 `{renewable_energy_result}`，运行时被自动替换成上游结果。
  - 注意装配顺序的隐含约束：`queryAgentList()` 是从 `agentGroup` 这个 Map 按名字查的，所以 **被引用的 workflow 必须先于引用者装配**（parallel 必须写在 sequential 前面），否则查出来是空列表且不报错。

  另外 `application-dev.yml` 里 `spring.config.import` 改成只导入这一个 yml，`test-agent.yml` 的 key 从 `testAgent` 改名 `testAgent01`（避免多份配置的 key 冲突）。

### 六、待深究

  `SequentialAgentNode` 里的 `registerBean(name, SequentialAgent.class, sequentialAgent)` 这次被**删掉了** —— 属于只看提交信息会漏、读 diff 才能发现的行为变更。结论是安全的：`RunnerNode.getRunner()` 走的是 `dynamicContext.getAgentGroup().get(agentName)`，不查 Spring 容器。但副作用是 **workflow agent 不再是 Spring Bean，无法被 `@Resource` / `getBean(name)` 注入**。回头如果要在别处直接拿某个 workflow agent，需要自己补回注册。（顺带：为什么只有 Sequential 注册过而 Loop/Parallel 没有？大概率是之前写的时候不统一，这次顺手抹平了。）

## 2-14 增强装配-本地mcp
把 `ChatModelNode` 里那个 88 行的 if-else MCP 构建方法，拆成**策略模式**（接口 + 三实现 + 工厂）；并借机新增 `local` 类型——让 Spring 容器里用 `@Tool` 写的本地方法，也能当 MCP 工具喂给大模型

### 一、旧版的痛点（2-6 遗留）

`ChatModelNode.createMcpSyncClient()` 是个典型的"什么都往里塞"的私有方法：

1. **类型判断和构建逻辑糊在一起**：`if (null != sseConfig) {...}` / `if (null != stdioConfig) {...}`，每加一种传输方式就往里加一个 if 分支，方法无限膨胀。
2. **ChatModelNode 职责失焦**：它本该只干"造 ChatModel"这一件事，结果一半篇幅在处理 MCP 协议细节（URL 解析、SSE endpoint 拼接、Stdio 进程参数）。
3. **藏着一个真 bug**：stdio 分支里 `mcpSyncClient.initialize()` 之后**忘了 `return`**，执行流直接掉到方法末尾的 `throw new RuntimeException("tool mcp sse and stdio is null!")`。换句话说 **stdio 类型配了也用不了**，这次重构顺手修掉了。

### 二、做法：接口 + 三实现 + 工厂

```java
// 统一接口：入参是配置，出参是大模型能直接用的工具回调
public interface TooMcpCreateService {
    ToolCallback[] buildToolCallback(AiAgentConfigTableVO.Module.ChatModel.ToolMcp toolMcp) throws Exception;
}
```

三个实现各管一种来源，互不认识：

| 实现类 | 来源 | 怎么拿到 ToolCallback |
|---|---|---|
| `SSEToolMcpCreateService` | 远程 HTTP/SSE | `HttpClientSseClientTransport` → `McpSyncClient` → `SyncMcpToolCallbackProvider` |
| `StdioToolMcpCreateService` | 本机子进程 | `StdioClientTransport`（启一个命令行进程）→ 同上 |
| `LocalToolMcpCreateService` | **Spring 容器** | `applicationContext.getBean(name)` 直接取 `ToolCallbackProvider` |

工厂只做"看哪个字段非 null"的分发，不含任何构建逻辑：

```java
public TooMcpCreateService getTooMcpCreateService(ToolMcp toolMcp) {
    if (null != toolMcp.getLocal())  return localToolMcpCreateService;
    if (null != toolMcp.getSse())    return sseToolMcpCreateService;
    if (null != toolMcp.getStdio())  return stdioToolMcpCreateService;
    throw new AppException(ResponseCode.NOT_FOUND_METHOD...);  // 新增 0003 错误码
}
```

`ChatModelNode` 瘦身后只剩"遍历 → 问工厂 → 收集"：

```java
List<ToolCallback> toolCallbackList = new ArrayList<>();
for (ToolMcp toolMcp : toolMcpList) {
    TooMcpCreateService service = defaultMcpClientFactory.getTooMcpCreateService(toolMcp);
    toolCallbackList.addAll(List.of(service.buildToolCallback(toolMcp)));
}
```

### 三、啊哈时刻：抽象层级往上抬了一级

**旧版接口返回 `McpSyncClient`，新版返回 `ToolCallback[]`** —— 这不是顺手改的，是 local 类型逼出来的：

```java
// ❌ 旧：抽象锚在"MCP 客户端"这一层
private McpSyncClient createMcpSyncClient(ToolMcp toolMcp)
// 本地工具压根没有 McpSyncClient（它不走 MCP 协议，就是个本地方法），塞不进这个抽象

// ✅ 新：抽象锚在"大模型能调的工具"这一层
ToolCallback[] buildToolCallback(ToolMcp toolMcp)
// 远程 MCP、子进程 MCP、本地方法，殊途同归都能产出 ToolCallback
```

> **可复用的判断**：选抽象层级时，要挑**所有实现都天然具备的那个共性**，而不是"当前两个实现恰好都有的那个中间产物"。`McpSyncClient` 是 SSE/Stdio 的实现细节，`ToolCallback` 才是使用方（ChatModel）真正要的东西。**按使用方的需求定接口，而不是按现有实现定接口。**

### 四、结构图

```text
                 ChatModelNode
                      │ 遍历 toolMcpList，逐个问工厂
                      ▼
            DefaultMcpClientFactory
             （只判断哪个字段非 null）
                      │
        ┌─────────────┼─────────────┐
     local           sse          stdio
        ▼             ▼             ▼
  LocalToolMcp   SSEToolMcp   StdioToolMcp
  CreateService  CreateService CreateService
        │             │             │
        └─────────────┴─────────────┘
           都实现 TooMcpCreateService
           都返回 ToolCallback[]
                      │
                      ▼
      List<ToolCallback> → OpenAiChatOptions.toolCallbacks()
```

### 五、本地 MCP 怎么写（本节重点）

**第 1 步：写工具方法**，用 `@Tool` 描述能力，用 `@JsonPropertyDescription` 描述参数——这些描述是给**大模型看**的，写清楚它才知道何时调、怎么传参：

```java
@Service
public class MyTestMcpService {
    @Tool(description = "小写字母转换为大写字母")
    public XxxResponse toUpperCase(XxxRequest request) { ... }

    @Data
    public static class XxxRequest {
        @JsonProperty(required = true, value = "word")
        @JsonPropertyDescription("英文单词，字符串，字母。例如: good,xiaofuge")
        private String word;
    }
}
```

**第 2 步：包装成 Bean**，Bean 名字就是后面 yml 里要填的 `name`：

```java
@Bean("myToolCallbackProvider")   // ← 这个名字是配置和代码的接头暗号
public ToolCallbackProvider testTools(MyTestMcpService testService) {
    return MethodToolCallbackProvider.builder().toolObjects(testService).build();
}
```

**第 3 步：yml 里挂上**，和远程 MCP 并列写在同一个列表里：

```yaml
tool-mcp-list:
  - sse:                          # 远程的
      name: baidu-search
      base-uri: http://appbuilder.baidu.com/v2/ai_search/mcp/
  - local:                        # 本地的，只需要一个 bean 名
      name: myToolCallbackProvider
```

**验证**：`application-dev.yml` 切回 `only-one-agent.yml`，测试提问从"给我一份学习计划"改成 **"把xiaofuge转换为大写"** —— 看大模型会不会自己决定去调 `toUpperCase` 这个本地工具。

### 六、待深究

1. **`requestTimeout` 的单位不一致**：同一个配置字段（默认值 3000），SSE 实现用 `Duration.ofMillis(...)` 当**毫秒**（3 秒），Stdio 实现用 `Duration.ofSeconds(...)` 当**秒**（3000 秒 ≈ 50 分钟）。配置里写同一个数字，两种传输方式行为差 1000 倍。这次只是把旧代码平移过来，没统一。自己用的时候留意。
2. **McpSyncClient 没人管生命周期**：SSE/Stdio 实现里 `new` 出来的 client 只用来取一次 ToolCallback，之后既没存起来也没 close。装配是启动时一次性的，暂时不炸；但如果将来支持"运行时重新装配"，这里会漏连接/漏子进程。
3. 接口名 `TooMcpCreateService` 少打了个 `l`（应为 `Tool`）—— 不影响运行，但三个实现类和工厂都跟着这个名字了，将来改名要一起动。

## 2-15 增强装配：Runner Plugin

**主线**：2-15 分支先在配置对象 `Runner` 中增加 `pluginNameList`；再新增 `MyTestPlugin`（继承 `BasePlugin`，重写用户消息、Agent 执行前、模型调用前的回调来记录信息）和 `MyLogPlugin`（继承 ADK 的 `LoggingPlugin`）。`RunnerNode` 根据配置名从 Spring 容器取出这些插件，传给带插件参数的 `InMemoryRunner` 构造器。运行时 ADK 调用插件回调，于是日志等横切逻辑能插入 Agent 执行流程，效果类似 AOP。

```text
Runner.pluginNameList → RunnerNode.getBean(name) → List<BasePlugin>
                       → new InMemoryRunner(baseAgent, appName, plugins)
                       → ADK PluginManager 在 runAsync() 的生命周期节点调用插件
```

### 值得记住的知识点

1. **Runner 与 Plugin 是组合关系**：插件在创建 Runner 时注入，因此作用范围由这个 Runner 决定；业务 Agent 不必为日志等横切逻辑逐个改写。Spring 在这里负责创建和查找插件 Bean，真正触发回调的是 ADK 的执行流程，所以它不是 Spring AOP 代理。
2. **回调不只是“旁观”**：ADK 0.4.0 的 `PluginManager` 按注册顺序运行插件，取第一个非空的 `Maybe` 结果并停止后续插件。`Maybe.empty()` 表示继续正常流程；非空结果的含义取决于回调，例如替换用户消息或提前给出模型响应。`MyTestPlugin` 的三个回调只记录输入、Agent 名和模型名，随后返回基类的空结果，因此目前没有改变执行结果。
3. **注意两个命名空间**：配置里的 `myTestPlugin` 是 Spring Bean 名，供 `RunnerNode` 查找；`BasePlugin` 构造器里的 `MyTestPlugin` 是 ADK 插件名，`PluginManager` 用它识别插件并拒绝重名。两者可以不同，不能混为一谈。
4. **Plugin 与上一节的 ToolCallback 分工不同**：ToolCallback 是提供给模型选择调用的能力；Plugin 是框架在执行边界主动调用的扩展点。`MyLogPlugin` 只是把 ADK 自带的 `LoggingPlugin` 接入这条扩展链。插件 Bean 默认是 Spring 单例，单次调用的数据宜放在回调上下文中，不宜存在插件实例字段里。

## 2-17 会话服务：ChatService

**主线**：本分支补全 `IChatService`，新增 `ChatService` 与 `ChatCommandEntity`。`DefaultArmoryFactory` 增加按 `agentId` 取 `AiAgentRegisterVO` 的方法；`ChatService` 由此拿到装配阶段创建的 `InMemoryRunner`，实现 Agent 列表查询、Session 创建、普通消息、流式消息和多模态消息处理。`ChatCommandEntity` 承载文本、文件 URI、内联字节三类输入；`AgentNode` 同时改用上一节写的 `MySpringAI`，让自定义 MIME 转换真正进入 Agent 的模型调用链。新增的 `ChatServiceTest` 分别演示文本和图片消息。

```text
启动装配：配置 → RunnerNode → Spring Bean：agentId ↦ AiAgentRegisterVO(runner)
运行对话：ChatService → DefaultArmoryFactory.getAiAgentRegisterVO(agentId)
                      → sessionService.createSession / runner.runAsync
                      → Flowable<Event> → 原样返回或阻塞收集为 List<String>
```

### 值得记住的知识点

1. **装配和对话分层**：装配树负责创建并注册 Runner；`ChatService` 只查找和使用已注册的 Runner，不在每次发消息时重新装配 Agent。`AiAgentRegisterVO` 是这两个阶段的接点，里面同时保存 Agent 描述和可执行的 Runner。Agent 列表则直接来自配置表，是配置视图。
2. **Session 是对话上下文的身份**：服务用 Runner 的 `sessionService` 按 `appName`、`userId` 创建 Session，再把 `userId`、`sessionId` 传给 `runAsync` 续聊。当前 `userSessions` 仅以 `userId` 为键；同一用户切换不同 Agent 时可能复用另一个 Runner 的 Session ID，而每个 `InMemoryRunner` 有自己的内存 Session 服务。缓存键至少应包含 `agentId`，内存会话在进程重启后也不会保留。
3. **同一事件流有两种消费方式**：`handleMessageStream` 将 ADK 的 `Flowable<Event>` 交给调用方；返回 `List<String>` 的重载用 `blockingForEach` 等待流结束，并对每个事件调用 `stringifyContent()`。因此这个列表是事件内容的集合，不能直接等同于“最终答案”。接口直接暴露 `Event` / `Flowable`，上层也会依赖 ADK 类型。
4. **多模态输入先统一为 ADK 的 Content**：`ChatCommandEntity` 把文本映射为 `Part.fromText`、文件 URI 映射为 `Part.fromUri`、内联字节映射为 `Part.fromBytes`，再合成 `role="user"` 的消息。文件和字节都要带 MIME 类型；`MySpringAI` 使用上一节的 `MyMessageConverter` 把媒体转换成 Spring AI 可用的 `Media`。
5. **错误边界要看真实调用顺序**：`getAiAgentRegisterVO` 直接调用 Spring 的 `getBean(agentId, ...)`。ID 不存在时它会先抛异常，`ChatService` 后面的 `null` 判断通常不会触发；新增的 `E0001` 因而还没有覆盖这个失败路径。
