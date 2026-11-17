# 部署与使用手册（DEPLOY）

> 版本：v1.0　对应 `docs/spec.md`　维护：Agent-D（后端装配 + 架构）

## 1. 后端部署

### 1.1 本地运行（推荐开发用）

前置：Python 3.10+。

```bash
cd backend

# 虚拟环境
python -m venv .venv
# Windows:
.venv\Scripts\activate
# macOS / Linux:
source .venv/bin/activate

# 安装依赖
pip install -r requirements.txt

# 配置环境变量（见 §3 API Key 配置）
cp .env.example .env

# 启动（开发热重载）
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

验证：
- 健康检查：`curl http://localhost:8000/api/health` → `{"status":"ok",...}`
- API 文档：浏览器打开 http://localhost:8000/docs
- 首次启动自动建表并写入中文知识点种子（`backend/data/wrongbook.db`）。

可选重型依赖（OCR 公式 / 中文印刷体识别，未装则自动降级，见 `requirements.txt` 末尾）：

```bash
pip install paddlepaddle==2.6.2 paddleocr==2.7.3 texify
# 注意：首次运行 PaddleOCR 会自动下载 PP-OCRv5 模型（约几十 MB）
```

### 1.2 Docker Compose 一键启动（推荐部署用）

```bash
cd backend
cp .env.example .env     # compose 依赖 .env 存在
docker compose up -d --build
docker compose logs -f backend   # 查看日志
```

- 端口：`8000:8000`；数据卷：`./data:/app/data`（SQLite + ChromaDB 持久化）。
- 升级镜像后重启：`docker compose up -d --build`。
- 停止/清理：`docker compose down`（加 `-v` 会删除数据卷，慎用）。

镜像说明（`backend/Dockerfile`）：基于 `python:3.10-slim`，只装核心依赖；
paddleocr/texify/torch 以注释形式预留为可选构建层（体积大），缺失时后端自动降级。

### 1.3 当前线上部署（腾讯云轻量 · 韩国首尔）

> 2026-10 起使用；1 vCPU/2 核 1 GiB 机型，为省内存**未用 Docker**，改为 venv + systemd。

| 项 | 值 |
|---|---|
| 公网 IP | `8.213.136.134` |
| 对外地址 | `http://8.213.136.134/api`（Caddy 80 端口纯 HTTP 反代 → `127.0.0.1:8000`） |
| 代码目录 | `/opt/ai-wrong/backend` |
| 运行方式 | systemd 服务 `ai-wrong`，`venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000` |
| 环境变量 | `/opt/ai-wrong/backend/.env`（`LLM_API_KEY` / `MODEL` / `REGISTER_ENABLED=false` / 预置账号） |
| 依赖 | `requirements-slim.txt`（无 Paddle/RapidOCR/ChromaDB；OCR 走视觉大模型兜底、向量检索走内存） |
| 内存 | 已加 2 GiB swap |
| 反向代理 | Caddy（`/etc/caddy/Caddyfile`，HTTP 80；HTTPS 配置备份 `Caddyfile.https.bak`） |

常用运维：

```bash
systemctl status ai-wrong          # 状态
journalctl -u ai-wrong -n 100 -f   # 日志
systemctl restart ai-wrong         # 重启
systemctl restart caddy            # 改反代后重启
```

**换后端地址无需重新打包 App**：修改配置仓库
`https://github.com/Xyihang/ai-wrong-backend-config` 里的 `backend-config.json`：

```json
{ "apiBaseUrl": "http://新地址/api" }
```

App 每次启动会拉取（GitHub API → Gitee raw → GitHub raw），失败则用本地缓存/打包默认值。

## 2. Flutter 前端构建（跨端）

前置：Flutter SDK ≥ 3.4（`flutter --version` 确认），Dart SDK ≥ 3.4。

```bash
cd frontend
flutter pub get
# 如修改了模型/序列化代码需重新生成：
# dart run build_runner build --delete-conflicting-outputs
```

后端地址配置：App 启动会自动从远程配置仓库读取（见 §1.3），无需改代码。
构建时也可用兜底参数固定地址：

```bash
flutter build apk --release --dart-define=API_BASE_URL=http://8.213.136.134/api
```

真机调试若连局域网后端，请填局域网 IP（如 `http://192.168.x.x:8000/api`），不要用 `localhost`。

### 2.1 Android（APK）

```bash
flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk
```

权限（`android/app/src/main/AndroidManifest.xml`）：
- `CAMERA`（拍照）
- `READ_MEDIA_IMAGES`（Android 13+ 读相册）或 `READ_EXTERNAL_STORAGE`（旧版）
- `INTERNET`（访问后端）

注意：Android 9+ 默认禁止明文 HTTP，需在 manifest 的 `<application>` 加
`android:usesCleartextTraffic="true"`（或配置 networkSecurityConfig）才能访问
`http://` 后端。

### 2.2 iOS

```bash
flutter build ios --release   # 需 macOS + Xcode
```

权限（`ios/Runner/Info.plist`）：
- `NSCameraUsageDescription`（拍照）
- `NSPhotoLibraryUsageDescription`（相册）
- `NSAppTransportSecurity` → 允许本地 HTTP（`NSAllowsLocalNetworking` 或针对开发环境的 ATS 例外）

### 2.3 Windows

```bash
flutter build windows --release
# 产物：build/windows/x64/runner/Release/
```

无需额外权限；确保系统能访问后端端口（防火墙放行 8000）。

### 2.4 macOS

```bash
flutter build macos --release
```

沙盒应用访问网络需在 `macos/Runner/DebugProfile.entitlements` 与
`Release.entitlements` 中启用 `com.apple.security.network.client`；
相册权限视部署形态（macOS 13+ 的 Photos 权限）按需配置。

### 2.5 Web

```bash
flutter build web --release
# 部署产物：build/web/（可交给任意静态服务器 / nginx）
```

- 浏览器访问后端需后端 CORS 白名单包含前端来源（默认 `CORS_ORIGINS=*` 已放开）。
- 图片选择走 `image_picker` Web 实现，无需特殊权限。

## 3. API Key 配置与模型切换

后端支持任意 **OpenAI 兼容** 大模型（DeepSeek / 通义千问 / Moonshot / 本地 vLLM 等）。

### 3.1 通过 .env（重启生效）

```ini
LLM_BASE_URL=https://api.deepseek.com/v1
LLM_API_KEY=sk-xxxxxxxx
LLM_MODEL=deepseek-chat
LLM_ENABLED=true
```

### 3.2 通过运行时设置接口（免重启）

```
GET /api/settings          # 读取（api_key 显示为 ******）
PUT /api/settings
{
  "llm_enabled": true,
  "base_url": "https://api.deepseek.com/v1",
  "model": "deepseek-chat",
  "api_key": "sk-xxxxxxxx"   # 传 ****** 视为不修改
}
```

保存后 LLM 客户端自动重建，立即生效。切换其它厂商示例：

| 厂商 | base_url | model 示例 |
|---|---|---|
| DeepSeek | `https://api.deepseek.com/v1` | `deepseek-chat` |
| 通义千问 | `https://dashscope.aliyuncs.com/compatible-mode/v1` | `qwen-plus` |
| Moonshot | `https://api.moonshot.cn/v1` | `moonshot-v1-8k` |
| 本地 vLLM/Ollama | `http://127.0.0.1:8000/v1` | 本地模型名 |

## 4. 核心功能操作手册

### 4.1 拍照错题一键入库（P0）

1. App 首页点「拍照 / 从相册选择」，端侧裁剪/矫正后上传；
2. 后端自动执行：OCR 识别 → AI 结构化（科目/知识点/题型/难度/题干/答案/解析/错因）；
3. 结果页自动弹出**同类错题弹窗**（TopN：相似度、缩略图、错因、订正答案、收录时间）；
4. 确认无误后点「保存」→ 题目入库（SQLite + 向量库同步）。

异常处理：
- 「未识别到文字」→ 图片过暗/模糊/非题目，换图重试；
- LLM 未配置 → 自动降级，仅存 OCR 原文（可后续在详情页编辑补全）。

### 4.2 错题本管理

- 列表页按 **科目 / 知识点 / 题型 / 掌握程度 / 关键词** 多维筛选（`GET /api/questions`）；
- 详情页编辑题干/答案/解析、改标签、标记掌握程度（`PATCH /api/questions/{id}`）；
- 列表长按多选 → 批量删除 / 批量移动知识点（`DELETE /api/questions`、`POST /api/questions/batch-move`）。

### 4.3 导出 PDF

- 错题本 → 导出：选择「纯题版」或「含答案解析版」（`GET /api/export/pdf?mode=...`）；
- 按知识点生成「巩固练习卷」（不含答案，预留答题空行，`GET /api/export/worksheet`）。

### 4.4 公式识别

后端 texify 输出 LaTeX（`latex_text`），前端 `flutter_math_fork` / katex 渲染。
未安装 texify 时该字段为空，不影响其余流程。

### 4.5 试卷批量导入（P2，占位）

`POST /api/import/paper` 当前返回 **501「整页试卷切分功能开发中」**，
前端对应按钮显示「敬请期待」。

## 5. 常见问题（FAQ）

| 现象 | 原因与处理 |
|---|---|
| `/api/health` 返回 `db:error` | SQLite 文件目录不可写；检查 `backend/data` 权限 / 卷挂载 |
| analyze 一直「未识别到文字」 | 未安装 paddleocr（降级）或图片质量差；安装依赖或换图 |
| 前端连不上后端 | 真机用局域网 IP；Android 加 `usesCleartextTraffic`；检查防火墙 8000 端口 |
| ChromaDB 相关日志告警 | 未安装 chromadb，已自动降级内存索引，功能可用（重启丢失索引） |
| PUT /settings 报「不支持的设置项」 | 仅接受 `llm_enabled/model/base_url/api_key` 四个键 |

## 6. 后续优化建议

### 6.1 YOLO 题目检测微调（P1 进阶）
当前题目区域切分基于版面投影规则（`app/ocr/layout.py`），对复杂排版（多栏、混排图、
手写批注）鲁棒性有限。`layout.py` 已预留 `yolo_detector` 扩展点：
1. 收集真实错题照片，标注题目边界框（labelme / CVAT）；
2. 微调 YOLOv8 目标检测模型；
3. 在 `layout.py` 注入模型输出替代/增强投影规则。

### 6.2 手写准确率提升（P1 进阶）
PaddleOCR 对手写体识别率偏低：
- 尝试 `PP-OCRv5` 手写模型 / 训练手写识别分支；
- 预处理增加透视矫正（端侧已裁剪，后端可二次 `deskew`）；
- 结合 LLM 语义纠错（对 OCR 文本做拼写/数学符号后处理）。

### 6.3 本地大模型接入（P2）
当前结构化依赖外部 OpenAI 兼容 API（需联网 + 按量付费）：
- 接入 vLLM / Ollama / llama.cpp 本地推理，`base_url` 指向本机即可无缝切换；
- 结合「本地优先」目标，全部 AI 能力离线化；
- 注意：本地 7B 级模型中文结构化效果与 API 大模型有差距，需实测调 prompt。

### 6.4 多端同步（P2）
当前 SQLite 单设备，`sync_version` 列已预留：
- 方案 A：后端换 Postgres（`DATABASE_URL` 已支持非 sqlite 方言）+ 加用户体系；
- 方案 B：端侧 Drift 库 + 服务端增量同步接口（按 `updated_at` / `sync_version` 增量拉取）；
- 图片同步建议对象存储（MinIO / OSS）+ 缩略图 CDN。

### 6.5 其它
- 导出 PDF 增加「按掌握程度/错因」分组、题号区间选择；
- `/api/import/paper` 接通切分流程（复用 ocr.layout + llm 结构化）完成 P2；
- 加接口鉴权（当前为内网/个人使用设计，公网部署务必加 Token）；
- 检索效果评估：沉淀测试集，对比 `matched_by` 分布与人工标注一致率。
