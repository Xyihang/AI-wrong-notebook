# AI功能配置指南

本文档说明如何配置和使用题库系统的AI智能增强功能。

## 为什么需要AI功能？

AI功能可以显著提升OCR识别准确度，特别是对于：
- ✅ **英文题目**：自动纠正常见OCR错误（0/O, 1/l/I, 5/S等混淆）
- ✅ **数学公式**：更准确识别数学符号和方程
- ✅ **题目结构**：智能识别题型、难度、知识点
- ✅ **选择题选项**：自动提取A、B、C、D选项
- ✅ **质量提升**：平均识别准确率提升20-30%

## 快速配置

### 步骤1：获取Anthropic API密钥

1. 访问 [Anthropic Console](https://console.anthropic.com/)
2. 注册或登录账号
3. 进入 API Keys 页面
4. 点击 "Create Key" 创建新密钥
5. 复制生成的密钥（格式：sk-ant-api03-...）

### 步骤2：配置环境变量

#### Linux/macOS

```bash
# 方法1：在项目目录创建.env文件
cp .env.example .env
nano .env  # 或使用其他编辑器

# 在.env文件中添加：
ANTHROPIC_API_KEY=sk-ant-api03-your-key-here

# 方法2：直接在终端设置（临时）
export ANTHROPIC_API_KEY=sk-ant-api03-your-key-here
```

#### Windows

```cmd
# 方法1：创建.env文件
copy .env.example .env
notepad .env

# 在.env文件中添加：
ANTHROPIC_API_KEY=sk-ant-api03-your-key-here

# 方法2：在命令提示符设置（临时）
set ANTHROPIC_API_KEY=sk-ant-api03-your-key-here

# 方法3：在PowerShell设置（临时）
$env:ANTHROPIC_API_KEY="sk-ant-api03-your-key-here"
```

### 步骤3：启动应用

```bash
python app.py
```

启动时会显示AI助手状态：
```
AI助手状态: 可用
```

如果显示"不可用"，请检查API密钥配置。

## 使用AI功能

### 1. 上传文件时使用AI

访问"导入题目"页面，你会看到：

```
✅ AI助手已启用 - 将自动纠正OCR识别结果
[x] 使用AI智能纠正
```

- 勾选此选项后，上传的文件会经过AI处理
- 取消勾选则使用基础OCR识别

### 2. 查看AI纠正结果

上传文件后，界面会显示：

#### AI纠正信息框
```
🤖 AI纠正信息
OCR置信度: 87.5%
AI纠正置信度: high

纠正内容:
- 修正 "0pen" → "Open"
- 修正 "ca1culate" → "calculate"
- 添加缺失空格
```

#### 标签页对比
- **识别文本**：AI纠正后的最终文本
- **原始OCR**：未经AI处理的原始识别文本
- **智能提取的题目**：AI解析的结构化题目

### 3. 智能题目解析

AI会自动提取每道题目的：

```
题目 1  [multiple_choice]  [medium]
What is the capital of France?
A. London
B. Paris
C. Berlin
D. Madrid

标签: geography, europe
📝 Clear multiple choice question with standard format
```

点击"保存此题"时，题型、难度、标签会自动填充。

## API使用示例

### 检查AI状态

```bash
curl http://localhost:5000/api/ai/status
```

响应：
```json
{
  "available": true,
  "message": "AI助手可用"
}
```

### AI纠正文本

```bash
curl -X POST http://localhost:5000/api/ai/correct \
  -H "Content-Type: application/json" \
  -d '{
    "text": "What is the va1ue 0f x?",
    "confidence": 0.85
  }'
```

响应：
```json
{
  "success": true,
  "corrected_text": "What is the value of x?",
  "original_text": "What is the va1ue 0f x?",
  "corrections": [
    "Corrected 'va1ue' to 'value'",
    "Corrected '0f' to 'of'"
  ],
  "ai_confidence": "high"
}
```

### AI解析题目

```bash
curl -X POST http://localhost:5000/api/ai/parse \
  -H "Content-Type: application/json" \
  -d '{
    "text": "1. What is 2+2?\nA. 3\nB. 4\nC. 5\nD. 6"
  }'
```

## 费用说明

使用Claude API会产生费用：

- **Claude 3.5 Sonnet**（当前使用）
  - 输入：$3 / 百万tokens
  - 输出：$15 / 百万tokens

**典型使用成本**：
- 识别单张图片（约500字）：约 $0.01-0.02
- 识别一份试卷（10道题）：约 $0.05-0.10
- 批量处理100道题：约 $0.50-1.00

**节约成本提示**：
1. 只对重要文件启用AI纠正
2. OCR置信度>90%时可以不使用AI
3. 定期检查API使用量

## 常见问题

### Q: AI助手显示"不可用"？
A:
1. 检查.env文件是否存在
2. 确认ANTHROPIC_API_KEY正确设置
3. 重启应用
4. 检查网络连接（需要访问api.anthropic.com）

### Q: AI纠正结果不理想？
A:
1. 确保上传的图片清晰
2. 英文文本效果最好
3. 可以在纠正后手动编辑
4. 对比"原始OCR"和"识别文本"查看改进

### Q: 能否使用其他AI模型？
A: 当前版本仅支持Claude API。未来计划支持：
- OpenAI GPT-4
- Google Gemini
- 本地开源模型

### Q: AI功能是必需的吗？
A: 不是。系统在没有AI的情况下仍可正常工作，只是识别准确度会降低。

## 高级配置

### 自定义AI模型

编辑 `backend/ai/ai_assistant.py`：

```python
message = self.client.messages.create(
    model="claude-3-5-sonnet-20241022",  # 修改此处
    max_tokens=4000,
    messages=[...]
)
```

可选模型：
- `claude-3-5-sonnet-20241022`（推荐，平衡性能和成本）
- `claude-3-opus-20240229`（最高质量，最贵）
- `claude-3-haiku-20240307`（最快，最便宜）

### 调整AI提示词

如需针对特定学科优化，可修改 `ai_assistant.py` 中的prompt：

```python
prompt = f"""Please correct the following text from a [Math/Physics/Chemistry] exam...

Common domain-specific errors:
- [List specific terminology]
- [Common symbol confusions]

{ocr_text}
"""
```

## 技术支持

如遇问题：
1. 查看控制台错误日志
2. 检查 `/api/ai/status` 端点
3. 提交Issue到GitHub仓库
4. 联系项目维护者

---

**享受AI加持的高效题目识别！**
