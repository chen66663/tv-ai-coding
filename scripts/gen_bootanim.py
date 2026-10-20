# -*- coding: utf-8 -*-
"""「无限进步」开机动画 v2：纯黑底 + 白字 + 从右往左依次滑入，无特效"""
import os, shutil
from PIL import Image, ImageDraw, ImageFont

W, H = 1920, 1080
FPS = 30
DUR = 5.0
N = int(FPS * DUR)

TEXT = "无限进步"
FONT = "C:/Windows/Fonts/msyhbd.ttc"
SIZE = 250
GAP = 40

OUT = r"C:/Users/qqq/tvbuild/bootanim"
FRAMES = os.path.join(OUT, "frames")


def ease_out_quint(t):
    return 1 - (1 - t) ** 5


TILT = 8             # 整字倾斜角度（顺时针），保证画布自动扩展不裁切


def make_char(ch):
    """纯白正体字，整体旋转出倾斜感；expand=True 保证四周不被裁"""
    font = ImageFont.truetype(FONT, SIZE)
    box = font.getbbox(ch)
    w = box[2] - box[0] + 16
    h = box[3] - box[1] + 16
    img = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(img)
    d.text((8 - box[0], 8 - box[1]), ch, font=font, fill=255)

    # expand=True 会自动放大画布，旋转不会丢掉任何笔画
    return img.rotate(-TILT, resample=Image.BICUBIC, expand=True)


def main():
    if os.path.isdir(FRAMES):
        shutil.rmtree(FRAMES)
    os.makedirs(FRAMES, exist_ok=True)

    chars = [make_char(c) for c in TEXT]
    total_w = sum(c.width for c in chars) + GAP * (len(chars) - 1)
    start_x = (W - total_w) // 2
    y0 = H // 2 - max(c.height for c in chars) // 2
    print("total_w=", total_w, "start_x=", start_x)

    # 演出节奏：每字间隔 0.26s，单字滑入 1.05s（慢一点更丝滑）
    T0 = 0.35
    STEP = 0.26
    DUR_IN = 1.05
    SLIDE = 560          # 起点在右侧多远

    for f in range(N):
        t = f / FPS
        frame = Image.new("RGB", (W, H), (0, 0, 0))

        fx = start_x
        for i, ch in enumerate(chars):
            t0 = T0 + i * STEP
            if t < t0:
                fx += ch.width + GAP
                continue
            p = min(1.0, (t - t0) / DUR_IN)
            dx = int(SLIDE * (1 - ease_out_quint(p)))
            alpha = min(1.0, p * 2.4)

            layer = ch
            if alpha < 1.0:
                layer = ch.point(lambda v: int(v * alpha))

            px = fx + dx
            frame.paste(Image.new("RGB", layer.size, (255, 255, 255)), (px, y0), layer)

            fx += ch.width + GAP

        if t > 4.40:
            k = min(1.0, (t - 4.40) / 0.55)
            frame = frame.point(lambda v: int(v * (1 - k)))

        frame.save(os.path.join(FRAMES, "f%04d.png" % f))
        if f % 30 == 0:
            print("frame", f, "/", N, flush=True)

    print("done")


if __name__ == "__main__":
    main()
