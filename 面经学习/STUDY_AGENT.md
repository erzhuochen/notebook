大家好，我是技术UP主小傅哥。

本篇内容，为伙伴们推荐一套 AI 从通识、应用、项目，全套流程路线。你可以刷到 AI 八股，也可以学会 AI VibeCoding 编程，还能实践各类 AI 项目。如，市面的 AI IDE（walissh、walicode）教你做一套市面上的 trae.ai/qcoder 一样的编程工具。WaLiAPI（LLM 负载、日志审计、RAG 知识库）、AI MCP Gateway 教你如何构建 AI Infra 基础设施。

这里的所有内容，所有的项目，都从 [bugstack.cn (opens new window)](https://bugstack.cn/)实战项目进入学习；

![](https://bugstack.cn/images/article/project/ai-agent-scaffold/part-1/1-1/images/ai-agent-scaffold-1-1-10.png)

- 首先，小白推荐先进入 AI Agent Guide 基础认知教程：[ai-agent-guide.xiaofuge.cn (opens new window)](https://ai-agent-guide.xiaofuge.cn/)- 涵盖基础概念、八股、面试内容。
- 之后，如果没有使用过 AI IDE 工具，可以做下 AI 新范式，通过 AI 实践来锻炼。
- 最后，可以通过项目驱动学习，结果导向的项目实战，可以更好的锻炼 AI 技能，也是为转岗到 AI Agent 应用开发工程师做准备。

**学习建议**

- 学习路线A-完整进阶：0 - 认知和实践、「1阶段」0、1、2、3、9 「2阶段」5、4、7、6、7、8、10
- 学习路线B-着急面试：0 + (2) | (3) | (5+4) | (5+4+6) | (5+6+7) | (5+4+8) | ...

**阶段成长**

- 第1阶段：OpenAI代码自动评审+(AI Agent 脚手架+场景应用/AIAgent智能体)2选1
- 第2阶段：OpenAI应用项目(公众号扫码登录、微信支付)+AI MCP网关（+WaLiAPI），时间充足可结合 API Gateway 业务网关
- 第3阶段：AI MCP Gateway+API网关结合、OpenAI应用+AI Agent +拼团/大营销结合
- 第4阶段：进阶到 WaLiSSH + WaLiCode 深入到 AI Agent 运行时设计实现 + WaLiAPI（知识库）

> 以上，所有内容，加入星球「[码农会锁 (opens new window)](https://wx.zsxq.com/group/48411118851818)」都可以学习到，此外还有其他非常多的内容，都可以获取。

还记得吗🤔，26年3月31日，`Anthropic` 在发布 `claude code v2.1.88` 版本时，将带有完整 source map 的包上传 npm 导致源码全部泄露。**51万行 TypeScript 代码**，40+ 工具模块，多智能体编排系统。一瞬间，市面上出现了大量的 claude code 教程（~~大部分都是AI写的，所以很多伙伴看了也等于没看~~）。

![](https://bugstack.cn/images/article/project/walicode/walicode-introduce-01.gif)

但 `Anthropic` 的 `Claude Code` 就是标杆呀，这么好的东西，不能成体系的吃下来，也就等于，在这个 AI 时代没学会最有价值的智能体。但咋学呢？

**我做了个计划，帮助大家彻底搞透智能体。😂 但真的花费了好长时间！**

- `第一步，我去深度实践。` 4个月呀！从调研开发 AI IDE 工具所需的技术框架，到初版桥接到 Claude Code，再逐步把功能全部重写完成，以及扩展；AI Shell、MCP、Skills、CLI、Git、Git-AI（AI归因）、多对话模式、Token 速率和消耗、继承对话、任务队列等等功能。到这，才感受到了彻底驾驭 AI Agent 智能体，按需随意的扩展需要的场景功能有多爽！
    
    > **AI IDE**：[walicode.xiaofuge.cn (opens new window)](https://walicode.xiaofuge.cn/)- 已有几千人加群，几万次安装使用。现在这款产品，已经成为成熟 AI 开发工具产品。
    
- `第二步，教会大家使用。` 我做了一套 AI 新范式编程，使用 [walicode (opens new window)](https://walicode.xiaofuge.cn/)（AI IDE）工具，通过 vibe coding 的方式0编码进行开发和运维以及做了全套的压测。
    
- `第三步，制作通识教程。` 为了让大家更好的，更完整的成体系的学习到 AI Agent 智能体技术，编写了一套 AI Agent Guide 通识教程，从0到1的，由浅入深的，带着大家学习、理解、掌握智能体技术，并附带八股和考试题锻炼。地址：[https://ai-agent-guide.xiaofuge.cn(opens new window)](https://ai-agent-guide.xiaofuge.cn/)
    
- `第四步，综合实战项目。` 一套 AI IDE 牵扯的东西是非常多的，为了能让大家可以更好的学习下来，我先是做了一套 AI Agent 智能体通用脚手架（Spring AI、LangChain、Google ADK），之后结合脚手架做了 ai draw.io 和 ai mobile（手机龙虾），让大家入门智能体实现。然后是进阶 walissh 通过脚手架开发一套 AI 自动化的云服务器操作，之所以先做它，是因为它可以用一套 SSH 连接服务器的操作，就能让智能体完整的跑起来，因为 shell 命令，可以完整操作云服务器。做这么一套东西，就把云服务器跑起来了。完事后，就到了 walicode 教学版，结合更多场景工具，动态化的完成编码处理。所以，这是一套 ai agent 脚手架、ai draw.io、walissh、walicode 的完整进阶实践路线。
    

> 接下来，小傅哥就给大家介绍下这四步内容，让小伙伴们看看每一部分实打实的内容。

## [#](https://bugstack.cn/md/zsxq/material/student-learn-ai.html#%E4%B8%80%E3%80%81ai-ide-walicode)一、AI IDE（walicode）

瓦力 Coding，本地运行的 AI 编程助手。基于 Tauri 原生构建的 AI IDE，原生集成文件系统、终端、SSH 与调试能力，让 AI 真正帮你**写代码**，而不只是**给建议**。支持 Windows、Mac、Linux、IOS、安卓。可以配置任何 LLM（OpenAI 协议、Anthropic 协议、Ollama 协议），不会对任何模型限速。

![](https://bugstack.cn/images/article/product/software/walicode-v0.3.0-00.png)

- 官网下载：[https://walicode.xiaofuge.cn/(opens new window)](https://walicode.xiaofuge.cn/)
- 使用视频：[https://www.bilibili.com/video/BV1Zkd2BvExi(opens new window)](https://www.bilibili.com/video/BV1Zkd2BvExi)

> 就是因为有这套东西 walicode，几万次的下载安装使用，几千人的讨论群，我才有底气给你编写后续的课程。

## [#](https://bugstack.cn/md/zsxq/material/student-learn-ai.html#%E4%BA%8C%E3%80%81ai-%E6%96%B0%E8%8C%83%E5%BC%8F-vibecoding)二、AI 新范式（VibeCoding）

AI 新范式编程交付项目，是一套0编码，全流程从开发到部署和压测的实操项目。课程采用“视频带学 + 对话式开发”的新范式教学方式，手把手带你完成`服务器配置`、`开发环境安装`、`DDD + SpringBoot 表单项目搭建`、`云服务器部署上线`、`性能压测与 Arthas 性能分析`、`Ollama 本地大模型部署`，并最终完成`智能客服系统对接与交付`。

![](https://bugstack.cn/images/article/zsxq/student-learn-ai-01.png)

- 教程地址：[https://space.bilibili.com/15637440/lists/8403959?type=season(opens new window)](https://space.bilibili.com/15637440/lists/8403959?type=season)
- 内容说明：该系列内容，带着小伙伴们，全程使用 AI 工具，从0到自动化的完成环境配置、编码开发（编程规约技能）、项目上线、性能压测、链路分析、代码优化、Ollama + qwen2.5:0.5b（2c4g）结合项目做智能客服。FDE（人工智能领域的前沿部署工程师） 工程师必备技能。还有 Skills 技能的开发。

## [#](https://bugstack.cn/md/zsxq/material/student-learn-ai.html#%E4%B8%89%E3%80%81ai-agent-guide-%E9%80%9A%E8%AF%86%E6%95%99%E7%A8%8B)三、AI Agent Guide - 通识教程

`Agent 架构与传统 LLM 链式调用有什么区别？` `什么是 ReAct 模式，底层工作原理是什么？` `多轮 Agent 对话怎么解决上下文溢出？` `Agent 工具调用的工具类型都有哪些，在长对话中，怎么保证 Agent 的工具调用的可靠性。` 死鬼，想转 Agent 应用开发工程师吗，这些问题你准备好了吗。别怕，本套通识教程，都为你把这些准备好了。在做项目前，可以先把 AI Agent Guide 好好刷下。

![](https://bugstack.cn/images/article/ai/ai-agent-guide-01.png)

- 教程地址：[https://ai-agent-guide.xiaofuge.cn/(opens new window)](https://ai-agent-guide.xiaofuge.cn/)
- 教程说明：这是一套从零到面试通关的 AI Agent Guide 宝典，用可视化动画拆解复杂概念，循序渐进的由浅入深的帮助大家理解和掌握 Agent 智能体。并且每节内容，都覆盖了核心内容的讲解，八股文章的总结和课后面试问题的考察。除此之外，还附带了 AI 工具（免费的）帮助大家理解和学习整套课程。可以说这套教程，是当下最系统的中文 AI Agent 学习资源之一。

## [#](https://bugstack.cn/md/zsxq/material/student-learn-ai.html#%E5%9B%9B%E3%80%81%E5%AE%9E%E6%88%98%E9%A1%B9%E7%9B%AE-ai-%E9%83%A8%E5%88%86)四、实战项目（AI 部分）

这是一整套完整体系的 AI 学习教程，由浅入深的，渐进式的成长学习。从最基本的 OpenAI 的 API 组件开发，到怎么和业务场景对接，完成登录、支付、对话（绘图）、敏感词过滤，之后又进入到不用场景的智能体实现，以及深入到源码的 AI MCP Gateway 学习。可以帮助大家，一步步稳扎稳打的学习成长。

![](https://bugstack.cn/images/article/zsxq/student-learn-ai-02.png)

> 实战项目地址：[https://bugstack.cn/](https://bugstack.cn/) - `进入实战项目，就可以看到各个项目啦` walicode 部分在更新课程，它是在 walissh 的基础上来的。

### [#](https://bugstack.cn/md/zsxq/material/student-learn-ai.html#_1-openai-%E5%A4%A7%E6%A8%A1%E5%9E%8B%E5%BA%94%E7%94%A8)1. OpenAI 大模型应用

项目地址：[https://bugstack.cn/md/project/chatgpt/chatgpt.html(opens new window)](https://bugstack.cn/md/project/chatgpt/chatgpt.html)

#### [#](https://bugstack.cn/md/zsxq/material/student-learn-ai.html#_1-1-%E9%A1%B9%E7%9B%AE%E6%BC%94%E7%A4%BA)1.1 项目演示

![](https://bugstack.cn/images/article/project/chatgpt/chatgpt-extra-230905-03.png?raw=true)

#### [#](https://bugstack.cn/md/zsxq/material/student-learn-ai.html#_1-2-%E6%95%B0%E6%8D%AE%E7%9B%91%E6%8E%A7-%E7%99%BE%E5%BA%A6%E7%BB%9F%E8%AE%A1)1.2 数据监控（百度统计）

![](https://bugstack.cn/images/article/project/chatgpt/chatgpt-extra-230905-04.png?raw=true)

#### [#](https://bugstack.cn/md/zsxq/material/student-learn-ai.html#_1-3-%E7%83%AD%E5%8A%9B%E5%B1%95%E7%A4%BA-%E7%99%BE%E5%BA%A6%E7%BB%9F%E8%AE%A1)1.3 热力展示（百度统计）

![](https://bugstack.cn/images/article/project/chatgpt/chatgpt-extra-230905-09.png?raw=true)

### [#](https://bugstack.cn/md/zsxq/material/student-learn-ai.html#_2-openai-%E4%BB%A3%E7%A0%81%E8%87%AA%E5%8A%A8%E8%AF%84%E5%AE%A1)2. OpenAI 代码自动评审

项目地址：[https://bugstack.cn/md/zsxq/project/openai-code-review.html(opens new window)](https://bugstack.cn/md/zsxq/project/openai-code-review.html)

![](https://bugstack.cn/images/article/project/openai-code-review/openai-code-review-01.png)

![](https://bugstack.cn/images/article/project/openai-code-review/openai-code-review-08.png)

### [#](https://bugstack.cn/md/zsxq/material/student-learn-ai.html#_3-ai-agent-%E6%8B%96%E6%8B%89%E6%8B%BD)3. AI Agent 拖拉拽

项目地址：[https://bugstack.cn/md/project/ai-knowledge/ai-knowledge.html(opens new window)](https://bugstack.cn/md/project/ai-knowledge/ai-knowledge.html)

#### [#](https://bugstack.cn/md/zsxq/material/student-learn-ai.html#_3-1-%E7%99%BB%E5%BD%95%E7%95%8C%E9%9D%A2)3.1 登录界面

![](https://bugstack.cn/images/article/project/ai-rag-knowledge/ai-rag-knowledge-3-20-02.png)

- 管理后台目前提供了，代理管理（拖拉拽编排方式配置智能体），资源管理（model、client、mcp、advisor、prompt）
- 数据分析、系统设置，是样例，你可以继续扩展你所需要的内容。

#### [#](https://bugstack.cn/md/zsxq/material/student-learn-ai.html#_3-2-%E4%BB%A3%E7%90%86%E5%88%97%E8%A1%A8)3.2 代理列表

![](https://bugstack.cn/images/article/project/ai-rag-knowledge/ai-rag-knowledge-3-20-03.png)

- 这里的代理列表，就是通过拖拉拽配置的智能体。可以点击【查看】看到明细，也可以【新建】，还可以删除。
- 点击【加载】则是调用服务端，把数据加载到 Spring 容器，之后就可以使用了。

#### [#](https://bugstack.cn/md/zsxq/material/student-learn-ai.html#_3-3-%E4%BB%A3%E7%90%86%E9%85%8D%E7%BD%AE)3.3 代理配置

![](https://bugstack.cn/images/article/project/ai-rag-knowledge/ai-rag-knowledge-3-20-04.png)

- 当你点击一个代理配置，则会展示出拖拉拽的数据到页面上。这部分会从数据库读取，之后展示出来，全部可视化。
- 如果你点击了Save则会做出一份新的，之后对于旧的，你可以自己手动删除。

#### [#](https://bugstack.cn/md/zsxq/material/student-learn-ai.html#_3-4-%E7%9B%91%E6%8E%A7%E5%88%86%E6%9E%90)3.4 监控分析

![](https://bugstack.cn/images/article/project/ai-rag-knowledge/ai-rag-knowledge-3-14-07.png)

### [#](https://bugstack.cn/md/zsxq/material/student-learn-ai.html#_4-ai-agent-%E8%84%9A%E6%89%8B%E6%9E%B6)4. AI Agent 脚手架

项目地址：[https://bugstack.cn/md/project/ai-agent-scaffold/ai-agent-scaffold.html(opens new window)](https://bugstack.cn/md/project/ai-agent-scaffold/ai-agent-scaffold.html)

#### [#](https://bugstack.cn/md/zsxq/material/student-learn-ai.html#_4-1-%E6%99%BA%E8%83%BD%E4%BD%93%E6%95%B4%E4%BD%93%E8%AE%BE%E8%AE%A1)4.1 智能体整体设计

![](https://bugstack.cn/images/article/project/ai-agent-scaffold/part-1/1-1/images/ai-agent-scaffold-1-1-02.png)

- 2025年11月27日，Google 正式在 Maven 仓库管理中心，推送了 0.4.0 版本 ADK，该版本新增加了 Spring AI 的集成。[google-adk-spring-ai (opens new window)](https://central.sonatype.com/artifact/com.google.adk/google-adk-spring-ai)至此，也因此，小傅哥决定基于这套服务组合，设计智能体脚手架。
- 首先，Google ADK 是一个智能体框架，他自身也是支持直接对接各类大模型的 API，以及构建 ChatModel 的。但在整合 Spring AI、LangeChain4J 以后，Google ADK 的使用，将会得到已经使用上述组件的公司更大的青睐。
- 之后，Spring AI 解决的 AI 对接的前半部分，让你可以把 AI API、Model、Prompt、RAG、Tool（Function、MCP）等，非常方便的构建出一个单一的 AI Agent 服务（也可以称之为是一个客户端）。
- 然后，Google ADK 解决的是，多个 AI Agent 怎么协同工作的问题。这里包括，Sequential 序列顺序执行、Loop 循环执行、Parallel 并行执行，而这些执行方式，又可以组合搭配的配置到一个 Sequential 中进行顺序执行（注意图中颜色）。绿色的是大模型服务，绿色部分可以被深黄色或者浅青色包装，之后在组合到 SequentialAgent - 序列执行中。
- 最后，Google ADK 提供了记忆上下文 Runner 执行器（也可以自己扩展实现），在这里又提供了钩子插件，你可以对执行过程中的流程，进行拦截。这个过程类似 Spring 容器中对 Bean 对象的处理，before、after 的过程。

#### [#](https://bugstack.cn/md/zsxq/material/student-learn-ai.html#_4-2-draw-io-%E7%94%BB%E5%9B%BE)4.2 draw.io + 画图

![](https://bugstack.cn/images/article/project/ai-agent-scaffold/part-4/4-4/images/ai-agent-scaffold-4-4-05.png)

- ai agent + draw.io，可以配置出一套交互式绘图智能体。我们可以把诉求发给 AI，之后 AI 进行分析和决策，让用户补充信息或者直接画图。
- 在大量的测试和体验中，这套智能体 + gpt 5.1 可以绘制出非常符合企业中真实场景的流程图，效果还是非常不错的。如果你还配置 mcp 可以结合本地代码库，文档库，产品PRD库，那么它还可以更好的绘制出相关的流程图。

#### [#](https://bugstack.cn/md/zsxq/material/student-learn-ai.html#_4-3-autophone-%E5%AE%9E%E9%AA%8C%E6%80%A7%E5%9C%BA%E6%99%AF)4.3 AutoPhone 实验性场景

这里小傅哥在体验了 OpenClaw 大龙虾的设计后，对 AutoPhone 也有了想法。我们可以设计一套安卓版的手机 MobileOpenClaw，在手机端开发一个网关，网关功能具备；`启动应用`、`点击指定坐标`、`输入文本`、`滑动屏幕`等。之后在让 AI 以借助 Socket 通信，对手机设备进行管理。

![](https://bugstack.cn/images/article/project/ai-agent-scaffold/part-5/5-0/images/ai-agent-scaffold-5-0-01.png)

- 首先，需要实现一套 MobileOpenClaw 的网关，这部分内容是安卓开发的一个软件，如果 IOS 也还有其他方案。可以在 Github 检索相关资料 [https://github.com/search?q=phone%20agent&type=repositories(opens new window)](https://github.com/search?q=phone%20agent&type=repositories)
- 之后，基于脚手架，开发 MobileOpenClaw 智能体，这部分要通过 Socket 和 手机端进行通信。让 AI 识别用户意图，控制手机端执行相关操作。因为这里大量的视觉识别，所以 gemini-3-pro-preview 效果不错，另外就是 GLM 定制的 [AutoGLM-Phone-9B (opens new window)](https://github.com/zai-org/Open-AutoGLM)模型，可以自己在 GPU 部署。

### [#](https://bugstack.cn/md/zsxq/material/student-learn-ai.html#_5-ai-mcp-gateway)5. AI MCP Gateway

项目地址：[https://bugstack.cn/md/project/ai-mcp-gateway/ai-mcp-gateway.html(opens new window)](https://bugstack.cn/md/project/ai-mcp-gateway/ai-mcp-gateway.html)

#### [#](https://bugstack.cn/md/zsxq/material/student-learn-ai.html#_5-1-%E7%BD%91%E5%85%B3%E5%88%97%E8%A1%A8)5.1 网关列表

![](https://bugstack.cn/images/article/project/ai-mcp-gateway/ai-mcp-gateway-4-1-09.png)

#### [#](https://bugstack.cn/md/zsxq/material/student-learn-ai.html#_5-2-%E5%8D%8F%E8%AE%AE%E9%85%8D%E7%BD%AE)5.2 协议配置

![](https://bugstack.cn/images/article/project/ai-mcp-gateway/ai-mcp-gateway-4-1-06.png)

- 这里网关测试的是小傅哥上传并解析的 Swagger OpenAPI 协议，导入后，可以被识别为 MCP 网关协议，之后进行通信。

#### [#](https://bugstack.cn/md/zsxq/material/student-learn-ai.html#_5-3-%E7%BD%91%E5%85%B3%E6%B5%8B%E8%AF%95)5.3 网关测试

![](https://bugstack.cn/images/article/project/ai-mcp-gateway/ai-mcp-gateway-4-1-07.png)

- 网关加入了一套 LLM 轻量的智能体，用于测试配置的网关服务是否可用。
- 这个完整的东西，拿出去给面试官演示，那不妥妥的让面试官给你发 Offer！

### [#](https://bugstack.cn/md/zsxq/material/student-learn-ai.html#_6-ai-shell-walissh)6. ai shell walissh

项目地址：[https://bugstack.cn/md/project/walissh/walissh.html(opens new window)](https://bugstack.cn/md/project/walissh/walissh.html)

#### [#](https://bugstack.cn/md/zsxq/material/student-learn-ai.html#_6-1-%E5%9F%BA%E7%A1%80%E8%AE%BE%E7%BD%AE)6.1 基础设置

![](https://bugstack.cn/images/article/project/walissh/product-walissh-user-guide-03.png)

- 首先，在设置里有个通用设置，这里的服务端地址，就是 walissh-server 部署的地址。如果你部署在云服务器，那么这个默认地址也可以配置成云服务器。
- 之后，如果你想改变外观主题或者终端字体，可以分别调整设置。
- 最后，是关于，这里写了相关的技术栈，整个项目也是基于此语言进行构建的。

#### [#](https://bugstack.cn/md/zsxq/material/student-learn-ai.html#_6-2-%E8%BE%85%E5%8A%A9%E5%91%BD%E4%BB%A4)6.2 辅助命令

![](https://bugstack.cn/images/article/project/walissh/product-walissh-user-guide-04.png)

- 连接服务器，在终端页有相关的辅助命令，你可以直接使用。
- 右侧是对话输入框，以及对话展示栏。提供了一些案例，也可以点击后，测试验证。

#### [#](https://bugstack.cn/md/zsxq/material/student-learn-ai.html#_6-3-%E6%99%BA%E8%83%BD%E5%88%86%E6%9E%90)6.3 智能分析

![](https://bugstack.cn/images/article/project/walissh/product-walissh-user-guide-05.png)

- 你可以在对话框输入框，发送各类运维相关的信息。之后 ssh ai agent 会自动化的分析，并执行脚本命令（你可以看到命令的执行，风险命令已被限制不会执行）。
- 命令逐个执行完毕后，你会得到一个分析结果，以及会提示你是否做后续的其他操作。

> 这个东西是我一直想要的，但市面上是真没有！我太需要一个智能 ssh 服务了，可以帮我这类的请运维工程师，做很多工作。甚至你像做个 redis 集群，也可以帮你配置完成。通过多个 ssh 终端对话，让 ai agent 智能体，依次的配置并验证检查。

### [#](https://bugstack.cn/md/zsxq/material/student-learn-ai.html#_7-ai-coding-walicode)7. ai coding walicode

项目地址：[https://bugstack.cn/md/project/walicode/walicode.html(opens new window)](https://bugstack.cn/md/project/walicode/walicode.html)

#### [#](https://bugstack.cn/md/zsxq/material/student-learn-ai.html#_7-1-%E8%AF%A2%E9%97%AE%E9%A1%B9%E7%9B%AE-ai-%E8%BF%90%E7%BB%B4)7.1 询问项目 + AI 运维

![](https://bugstack.cn/images/article/project/walicode/walicode-introduce-05.png)

- 可以对话的方式直接询问代码，AI IDE 会主动的分析并给出结果。
- 也可以通过 SSH 能力与云服务器对话，这样既具备了开发能力，又有了云环境的运维能力。

#### [#](https://bugstack.cn/md/zsxq/material/student-learn-ai.html#_7-2-%E6%93%8D%E4%BD%9C%E4%BB%A3%E7%A0%81)7.2 操作代码

![](https://bugstack.cn/images/article/project/walicode/walicode-introduce-11.png)

这是当前对应的 UI 效果，具备了基本的功能，后续小傅哥还会继续迭代，也会把代码直接推送到课程仓库，让小伙伴们可以拿去就学。