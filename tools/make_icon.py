#!/usr/bin/env python3
"""
Генератор иконки OLCVPN в стиле Aurora Glass.

Рисует 1024x1024 непрозрачный PNG: глубоко-синий фон, мягкое aurora-свечение
(teal -> green -> blue), стеклянный орб с aurora-кольцом и замком — визуальное
эхо экрана подключения приложения.

Запуск:  python tools/make_icon.py
Выход:   App/Assets.xcassets/AppIcon.appiconset/icon-1024.png  (RGB, без альфы)
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "App", "Assets.xcassets",
                   "AppIcon.appiconset", "icon-1024.png")

SIZE = 1024
SS = 2                      # суперсэмплинг для гладких краёв
W = SIZE * SS
CX = CY = W // 2

# Палитра (совпадает с Theme.swift)
NAVY_TOP    = (7, 11, 22)
NAVY_BOTTOM = (17, 24, 46)
TEAL   = (45, 212, 191)
GREEN  = (52, 211, 153)
BLUE   = (59, 130, 246)
INDIGO = (99, 102, 241)


def vertical_gradient(top, bottom):
    """Вертикальный градиент как float-массив HxWx3."""
    t = np.linspace(0, 1, W)[:, None]            # по вертикали
    top = np.array(top, float)
    bottom = np.array(bottom, float)
    col = top[None, :] * (1 - t) + bottom[None, :] * t   # Wx3
    return np.repeat(col[:, None, :], W, axis=1)          # WxWx3


def radial_glow(center, radius, color, intensity=1.0):
    """Аддитивное радиальное свечение."""
    yy, xx = np.mgrid[0:W, 0:W]
    d = np.sqrt((xx - center[0]) ** 2 + (yy - center[1]) ** 2)
    falloff = np.clip(1 - d / radius, 0, 1) ** 2
    return falloff[:, :, None] * np.array(color, float) * intensity


def gradient_image(c_top, c_mid, c_bottom, size):
    """RGBA-картинка с вертикальным трёхцветным градиентом."""
    t = np.linspace(0, 1, size)[:, None]
    top, mid, bot = (np.array(c, float) for c in (c_top, c_mid, c_bottom))
    upper = top * (1 - t * 2).clip(0, 1) + mid * (t * 2).clip(0, 1)
    lower = mid * (2 - t * 2).clip(0, 1) + bot * (t * 2 - 1).clip(0, 1)
    col = np.where(t < 0.5, upper, lower)
    arr = np.repeat(col[:, None, :], size, axis=1).astype(np.uint8)
    rgba = np.dstack([arr, np.full((size, size), 255, np.uint8)])
    return Image.fromarray(rgba, "RGBA")


def main():
    # --- фон + aurora-свечение (numpy) ---
    base = vertical_gradient(NAVY_TOP, NAVY_BOTTOM)
    glow = np.zeros_like(base)
    glow += radial_glow((CX - 260 * SS, CY - 300 * SS), 520 * SS, TEAL,   0.55)
    glow += radial_glow((CX + 300 * SS, CY - 160 * SS), 560 * SS, BLUE,   0.50)
    glow += radial_glow((CX - 120 * SS, CY + 320 * SS), 520 * SS, INDIGO, 0.45)
    glow += radial_glow((CX + 240 * SS, CY + 300 * SS), 460 * SS, GREEN,  0.40)
    # screen-смешивание свечения с фоном
    b = base / 255.0
    g = np.clip(glow, 0, 255) / 255.0
    out = (1 - (1 - b) * (1 - g)) * 255.0
    img = Image.fromarray(out.clip(0, 255).astype(np.uint8), "RGB").convert("RGBA")

    # --- aurora-кольцо ---
    ring_outer, ring_inner = 360 * SS, 312 * SS
    ring_mask = Image.new("L", (W, W), 0)
    md = ImageDraw.Draw(ring_mask)
    md.ellipse([CX - ring_outer, CY - ring_outer, CX + ring_outer, CY + ring_outer], fill=255)
    md.ellipse([CX - ring_inner, CY - ring_inner, CX + ring_inner, CY + ring_inner], fill=0)
    ring_grad = gradient_image(TEAL, GREEN, BLUE, W)
    # свечение кольца
    ring_layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ring_layer.paste(ring_grad, (0, 0), ring_mask)
    glow_ring = ring_layer.filter(ImageFilter.GaussianBlur(26 * SS))
    img = Image.alpha_composite(img, glow_ring)
    img = Image.alpha_composite(img, ring_layer)

    # --- стеклянная сердцевина ---
    core_r = 286 * SS
    core = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    cd = ImageDraw.Draw(core)
    cd.ellipse([CX - core_r, CY - core_r, CX + core_r, CY + core_r], fill=(18, 26, 48, 235))
    # верхний блик
    hi = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    hd = ImageDraw.Draw(hi)
    hd.ellipse([CX - core_r, CY - core_r - 60 * SS, CX + core_r, CY + 80 * SS],
               fill=(255, 255, 255, 30))
    hi = hi.filter(ImageFilter.GaussianBlur(40 * SS))
    core = Image.alpha_composite(core, hi)
    img = Image.alpha_composite(img, core)

    # --- замок (эхо экрана подключения) ---
    lock = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ld = ImageDraw.Draw(lock)
    body_w, body_h = 230 * SS, 180 * SS
    body_x0, body_y0 = CX - body_w // 2, CY - 20 * SS
    body_x1, body_y1 = CX + body_w // 2, CY - 20 * SS + body_h
    # дужка
    sh_r = 78 * SS
    sh_cx, sh_cy = CX, body_y0 - 6 * SS
    ld.arc([sh_cx - sh_r, sh_cy - sh_r, sh_cx + sh_r, sh_cy + sh_r],
           start=180, end=360, fill=(226, 238, 255, 255), width=30 * SS)
    # корпус (заливаем aurora-градиентом через маску)
    body_mask = Image.new("L", (W, W), 0)
    bd = ImageDraw.Draw(body_mask)
    bd.rounded_rectangle([body_x0, body_y0, body_x1, body_y1], radius=42 * SS, fill=255)
    body_grad = gradient_image(TEAL, GREEN, BLUE, W)
    lock.paste(body_grad, (0, 0), body_mask)
    # замочная скважина (тёмная)
    kd = ImageDraw.Draw(lock)
    kh_cx, kh_cy = CX, body_y0 + body_h // 2 - 6 * SS
    kd.ellipse([kh_cx - 26 * SS, kh_cy - 26 * SS, kh_cx + 26 * SS, kh_cy + 26 * SS],
               fill=(12, 18, 34, 255))
    kd.polygon([(kh_cx - 14 * SS, kh_cy + 6 * SS), (kh_cx + 14 * SS, kh_cy + 6 * SS),
                (kh_cx + 24 * SS, kh_cy + 64 * SS), (kh_cx - 24 * SS, kh_cy + 64 * SS)],
               fill=(12, 18, 34, 255))
    img = Image.alpha_composite(img, lock)

    # --- финал: вниз до 1024, без альфы ---
    img = img.convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img.save(OUT, "PNG")
    print("saved:", os.path.normpath(OUT), img.size, img.mode)


if __name__ == "__main__":
    main()
