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