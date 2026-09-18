# -*- coding: utf-8 -*-
"""复现：3 道题整页走后端 analyze，检查返回各字段是否完整（题干有、解析空？）。"""
import io
import time
import requests
from PIL import Image, ImageDraw, ImageFont

BASE = "http://127.0.0.1:8000/api"
for _ in range(30):
    try:
        requests.get(BASE + "/health", timeout=3); break
    except Exception:
        time.sleep(0.5)

r = requests.post(BASE + "/auth/login", json={"username": "admintest", "password": "admintest"}, timeout=10)
tok = r.json()["access_token"]
headers = {"Authorization": f"Bearer {tok}"}

# 3 道题整页（每题多行，模拟真实卷子）
questions = [
    ["一、解方程：x^2 - 5x + 6 = 0", "A. x=2  B. x=3", "C. x=1  D. x=6"],
    ["二、计算：3/4 + 1/2 等于多少？", "A. 1  B. 5/4", "C. 1/4  D. 3/2"],
    ["三、判断：三角形内角和是 180 度。", "A. 正确  B. 错误", ""],
]
img = Image.new("RGB", (900, 640), "white")
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype("simhei.ttf", 24)
except Exception:
    font = ImageFont.load_default()
y = 40
for q in questions:
    for ln in q:
        if ln:
            d.text((40, y), ln, fill="black", font=font)
        y += 36
    y += 70

buf = io.BytesIO(); img.save(buf, format="PNG")
r2 = requests.post(
    BASE + "/questions/analyze",
    files={"file": ("t.png", buf.getvalue(), "image/png")},
    data={"subject": "数学", "has_vision_key": "true", "use_vision_mode": "false"},
    headers=headers, timeout=180,
)
print("status:", r2.status_code)
if r2.status_code != 200:
    print("detail:", r2.text[:300]); raise SystemExit
rec = r2.json()
print("=== 返回字段检查 ===")
for k in ["subject", "stem", "answer", "analysis", "mistake_reason", "knowledge_points", "question_type"]:
    v = rec.get(k)
    if isinstance(v, str):
        print(f"  {k}: {repr(v[:120]) if v else '(空!)'}")
    else:
        print(f"  {k}: {v}")
