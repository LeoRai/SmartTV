#!/usr/bin/env python3
"""Рисует иконку и баннер приложения (нужен Pillow). Готовые PNG лежат в res/drawable, запускать не обязательно."""

import os

from PIL import Image, ImageDraw, ImageFont

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "res", "drawable")
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
SCALE = 4  # рисуем крупнее и уменьшаем — так края получаются гладкими


def gradient(w, h):
    img = Image.new("RGB", (w, h))
    top, bottom = (16, 120, 140), (20, 40, 110)
    px = img.load()
    for y in range(h):
        t = y / (h - 1)
        color = tuple(round(a + (b - a) * t) for a, b in zip(top, bottom))
        for x in range(w):
            px[x, y] = color
    return img


def draw_tv(d, cx, cy, size):
    """Телевизор с молнией: «ускорение ТВ»."""
    w, h = size, size * 0.62
    line = size * 0.07
    left, top = cx - w / 2, cy - h / 2 - size * 0.06
    d.rounded_rectangle([left, top, left + w, top + h], radius=size * 0.08, outline="white", width=round(line))
    d.polygon([(cx - size * 0.16, top + h + size * 0.14), (cx + size * 0.16, top + h + size * 0.14),
               (cx + size * 0.08, top + h), (cx - size * 0.08, top + h)], fill="white")
    s = size * 0.42
    bolt = [(0.10, -0.50), (-0.28, 0.08), (-0.02, 0.08), (-0.12, 0.50), (0.28, -0.10), (0.02, -0.10)]
    d.polygon([(cx + x * s, top + h / 2 + y * s) for x, y in bolt], fill=(255, 213, 79))


def save(img, name, size):
    os.makedirs(OUT, exist_ok=True)
    img.resize(size, Image.LANCZOS).save(os.path.join(OUT, name), optimize=True)


def main():
    w, h = 256 * SCALE, 256 * SCALE
    icon = gradient(w, h)
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, h - 1], radius=w * 0.22, fill=255)
    draw_tv(ImageDraw.Draw(icon), w / 2, h / 2, w * 0.62)
    icon = icon.convert("RGBA")
    icon.putalpha(mask)
    save(icon, "icon.png", (256, 256))

    w, h = 640 * SCALE, 360 * SCALE
    banner = gradient(w, h)
    d = ImageDraw.Draw(banner)
    draw_tv(d, h * 0.42, h / 2, h * 0.5)
    left, right = h * 0.78, w - h * 0.1
    size = round(h * 0.22)
    font = ImageFont.truetype(FONT, size)
    while font.getlength("ТВ Тюнер") > right - left:  # подбираем шрифт под ширину баннера
        size -= 4
        font = ImageFont.truetype(FONT, size)
    d.text((left, h / 2), "ТВ Тюнер", font=font, fill="white", anchor="lm")
    save(banner, "banner.png", (640, 360))


if __name__ == "__main__":
    main()
