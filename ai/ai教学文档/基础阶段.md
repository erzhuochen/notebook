# AI应用课程实验指南（实验1-4）

欢迎来到AI应用课程的基础能力构建阶段！本项目包含4个渐进式实验，帮助你掌握与AI模型进行**可靠、可控、可验证**交互的核心技术。

## 🎯 学习目标

通过这4个实验，你将学习：

1. **实验1**：使用 Pydantic 实现结构化输出，确保AI返回可验证的数据格式
2. **实验2**：实现有状态对话系统，掌握多会话隔离与历史管理
3. **实验3**：使用 LangChain 的内存组件，实现标准化的会话记忆系统
4. **实验4**：掌握 LangChain 链式调用，构建可编程的AI应用流程

## 📋 环境准备

### 1. 系统要求

- **Python**: 3.10 或更高版本
- **操作系统**: Linux / macOS / Windows
- **Ollama**: 本地AI模型服务

### 2. 安装 Ollama

#### Linux / macOS

```bash
# 安装 Ollama
curl -fsSL https://ollama.ai/install.sh | sh

# 启动 Ollama 服务
ollama serve

# 下载 Qwen3-8B 模型（新开一个终端）
ollama pull qwen3:8b
```

#### Windows

1. 访问 [Ollama官网](https://ollama.ai) 下载 Windows 安装包
2. 安装并启动 Ollama
3. 在命令提示符中运行：`ollama pull qwen3:8b`

### 3. 验证 Ollama 服务

```bash
# 检查 Ollama 是否运行
curl http://localhost:11434/api/tags

# 应该返回包含 qwen3:8b 的模型列表
```

### 4. 安装 Python 依赖

```bash
# 进入项目目录
cd ai-course-labs

# 安装依赖
pip install -r requirements.txt
```

## 🚀 快速开始

### 运行测试

```bash
# 运行所有实验的测试
pytest grader/ -v

# 运行单个实验的测试
pytest grader/test_lab1.py -v
pytest grader/test_lab2.py -v
pytest grader/test_lab3.py -v
pytest grader/test_lab4.py -v

# 查看详细错误信息
pytest grader/test_lab1.py -v --tb=short
```

### 查看测试覆盖率

```bash
# 查看测试输出的详细信息
pytest grader/ -v -s
```

## 📂 项目结构

```
ai-course-labs/
├── grader/                    # 测评系统
│   ├── fixtures.py           # 共享测试夹具（Ollama健康检查）
│   ├── test_lab1.py          # 实验1测评脚本
│   ├── test_lab2.py          # 实验2测评脚本
│   ├── test_lab3.py          # 实验3测评脚本
│   └── test_lab4.py          # 实验4测评脚本
│
├── student_code/              # 学生代码目录
│   ├── lab1/main.py          # 实验1：你的实现代码
│   ├── lab2/main.py          # 实验2：你的实现代码
│   ├── lab3/main.py          # 实验3：你的实现代码
│   └── lab4/main.py          # 实验4：你的实现代码
│
├── requirements.txt           # Python依赖
├── pytest.ini                 # Pytest配置
└── README.md                  # 本文件
```

## 🧪 实验详情

### 实验1：结构化提示词与输出

**目标**：实现文本分类功能，返回 Pydantic 模型实例

**文件位置**：`student_code/lab1/main.py`

**需要实现**：`classify_text()` 函数

**任务要求**：
- 构建结构化Prompt，要求模型输出JSON格式
- 调用Ollama API进行文本分类
- 解析JSON响应并创建TextClassification实例
- 确保返回的category在预定义列表中

**关键要求**：
- 返回 `TextClassification` 实例（包含 category, confidence_score, keywords）
- category 必须是预定义的5个类别之一：'新闻', '技术', '体育', '娱乐', '财经'
- confidence_score 范围 0-1
- keywords 列表长度 1-5

**实现提示**：
```python
# 当前状态：raise NotImplementedError("请实现 classify_text 函数")
# 你需要：
# 1. 设计包含5个类别的prompt
# 2. 使用 httpx.post() 调用 Ollama API (http://localhost:11434/api/generate)
# 3. 使用 "format": "json" 参数强制JSON输出
# 4. 用 json.loads() 解析响应
# 5. 用 TextClassification.model_validate() 验证并创建实例
```

**测试运行**：
```bash
pytest grader/test_lab1.py -v
```

**测试用例**：
- ✅ 返回类型验证（20%）
- ✅ 分类类别有效性（20%）
- ✅ 置信度范围检查（15%）
- ✅ 关键词非空验证（15%）
- ✅ 技术类文本准确性（15%）
- ✅ 体育类文本准确性（15%）
- 🌟 批量测试（加分项）

---

### 实验2：有状态对话的快照验证

**目标**：实现支持多会话隔离的对话系统

**文件位置**：`student_code/lab2/main.py`

**需要实现**：`chat_with_memory()` 函数

**任务要求**：
- 实现多会话隔离的对话系统
- 正确计算history_length（本次对话前的消息数）
- 将历史消息作为上下文传递给模型
- 保存用户消息和AI回复到历史记录

**关键要求**：
- 返回字典，包含 response, history_length, session_id
- 不同 session_id 的历史完全独立
- history_length 必须精确反映本次对话前的消息数
- 历史消息作为上下文传递给模型

**实现提示**：
```python
# 当前状态：raise NotImplementedError("请实现 chat_with_memory 函数")
# 你需要：
# 1. 初始化 SESSION_HISTORY[session_id] = []
# 2. history_length = len(history) # 在保存新消息前计算
# 3. 构建包含历史的prompt
# 4. 调用Ollama API并保存结果到SESSION_HISTORY
```

**数据结构建议**：
```python
SESSION_HISTORY = {
    "session_001": [
        {"role": "user", "content": "你好"},
        {"role": "assistant", "content": "你好！..."},
    ]
}
```

**测试运行**：
```bash
pytest grader/test_lab2.py -v
```

**测试用例**：
- ✅ 首次对话 history_length=0（15%）
- ✅ 历史消息累积（20%）
- ✅ 会话隔离验证（25%）
- ✅ 交叉会话测试（25%）
- ✅ 输出结构验证（15%）
- 🌟 内容持久化验证（加分项）

---

### 实验3：记忆系统的内容检索

**目标**：使用 LangChain 的 ConversationBufferMemory 管理会话

**文件位置**：`student_code/lab3/main.py`

**需要实现**：
- `chat_with_langchain_memory()` 函数：使用 LangChain Memory 进行对话
- `get_memory_summary()` 函数：获取会话历史摘要

**任务要求**：
- 使用LangChain的ConversationBufferMemory管理历史
- 创建LLMChain连接Prompt、LLM和Memory
- 实现memory_variables返回（包含 'history' 键）
- 格式化历史记录摘要为人类可读文本

**关键要求**：
- 使用 `ConversationBufferMemory` 管理历史
- 返回值包含 memory_variables（含 history 键）
- 摘要格式化为人类可读文本（User: ... AI: ...）
- 不同 session 的 Memory 完全独立

**实现提示**：
```python
# 需要安装和导入：
# from langchain_core.prompts import PromptTemplate
# from langchain_community.llms import Ollama

# 对于ConversationBufferMemory和LLMChain:
# - 新版LangChain可能需要自己实现兼容层
# - 或者查找新版本的等效API
# - 参考LangChain官方文档

# 提示：
# 1. 检查 session_id 是否存在对应的 Memory，不存在则创建
# 2. 创建 Ollama LLM 实例
# 3. 创建 PromptTemplate（包含历史上下文）
# 4. 创建 LLMChain，连接 Prompt、LLM 和 Memory
# 5. 运行链并获取响应
# 6. 返回响应和 memory_variables
```

**LangChain 示例**：
```python
from langchain.memory import ConversationBufferMemory

memory = ConversationBufferMemory(
    memory_key="history",
    return_messages=False
)
```

**测试运行**：
```bash
pytest grader/test_lab3.py -v
```

**测试用例**：
- ✅ Memory 对象类型验证（15%）
- ✅ memory_variables 结构检查（15%）
- ✅ 信息持久化验证（30%）
- ✅ 历史摘要格式（20%）
- ✅ 不存在会话处理（20%）
- 🌟 跨会话隔离（加分项）

---

### 实验4：LangChain 链的确定性输出

**目标**：使用 LangChain 链生成广告文案

**文件位置**：`student_code/lab4/main.py`

**需要实现**：`generate_ad()` 函数

**任务要求**：
- 使用PromptTemplate定义模板（包含 {product} 和 {feature}）
- 创建LLMChain连接Prompt和LLM
- 生成广告文案并计算字数
- 返回结构化结果

**关键要求**：
- 使用 `PromptTemplate` 定义模板（包含 {product} 和 {feature}）
- 创建 `LLMChain` 连接 Prompt 和 LLM
- 返回字典包含 ad_copy, word_count, template_used
- word_count 必须等于 len(ad_copy)

**实现提示**：
```python
# 当前状态：raise NotImplementedError("请实现 generate_ad 函数")
# 你需要：
# 1. 创建包含{product}和{feature}的PromptTemplate
# 2. 创建Ollama LLM实例
# 3. 创建LLMChain连接prompt和llm
# 4. 调用chain.run()或chain.predict()
# 5. 返回包含ad_copy, word_count, template_used的字典
```

**LangChain 示例**：
```python
from langchain.chains import LLMChain
from langchain.prompts import PromptTemplate

template = "为产品 {product} 创作广告，特性：{feature}"
prompt = PromptTemplate(
    input_variables=["product", "feature"],
    template=template
)

chain = LLMChain(llm=llm, prompt=prompt)
result = chain.run(product="智能手表", feature="心率监测")
```

**测试运行**：
```bash
pytest grader/test_lab4.py -v
```

**测试用例**：
- ✅ 输出结构验证（20%）
- ✅ 字数一致性（25%）
- ✅ 产品名包含（20%）
- ✅ 特性包含（20%）
- ✅ 长度合理性（15%）
- 🌟 多产品批量测试（加分项）

## 🛠️ 调试建议

### 常见问题排查

| 问题现象 | 可能原因 | 解决方法 |
|---------|---------|---------|
| 测试全部 SKIP | Ollama 未启动 | 运行 `ollama serve`，确认端口 11434 监听 |
| 模型未找到 | qwen3:8b 未下载 | 运行 `ollama pull qwen3:8b` |
| 返回类型错误 | 未使用 Pydantic 模型 | 检查函数返回值类型 |
| JSON 解析失败 | Prompt 设计不当 | 在 Prompt 中明确要求输出纯 JSON |
| 会话状态混乱 | 全局变量使用错误 | 检查字典键是否为 session_id |
| 超时错误 | 模型响应慢 | 减小 max_tokens 或简化 Prompt，尝试使用更小模型 |
| LangChain导入错误 | 版本不兼容 | 查阅最新LangChain文档找到新API，或实现简单兼容层 |

### 重要提示

**关于LangChain版本**：
LangChain更新较快，如果遇到导入错误：
- **方案1**：查阅最新LangChain文档找到新API
- **方案2**：实现简单的兼容层（参考Lab3/Lab4的提示）
- **方案3**：降级到requirements.txt指定的版本

**JSON解析失败**：
- 在Ollama API调用中使用 `"format": "json"` 参数
- 在Prompt中明确要求输出纯JSON
- 添加JSON提取逻辑（正则表达式）

### 本地调试

每个实验文件都包含 `if __name__ == "__main__"` 测试代码，可以直接运行：

```bash
# 调试实验1
python student_code/lab1/main.py

# 调试实验2
python student_code/lab2/main.py

# 调试实验3
python student_code/lab3/main.py

# 调试实验4
python student_code/lab4/main.py
```

### 查看详细日志

```bash
# 显示打印输出
pytest grader/test_lab1.py -v -s

# 显示完整错误堆栈
pytest grader/test_lab1.py -v --tb=long

# 只运行失败的测试
pytest grader/test_lab1.py -v --lf
```

## 📊 评分标准

每个实验的测试用例都有明确的权重：

- **必需测试**：占总分 80-100%
- **加分项测试**：额外加分，展示高级理解

总体要求：
- 所有必需测试通过：合格
- 包含加分项：优秀
- 代码质量良好（注释、结构）：卓越

## 🎓 学习资源

### 官方文档

- [Pydantic 文档](https://docs.pydantic.dev/)
- [LangChain 文档](https://python.langchain.com/)
- [Ollama 文档](https://ollama.ai/docs)

### 推荐阅读

1. **结构化输出**：了解如何设计有效的 Prompt 确保 JSON 输出
2. **状态管理**：理解会话隔离与历史管理的最佳实践
3. **LangChain Memory**：掌握不同 Memory 类型的使用场景
4. **链式调用**：学习 LangChain 的核心概念与设计模式

## 🤝 获取帮助

### 遇到问题？

1. **查看错误信息**：Pytest 会提供详细的断言失败信息
2. **运行本地调试代码**：每个实验文件都有测试代码
3. **检查 Ollama 日志**：查看模型输出是否符合预期
4. **阅读测试用例**：理解每个测试的具体要求

### 提交作业前

- [ ] 确保所有必需测试通过
- [ ] 运行 `pytest grader/ -v` 查看整体结果
- [ ] 检查代码注释和文档
- [ ] 尝试实现加分项功能

## 📝 实验报告建议

完成实验后，建议撰写实验报告，包含：

1. **实现思路**：简述每个实验的核心思路
2. **遇到的问题**：记录调试过程中的问题与解决方案
3. **测试结果**：截图或粘贴测试通过的输出
4. **心得体会**：谈谈对结构化输出、状态管理、LangChain 的理解

## 🎉 完成标志

当你看到以下输出时，恭喜你完成了所有实验！

```
======================== test session starts =========================
...
grader/test_lab1.py::TestLab1::... PASSED                    [...]
grader/test_lab2.py::TestLab2::... PASSED                    [...]
grader/test_lab3.py::TestLab3::... PASSED                    [...]
grader/test_lab4.py::TestLab4::... PASSED                    [...]

======================== XX passed in XX.XXs =========================
```

---

**祝学习愉快！** 🚀

如有疑问，请参考设计文档或联系助教。
