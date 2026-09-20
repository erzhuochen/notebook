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
