# ============================================================
# AI-Wrong 后端镜像（核心依赖版，CPU 可运行）
# 构建：docker build -t ai-wrong-backend .
# 运行：docker compose up -d（推荐，见 docker-compose.yml）
# 文档：docs/DEPLOY.md
# ============================================================
FROM python:3.10-slim

WORKDIR /app

# 使用腾讯云 Ubuntu / PyPI 镜像加速（国内服务器构建更稳，避免官方源超时）
RUN sed -i 's@deb.debian.org@mirrors.cloud.tencent.com@g; s@security.debian.org@mirrors.cloud.tencent.com@g' /etc/apt/sources.list.d/debian.sources 2>/dev/null || \
    sed -i 's@deb.debian.org@mirrors.cloud.tencent.com@g; s@security.debian.org@mirrors.cloud.tencent.com@g' /etc/apt/sources.list

# opencv-python-headless 运行所需的最小系统库
RUN apt-get update && apt-get install -y --no-install-recommends \
        libgl1 \
        libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# 核心依赖（requirements.txt 中的重型依赖 paddleocr/texify/torch 默认不装）
COPY requirements.txt .
RUN pip install --no-cache-dir -i https://mirrors.cloud.tencent.com/pypi/simple -r requirements.txt

# 应用代码
COPY app ./app
COPY .env.example ./.env.example

# 数据目录（SQLite / ChromaDB / 上传），由 docker-compose 挂载卷
RUN mkdir -p /app/data

ENV PYTHONPATH=/app \
    PYTHONUNBUFFERED=1

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]

# ============================================================
# 可选：重型 OCR / 公式识别层（镜像体积显著增大，按需取消注释）
# ------------------------------------------------------------
# 未安装时后端自动降级：OCR 返回空文本（analyze 报「未识别到文字」）、
# latex_text 为空；装好后无需改任何代码。
# CPU 版：
#   RUN pip install --no-cache-dir paddlepaddle==2.6.2 paddleocr==2.7.3 texify
# GPU 版（需自行调整基础镜像与 CUDA 运行时）：
#   RUN pip install --no-cache-dir paddlepaddle-gpu paddleocr==2.7.3 texify
# ============================================================
