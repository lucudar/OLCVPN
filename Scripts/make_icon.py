#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Генератор иконки OLCVPN (1024x1024) — минимализм (Mono).

Почти-чёрный фон, тонкое бледное белое кольцо и яркая «бегущая» дуга —
тот же язык, что и RotatingRing в приложении.

Рисуется в 4x и уменьшается для сглаживания (anti-aliasing).
Цвета кольца/дуги уже смешаны с фоном (без альфа-канала).

Вывод: App/Assets.xcassets/AppIcon.appiconset/icon-1024.png
"""
import math
import os

from PIL import Image, ImageDraw

SS = 4                       # коэффициент суперсэмплинга
SIZE = 1024 * SS

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "App", "Assets.xcassets",
                   "AppIcon.appiconset", "icon-1024.png")

BG = (10, 10, 11)            # Theme.bgDeep 0x0A0A0B
RING = (39, 39, 40)          # бледное кольцо (белый ~0.12 поверх фона)
ARC = (247, 247, 248)        # яркая дуга (Theme.textPrimary)


def main():
    img = Image.new("RGB", (SIZE, SIZE), BG)
    draw = ImageDraw.Draw(img)

    cx = cy = SIZE / 2.0
    R = SIZE * 0.34          # радиус кольца
    w = int(SIZE * 0.025)    # толщина линии
    bbox = [cx - R, cy - R, cx + R, cy + R]

    # Бледное статичное кольцо
    draw.ellipse(bbox, outline=RING, width=w)

    # Яркая бегущая дуга (~25% окружности) с круглыми концами
    start, end = -105, -15
    draw.arc(bbox, start, end, fill=ARC, width=w)
    for ang in (start, end):
        px = cx + R * math.cos(math.radians(ang))
        py = cy + R * math.sin(math.radians(ang))
        r = w / 2.0
        draw.ellipse([px - r, py - r, px + r, py + r], fill=ARC)

    img = img.resize((1024, 1024), Image.LANCZOS)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img.save(OUT, "PNG")
    print("Wrote", OUT)


if __name__ == "__main__":
    main()
