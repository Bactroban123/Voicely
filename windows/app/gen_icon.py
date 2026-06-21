"""Generate a multi-size Voicely icon.ico next to this file (for the exe + installer).

Draws the same waveform-dot mascot as the macOS app icon: dark navy rounded square
background, glacier-cyan waveform bars, white dot head.
"""
import os
from PIL import Image, ImageDraw


NAVY  = (14, 26, 50, 255)    # dark background
CYAN  = (34, 211, 238, 255)  # glacier live / accent
WHITE = (240, 248, 255, 255)


def voicely_icon(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # Rounded-square background
    r = round(size * 0.22)
    d.rounded_rectangle([(0, 0), (size - 1, size - 1)], radius=r, fill=NAVY)

    s = size
    cx = s // 2

    # Head dot
    hd = round(s * 0.12)
    hy = round(s * 0.18)
    d.ellipse([(cx - hd, hy), (cx + hd, hy + hd * 2)], fill=WHITE)

    # Waveform bars (5 bars, centre is tallest)
    bar_w   = max(2, round(s * 0.07))
    heights = [0.14, 0.22, 0.30, 0.22, 0.14]
    offsets = [-4, -2, 0, 2, 4]
    base_y  = round(s * 0.82)

    for h_frac, off in zip(heights, offsets):
        bh  = round(s * h_frac)
        bx  = cx + round(off * s * 0.10) - bar_w // 2
        top = base_y - bh
        d.rounded_rectangle([(bx, top), (bx + bar_w, base_y)],
                             radius=bar_w // 2, fill=CYAN)

    return img


out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "icon.ico")
voicely_icon(256).save(
    out, format="ICO",
    sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
)
print("wrote", out)
