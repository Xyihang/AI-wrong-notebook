#!/bin/bash

echo "==================== 题库管理系统启动脚本 ===================="
echo ""

# 检查Python版本
echo "1. 检查Python版本..."
python3 --version || { echo "错误: Python3未安装"; exit 1; }
echo ""

# 检查并创建虚拟环境（可选）
if [ ! -d "venv" ]; then
    echo "2. 创建虚拟环境..."
    python3 -m venv venv
    echo "   ✓ 虚拟环境已创建"
else
    echo "2. 虚拟环境已存在"
fi
echo ""

# 激活虚拟环境
echo "3. 激活虚拟环境..."
source venv/bin/activate || { echo "警告: 无法激活虚拟环境，继续使用系统Python"; }
echo ""

# 安装依赖
echo "4. 检查并安装依赖..."
pip install -q --upgrade pip
pip install -q -r requirements.txt
echo "   ✓ 依赖安装完成"
echo ""

# 检查配置文件
echo "5. 检查配置文件..."
if [ ! -f ".env" ]; then
    echo "   警告: .env文件不存在"
    echo "   提示: 复制.env.example到.env并配置API密钥"
    echo "   命令: cp .env.example .env"
    echo "   然后编辑.env文件填入你的API密钥"
else
    echo "   ✓ .env文件存在"
fi
echo ""

# 创建必要的目录
echo "6. 创建必要的目录..."
mkdir -p frontend/static/uploads
mkdir -p logs
echo "   ✓ 目录已创建"
echo ""

# 启动应用
echo "7. 启动Flask应用..."
echo "=========================================================="
echo ""
echo "  🚀 应用启动地址: http://localhost:5000"
echo ""
echo "  提示:"
echo "  - 首次运行会下载PaddleOCR模型（需要网络）"
echo "  - 如需使用AI功能，请先配置.env文件"
echo "  - 按 Ctrl+C 停止应用"
echo ""
echo "=========================================================="
echo ""

python3 app.py
