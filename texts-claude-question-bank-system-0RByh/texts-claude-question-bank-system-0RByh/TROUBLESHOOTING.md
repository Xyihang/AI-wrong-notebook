# 故障排除指南

本文档帮助你解决运行题库系统时可能遇到的常见问题。

## 安装和启动问题

### 问题1: `No module named 'xxx'`

**症状**: 启动时报错缺少某个模块

**原因**: 依赖未安装或安装不完整

**解决方案**:
```bash
# 方案1: 重新安装所有依赖
pip install -r requirements.txt --force-reinstall

# 方案2: 安装特定缺失的包
pip install <package-name>

# 方案3: 使用虚拟环境（推荐）
python3 -m venv venv
source venv/bin/activate  # Linux/Mac
# 或 venv\Scripts\activate  # Windows
pip install -r requirements.txt
```

### 问题2: PaddleOCR下载失败或很慢

**症状**: 首次运行时卡在下载模型

**原因**: 网络问题或需要下载大文件（~200MB）

**解决方案**:
```bash
# 1. 确保网络连接正常

# 2. 手动预下载模型（可选）
python3 -c "from paddleocr import PaddleOCR; PaddleOCR(lang='en'); PaddleOCR(lang='ch')"

# 3. 如果在中国大陆，可能需要使用镜像
export HF_ENDPOINT=https://hf-mirror.com
```

### 问题3: `ImportError: cannot import name 'xxx'`

**症状**: 导入错误

**原因**: `__init__.py`文件问题或模块结构不正确

**解决方案**:
```bash
# 检查是否缺少__init__.py
find . -type d -name 'backend' -o -name 'frontend' | while read d; do
    [ -f "$d/__init__.py" ] || echo "Missing: $d/__init__.py"
done

# 重新克隆仓库（如果问题持续）
git pull origin claude/question-bank-system-0RByh
```

## AI功能问题

### 问题4: AI助手不可用

**症状**: 页面显示"AI助手不可用"

**原因**: 未配置API密钥或密钥无效

**解决方案**:
```bash
# 1. 创建.env文件
cp .env.example .env

# 2. 编辑.env，添加API密钥
nano .env
# 或
code .env

# 3. 验证API密钥格式
# Claude: 以 sk-ant- 开头
# Gemini: 通常是40个字符的字符串

# 4. 重启应用
```

**验证步骤**:
```python
# 测试Claude API
python3 -c "
import os
from dotenv import load_dotenv
load_dotenv()
key = os.getenv('ANTHROPIC_API_KEY')
print(f'Claude Key: {key[:10]}... ({len(key)} chars)' if key else 'Not set')
"

# 测试Gemini API
python3 -c "
import os
from dotenv import load_dotenv
load_dotenv()
key = os.getenv('GOOGLE_API_KEY')
print(f'Gemini Key: {key[:10]}... ({len(key)} chars)' if key else 'Not set')
"
```

### 问题5: AI识别结果不准确

**症状**: OCR纠正或题目解析效果不佳

**原因**: 图片质量、AI提供商差异

**解决方案**:
1. **提高图片质量**:
   - 使用清晰的打印体
   - 确保光线充足
   - 避免模糊或倾斜
   - 推荐分辨率: 300 DPI以上

2. **切换AI提供商**:
   ```bash
   # 在.env中设置
   AI_PROVIDER=gemini  # 或 claude
   ```

3. **手动核对**:
   - 上传后对比"识别文本"和"原始OCR"标签页
   - 手动修改不准确的部分

## 数据库问题

### 问题6: 数据库错误

**症状**: `sqlalchemy.exc.XXXError`

**原因**: 数据库损坏或版本不兼容

**解决方案**:
```bash
# 1. 备份现有数据库
cp question_bank.db question_bank.db.backup

# 2. 重建数据库
rm question_bank.db
python3 app.py  # 自动创建新数据库

# 3. 如果需要恢复
cp question_bank.db.backup question_bank.db
```

### 问题7: 模板初始化失败

**症状**: "初始化预设模板失败"

**原因**: 数据库权限或模板数据格式错误

**解决方案**:
```bash
# 检查数据库文件权限
ls -l question_bank.db
chmod 644 question_bank.db

# 手动初始化模板
python3 -c "
from backend.database import DatabaseManager
from backend.api.template_manager import TemplateManager

db = DatabaseManager('question_bank.db')
db.init_db()
tm = TemplateManager(db)
result = tm.init_preset_templates()
print('模板初始化成功' if result else '模板初始化失败')
"
```

## 文件上传问题

### 问题8: 文件上传失败

**症状**: "文件太大"或"不支持的格式"

**原因**: 文件超过限制或格式不支持

**解决方案**:
```bash
# 支持的格式: JPG, PNG, PDF, BMP
# 最大文件大小: 16MB（可在app.py中修改）

# 修改最大文件大小（app.py）:
# app.config['MAX_CONTENT_LENGTH'] = 32 * 1024 * 1024  # 32MB
```

### 问题9: 上传目录权限错误

**症状**: `Permission denied: frontend/static/uploads`

**原因**: 目录不存在或无写权限

**解决方案**:
```bash
# 创建目录
mkdir -p frontend/static/uploads

# 设置权限
chmod 755 frontend/static/uploads
```

## Word导出问题

### 问题10: Word文档无法导出

**症状**: "导出失败"或下载的文件损坏

**原因**: python-docx版本问题或字体缺失

**解决方案**:
```bash
# 重新安装python-docx
pip install --upgrade python-docx

# Linux系统安装中文字体
sudo apt-get install fonts-wqy-zenhei fonts-wqy-microhei
```

## 性能问题

### 问题11: OCR识别很慢

**症状**: 处理大文件时长时间无响应

**原因**: CPU处理、文件太大

**优化方案**:
1. **减小文件大小**: 推荐单个文件<5MB
2. **分页处理**: 大型PDF分成多个小文件
3. **使用GPU** (如果可用):
   ```python
   # 修改app.py
   ocr_processor = OCRProcessor(use_gpu=True, lang='en')
   ```

### 问题12: 系统占用内存过高

**症状**: 运行一段时间后内存占用很高

**原因**: OCR模型常驻内存

**解决方案**:
```bash
# 重启应用释放内存
# 或限制进程内存（Linux）
ulimit -v 2000000  # 限制约2GB
python3 app.py
```

## 网络和端口问题

### 问题13: 端口5000被占用

**症状**: `Address already in use`

**原因**: 端口被其他程序占用

**解决方案**:
```bash
# 方案1: 查找并关闭占用进程
lsof -i :5000
kill <PID>

# 方案2: 使用其他端口（修改app.py最后一行）
# app.run(debug=True, host='0.0.0.0', port=8080)
```

### 问题14: 无法访问网页

**症状**: 浏览器显示"无法连接"

**原因**: 防火墙或绑定地址错误

**解决方案**:
```bash
# 检查应用是否运行
ps aux | grep app.py

# 检查端口监听
netstat -tulpn | grep 5000

# 确保绑定到正确的地址
# app.run(debug=True, host='0.0.0.0', port=5000)  # 允许外部访问
# app.run(debug=True, host='127.0.0.1', port=5000)  # 仅本地访问
```

## 日志和调试

### 获取详细日志

如果问题无法解决，启用详细日志：

```python
# 在app.py顶部添加
import logging
logging.basicConfig(level=logging.DEBUG)

# 或在命令行运行
FLASK_ENV=development FLASK_DEBUG=1 python3 app.py
```

### 检查系统状态

```bash
# Python版本
python3 --version

# 已安装的包
pip list | grep -E "(flask|paddle|sqlalchemy|anthropic|google)"

# 系统资源
top
# 或
htop
```

## 获取帮助

如果以上方案都无法解决问题：

1. **检查日志**: 查看控制台输出的完整错误信息
2. **搜索错误**: 将错误信息复制到搜索引擎
3. **查看文档**:
   - `README.md` - 完整文档
   - `QUICK_START.md` - 快速开始
   - `UPDATE_v3.0.md` - 版本说明
4. **Github Issues**: 提交问题到项目仓库
5. **包含信息**:
   - Python版本
   - 操作系统
   - 完整错误信息
   - 复现步骤

---

**提示**: 大多数问题可以通过重新安装依赖或检查配置文件解决。
