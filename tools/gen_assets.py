#!/usr/bin/env python
"""
Generate the Autumn store/marketing image assets:

    assets/app_icon_24bit.png   128x128  fall-themed launcher-style icon (24-bit)
    assets/app_icon_64color.png 128x128  same icon, 64-color quantized
    assets/cover_image.png/.jpg 500x500  square promo (real screenshot on fall bg)
    assets/hero_image.png       1440x720 wide banner (screenshot + title)

The watch render (assets/screen_active.png) is composited in so the marketing art
matches the actual face. Run after capturing a fresh screenshot.

Run:  python tools/gen_assets.py
"""
import os, math
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets")
FONTS = os.path.join(ROOT, "fonts-src")

LEAF_COLORS = [(224, 101, 30), (224, 168, 40), (200, 80, 30), (178, 58, 30), (212, 98, 42)]


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def vgradient(size, top, bottom):
    w, h = size
    img = Image.new("RGB", size, top)
    px = img.load()
    for y in range(h):
        c = lerp(top, bottom, y / float(h - 1))
        for x in range(w):
            px[x, y] = c
    return img


def maple_leaf(draw, x, y, r, color, outline=None):
    """Stylized maple leaf matching the watch face (pointed body + stem + midrib)."""
    hw = r * 0.62
    stem = (90, 58, 30)
    if outline:
        for dx, dy in [(-2, -2), (2, -2), (-2, 2), (2, 2), (-2, 0), (2, 0), (0, -2), (0, 2)]:
            _leaf_shape(draw, x + dx, y + dy, r, hw, outline, outline)
    _leaf_shape(draw, x, y, r, hw, color, stem)


def _leaf_shape(draw, x, y, r, hw, body, stem):
    draw.line([(x, y + r * 0.5), (x, y + r)], fill=stem, width=max(1, int(r * 0.12)))
    draw.polygon([
        (x, y - r),
        (x + hw, y - r * 0.15),
        (x + hw * 0.6, y + r * 0.5),
        (x - hw * 0.6, y + r * 0.5),
        (x - hw, y - r * 0.15),
    ], fill=body)
    draw.line([(x, y - r * 0.8), (x, y + r * 0.45)], fill=stem, width=max(1, int(r * 0.1)))


def hill_polygon(w, h, base_y, amp, wavelen, phase):
    pts = [(w, h), (0, h)]
    steps = 48
    for i in range(steps + 1):
        x = i * w / steps
        yy = base_y + amp * math.sin(x / wavelen + phase)
        pts.append((x, yy))
    return pts


def sun(draw, cx, cy, r):
    # layered glow from warm outer to pale core
    layers = [(r * 1.9, (90, 60, 26)), (r * 1.5, (154, 90, 30)),
              (r * 1.2, (255, 140, 56)), (r, (255, 179, 71)), (r * 0.66, (255, 224, 160))]
    for rad, col in layers:
        draw.ellipse([cx - rad, cy - rad, cx + rad, cy + rad], fill=col)


def load_font(name, size):
    try:
        return ImageFont.truetype(os.path.join(FONTS, name), size)
    except Exception:
        return ImageFont.load_default()


# ---------------------------------------------------------------- app icon
def gen_app_icon():
    S = 128
    img = Image.new("RGB", (S, S), (10, 7, 16))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, S - 1, S - 1], radius=20, fill=(10, 7, 16))
    d.ellipse([8, 8, S - 8, S - 8], outline=(58, 36, 16), width=3)

    # harvest sun
    sun(d, S * 0.52, S * 0.42, S * 0.13)

    # rolling hills
    d.polygon(hill_polygon(S, S, S * 0.70, 6, 26, 0.0), fill=(122, 63, 30))
    d.polygon(hill_polygon(S, S, S * 0.80, 5, 22, 1.6), fill=(92, 52, 22))

    # a few falling maple leaves
    maple_leaf(d, S * 0.30, S * 0.30, 9, LEAF_COLORS[0])
    maple_leaf(d, S * 0.74, S * 0.34, 8, LEAF_COLORS[1])
    maple_leaf(d, S * 0.62, S * 0.20, 6, LEAF_COLORS[2])

    # harvest bar
    d.rounded_rectangle([S * 0.30, S * 0.85, S * 0.70, S * 0.85 + 6], radius=3, fill=(42, 28, 14))
    d.rounded_rectangle([S * 0.30, S * 0.85, S * 0.56, S * 0.85 + 6], radius=3, fill=(255, 192, 67))

    img.save(os.path.join(ASSETS, "app_icon_24bit.png"))
    img.convert("P", palette=Image.ADAPTIVE, colors=64).convert("RGB").save(
        os.path.join(ASSETS, "app_icon_64color.png"))
    print("app_icon_24bit.png / app_icon_64color.png  128x128")


def load_watch(target):
    p = os.path.join(ASSETS, "screen_active.png")
    if not os.path.exists(p):
        return None
    im = Image.open(p).convert("RGBA").resize((target, target), Image.LANCZOS)
    # ensure clean circular alpha
    mask = Image.new("L", (target, target), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, target - 1, target - 1], fill=255)
    im.putalpha(mask)
    return im


def fall_backdrop(size):
    w, h = size
    bg = vgradient(size, (74, 142, 184), (200, 120, 56))
    # warm ground band
    g = Image.new("RGB", (w, int(h * 0.22)), (110, 58, 22))
    bg.paste(g, (0, h - int(h * 0.22)))
    d = ImageDraw.Draw(bg)
    # scattered drifting leaves (the watch render carries its own sun)
    spots = [(0.10, 0.30), (0.22, 0.62), (0.32, 0.20), (0.62, 0.50),
             (0.70, 0.18), (0.88, 0.62), (0.46, 0.74), (0.14, 0.82)]
    for i, (fx, fy) in enumerate(spots):
        maple_leaf(d, w * fx, h * fy, max(8, h * 0.018), LEAF_COLORS[i % len(LEAF_COLORS)])
    return bg


# ---------------------------------------------------------------- cover (square)
def gen_cover():
    S = 500
    bg = fall_backdrop((S, S))
    watch = load_watch(int(S * 0.86))
    if watch is not None:
        # soft drop shadow
        shadow = Image.new("RGBA", bg.size, (0, 0, 0, 0))
        sd = ImageDraw.Draw(shadow)
        wsz = watch.size[0]
        ox = (S - wsz) // 2
        oy = int(S * 0.10)
        sd.ellipse([ox - 6, oy - 6, ox + wsz + 6, oy + wsz + 6], fill=(0, 0, 0, 120))
        shadow = shadow.filter(ImageFilter.GaussianBlur(10))
        bg = Image.alpha_composite(bg.convert("RGBA"), shadow).convert("RGB")
        bg.paste(watch, (ox, oy), watch)

    d = ImageDraw.Draw(bg)
    title_f = load_font("ExocetHeavy.ttf", 52)
    _text_center(d, S / 2, S * 0.95, "AUTUMN", title_f, (255, 239, 216))
    bg.save(os.path.join(ASSETS, "cover_image.png"))
    bg.save(os.path.join(ASSETS, "cover_image.jpg"), quality=90)
    print("cover_image.png / cover_image.jpg  500x500")


# ---------------------------------------------------------------- hero (banner)
def gen_hero():
    W, H = 1440, 720
    bg = fall_backdrop((W, H))
    watch = load_watch(int(H * 0.84))
    if watch is not None:
        wsz = watch.size[0]
        ox = int(W * 0.66)
        oy = (H - wsz) // 2
        shadow = Image.new("RGBA", bg.size, (0, 0, 0, 0))
        sd = ImageDraw.Draw(shadow)
        sd.ellipse([ox - 10, oy - 10, ox + wsz + 10, oy + wsz + 10], fill=(0, 0, 0, 120))
        shadow = shadow.filter(ImageFilter.GaussianBlur(16))
        bg = Image.alpha_composite(bg.convert("RGBA"), shadow).convert("RGB")
        bg.paste(watch, (ox, oy), watch)

    d = ImageDraw.Draw(bg)
    title_f = load_font("ExocetHeavy.ttf", 110)
    sub_f = load_font("SegoeUILight.ttf", 40)
    _text(d, W * 0.07, H * 0.34, "AUTUMN", title_f, (255, 239, 216))
    _text(d, W * 0.075, H * 0.50, "A golden-hour fall foliage watch face", sub_f, (255, 224, 170))
    _text(d, W * 0.075, H * 0.57, "for Garmin Fenix 8 & tactix 8", sub_f, (255, 224, 170))
    bg.save(os.path.join(ASSETS, "hero_image.png"))
    print("hero_image.png  1440x720")


def _text(d, x, y, s, font, color):
    d.text((x + 2, y + 2), s, font=font, fill=(0, 0, 0))
    d.text((x, y), s, font=font, fill=color)


def _text_center(d, cx, cy, s, font, color):
    l, t, r, b = d.textbbox((0, 0), s, font=font)
    _text(d, cx - (r - l) / 2, cy - (b - t) / 2, s, font, color)


if __name__ == "__main__":
    gen_app_icon()
    gen_cover()
    gen_hero()
    print("Done.")
