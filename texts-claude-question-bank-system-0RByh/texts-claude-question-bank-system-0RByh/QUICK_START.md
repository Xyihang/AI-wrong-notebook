# 快速启动指南

## 环境要求

- Python 3.8+
- pip
- 网络连接（首次运行需要下载OCR模型）

## 快速启动（推荐）

```bash
# 1. 运行启动脚本（自动处理所有步骤）
./run.sh
```

启动脚本会自动：
- ✓ 检查Python环境
- ✓ 创建虚拟环境（如果不存在）
- ✓ 安装所有依赖
- ✓ 创建必要的目录
- ✓ 启动应用

## 手动启动

如果需要手动启动，按以下步骤操作：

### 1. 安装依赖

```bash
pip install -r requirements.txt
```

### 2. 配置环境变量（可选）

如果要使用AI功能，需要配置API密钥：

```bash
# 复制配置模板
cp .env.example .env

# 编辑.env文件，填入你的API密钥
nano .env
```

配置项说明：
- `AI_PROVIDER`: 选择AI提供商（auto/claude/gemini）
- `ANTHROPIC_API_KEY`: Claude API密钥
- `GOOGLE_API_KEY`: Gemini API密钥

### 3. 启动应用

```bash
python3 app.py
```

### 4. 访问系统

打开浏览器访问：`http://localhost:5000`

## 功能说明

系统启动后，你可以：

1. **导入题目** (`/upload`)
   - 上传图片或PDF
   - AI自动识别和纠正（如果已配置）
   - 支持英文题目优先识别

2. **题目管理** (`/questions`)
   - 查看所有题目
   - 按题型、难度筛选
   - 编辑和删除题目

3. **试卷模板** (`/templates`)
   - 查看预设模板（初中英语期中/期末）
   - 使用模板快速生成试卷
   - 创建自定义模板

4. **组卷** (`/exam`)
   - 手动选题组卷
   - 自动组卷（按条件）
   - 导出Word文档

## 常见问题

### Q: 首次运行很慢？
A: 首次运行需要下载PaddleOCR模型（约200MB），需要良好的网络连接。

### Q: AI功能不可用？
A: 检查是否配置了`.env`文件并填入了有效的API密钥。

### Q: 如何获取API密钥？
A:
- Claude: https://console.anthropic.com/
- Gemini: https://aistudio.google.com/app/apikey

### Q: 系统支持哪些题型？
A: 支持10种英语题型：
- 单选题、完形填空、阅读理解
- 任务型阅读、选词填空、语法填空
- 单词拼写、句型转换、翻译、书面表达

### Q: 如何停止应用？
A: 按 `Ctrl+C`

## 技术支持

如有问题，请查看：
- `README.md` - 完整文档
- `UPDATE_v3.0.md` - 最新版本说明
- `AI_SETUP_GUIDE.md` - AI配置详细指南

---

祝使用愉快！ 🎉
