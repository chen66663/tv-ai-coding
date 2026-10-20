# -*- coding: utf-8 -*-
"""生成「无限进步」开机动画 mp4（1920x1080 / 30fps / 5s）"""
import os, math, shutil
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops

W, H = 1920, 1080
FPS = 30
DUR = 5.0
N = int(FPS * DUR)

TEXT = "无限进步"
FONT = "C:/Windows/Fonts/msyhbd.ttc"

OUT = r"C:/Users/qqq/tvbuild/bootanim"
FRAMES = os.path.join(OUT, "frames")

SKEW = 0.26          # 斜切量
SIZE = 250           # 字号
GAP = 34             # 字间距


def ease_out_back(t, s=1.9):
    t -= 1.0
    return t * t * ((s + 1) * t + s) + 1.0


def ease_out_cubic(t):
    return 1 - (1 - t) ** 3


def ease_in_out(t):
    return t * t * (3 - 2 * t)


# ---------- 单字图层 ----------
def make_char(ch, size=SIZE):
    font = ImageFont.truetype(FONT, size)
    box = font.getbbox(ch)
    w = box[2] - box[0] + 40
    h = box[3] - box[1] + 40
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.text((20 - box[0], 20 - box[1]), ch, font=font, fill=(255, 255, 255, 255))

    # 竖向渐变
    grad = Image.new("L", (1, h))
    for y in range(h):
        t = y / max(1, h - 1)
        grad.putpixel((0, y), int(255 - 70 * t))
    grad = grad.resize((w, h))
    body = Image.new("RGBA", (w, h), (200, 214, 232, 255))
    body.putalpha(ImageChops.multiply(img.getchannel("A"), grad))

    # 斜切（仿射）
    sk = img.transform(
        (w + int(h * SKEW), h), Image.AFFINE,
        (1, -SKEW, h * SKEW, 0, 1, 0), resample=Image.BICUBIC)
    skb = body.transform(
        (w + int(h * SKEW), h), Image.AFFINE,
        (1, -SKEW, h * SKEW, 0, 1, 0), resample=Image.BICUBIC)

    # 外发光
    glow = skb.filter(ImageFilter.GaussianBlur(26))
    canvas = Image.new("RGBA", (skb.width + 100, h + 100), (0, 0, 0, 0))
    canvas.alpha_composite(glow, (50, 50))
    canvas.alpha_composite(glow, (50, 50))
    canvas.alpha_composite(skb, (50, 50))
    # 裁掉透明边，靠 GAP 控制真实间距
    bbox = canvas.split()[3].getbbox()
    if bbox:
        canvas = canvas.crop(bbox)
    return canvas


def build_chars():
    chars = [make_char(c) for c in TEXT]
    total = sum(c.width for c in chars) + GAP * (len(chars) - 1)
    print("total_w=", total)
    return chars, total


# ---------- 背景 ----------
def make_bg():
    bg = Image.new("RGB", (W, H), (5, 7, 11))
    # 中心柔光
    glow = Image.new("RGB", (W, H), (5, 7, 11))
    d = ImageDraw.Draw(glow)
    for r in range(560, 0, -8):
        k = (1 - r / 560) ** 2
        col = (int(5 + 18 * k), int(7 + 26 * k), int(11 + 46 * k))
        d.ellipse([W // 2 - r * 1.6, H // 2 - r, W // 2 + r * 1.6, H // 2 + r], fill=col)
    return glow.filter(ImageFilter.GaussianBlur(60))


def main():
    if os.path.isdir(FRAMES):
        shutil.rmtree(FRAMES)
    os.makedirs(FRAMES, exist_ok=True)

    chars, total_w = build_chars()
    bg = make_bg()

    # 光带
    beam = Image.new("L", (520, H), 0)
    bd = ImageDraw.Draw(beam)
    for x in range(520):
        bd.line([(x, 0), (x, H)], fill=int(90 * math.sin(math.pi * x / 520) ** 2))
    beam = beam.filter(ImageFilter.GaussianBlur(40))

    start_x = (W - total_w) // 2
    y_center = H // 2

    for f in range(N):
        t = f / FPS
        frame = bg.copy()

        # 背景呼吸
        breathe = 0.82 + 0.18 * math.sin(min(1.0, t / 1.2) * math.pi / 2)
        frame = Image.blend(Image.new("RGB", (W, H), (3, 4, 7)), frame, breathe)

        fx = start_x
        for i, ch in enumerate(chars):
            # 每字入场时间：0.55s 开始，间隔 0.34s
            t0 = 0.55 + i * 0.34
            dur = 0.72
            if t < t0:
                fx += ch.width + GAP
                continue
            p = min(1.0, (t - t0) / dur)

            # 从左飞入 + 回弹
            e = ease_out_back(p)
            dx = int(-820 * (1 - e))
            scale = 0.62 + 0.38 * ease_out_cubic(p)

            # 落位瞬间的白闪
            flash = 0.0
            if 0.85 < p <= 1.0:
                flash = (p - 0.85) / 0.15 * (1 - (p - 0.85) / 0.15)

            w = int(ch.width * scale)
            h = int(ch.height * scale)
            if w < 4 or h < 4:
                fx += ch.width + GAP
                continue
            cw = ch.resize((w, h), Image.LANCZOS)

            alpha = min(1.0, p * 3.2)
            if flash > 0.02:
                cw = Image.blend(cw, Image.new("RGBA", cw.size, (255, 255, 255, 255)), flash * 0.55)
            if alpha < 1.0:
                a = cw.getchannel("A").point(lambda v: int(v * alpha))
                cw.putalpha(a)

            px = fx + (ch.width - w) // 2 + dx
            py = y_center - h // 2 + int((1 - ease_out_cubic(p)) * 26)
            frame.paste(cw, (px, py), cw)

            # 落位光晕
            if flash > 0.05:
                ring = Image.new("RGBA", (w + 240, h + 240), (0, 0, 0, 0))
                rd = ImageDraw.Draw(ring)
                rr = int((0.5 + (1 - flash)) * 200)
                rd.ellipse([w // 2 + 120 - rr, h // 2 + 120 - rr,
                            w // 2 + 120 + rr, h // 2 + 120 + rr],
                           fill=(255, 255, 255, int(52 * flash)))
                ring = ring.filter(ImageFilter.GaussianBlur(38))
                frame.paste(ring, (px - 120, py - 120), ring)

            fx += ch.width + GAP

        # 3.05s 之后：光带横扫
        if t > 3.05:
            bp = min(1.0, (t - 3.05) / 0.95)
            bx = int(-520 + (W + 1040) * ease_in_out(bp))
            frame.paste(Image.new("RGB", (520, H), (255, 255, 255)),
                        (bx, 0), beam)

        # 4.35s 之后：整体上浮 + 淡出
        if t > 4.35:
            fp = min(1.0, (t - 4.35) / 0.65)
            frame = Image.blend(frame, Image.new("RGB", (W, H), (3, 4, 7)), fp)

        frame.convert("RGB").save(os.path.join(FRAMES, "f%04d.png" % f), quality=92)
        if f % 30 == 0:
            print("frame", f, "/", N, flush=True)

    print("done", N, "frames")


if __name__ == "__main__":
    main()
