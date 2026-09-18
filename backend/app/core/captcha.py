"""
算术验证码（core.captcha）。

生成一张含算术题的图片（PIL 渲染 + 干扰线/噪点），答案以内存缓存保存，
注册时校验。单次有效，5 分钟过期。

- GET  /api/auth/captcha               -> {captcha_id, image_base64, ttl}
- POST /api/auth/register               -> 需携带 captcha_id + captcha_answer

说明：
- 用图片而非纯文本，增加机器解析成本；自用场景足够。
- 答案存进程内内存（与限流器一致），单进程 uvicorn 有效。
- 依赖 Pillow（requirements.txt 已有）。
"""
from __future__ import annotations

import base64
import io
import random
import secrets
import threading
import time
from typing import Dict, Optional

CAPTCHA_TTL = 300  # 5 分钟

_lock = threading.Lock()
# captcha_id -> {"answer": str, "expires": float}
_captchas: Dict[str, Dict[str, object]] = {}


def _make_expression() -> tuple[str, str]:
    """生成一道简单算术题。返回 (题目文本, 答案文本)。"""
    a = random.randint(1, 20)
    b = random.randint(1, 20)
    op = random.choice(["+", "-", "*"])
    if op == "-" and a < b:
        a, b = b, a
    if op == "*":
        a = random.randint(2, 9)
        b = random.randint(2, 9)
    text = f"{a} {op} {b}"
    answer = {"+": a + b, "-": a - b, "*": a * b}[op]
    return text, str(answer)


def _render_image(text: str) -> str:
    """把算术题渲染成带干扰的 PNG 图片，返回 base64。"""
    from PIL import Image, ImageDraw, ImageFont  # 延迟导入

    w, h = 170, 60
    img = Image.new("RGB", (w, h), (245, 245, 245))
    draw = ImageDraw.Draw(img)
    # 干扰线
    for _ in range(5):
        draw.line(
            [
                (random.randint(0, w), random.randint(0, h)),
                (random.randint(0, w), random.randint(0, h)),
            ],
            fill=(random.randint(120, 210),) * 3,
            width=1,
        )
    # 噪点
    for _ in range(120):
        draw.point(
            (random.randint(0, w - 1), random.randint(0, h - 1)),
            fill=(random.randint(0, 200),) * 3,
        )
    try:
        font = ImageFont.truetype("arial.ttf", 30)
    except Exception:  # noqa: BLE001 - 无系统字体时用默认
        font = ImageFont.load_default()
    draw.text((36, 12), text, fill=(30, 30, 30), font=font)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return base64.b64encode(buf.getvalue()).decode("ascii")


def generate_captcha() -> dict:
    """生成验证码：返回 captcha_id + base64 图片 + ttl。"""
    cid = secrets.token_urlsafe(24)
    text, answer = _make_expression()
    image_b64 = _render_image(text)
    with _lock:
        _captchas[cid] = {"answer": answer, "expires": time.time() + CAPTCHA_TTL}
    return {
        "captcha_id": cid,
        "image_base64": image_b64,
        "image_mime": "image/png",
        "ttl": CAPTCHA_TTL,
    }


def verify_captcha(captcha_id: Optional[str], answer: Optional[str]) -> bool:
    """校验验证码。单次有效，校验即销毁；过期/错误返回 False。"""
    if not captcha_id or answer is None:
        return False
    with _lock:
        rec = _captchas.pop(captcha_id, None)  # 单次使用
    if not rec:
        return False
    if time.time() > rec["expires"]:
        return False
    return str(answer).strip() == str(rec["answer"])
