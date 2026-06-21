"""Generate a multi-size heart icon.ico next to this file (for the exe + installer)."""
import os
from PIL import Image, ImageDraw


def heart(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s = size
    c = (34, 211, 238, 255)  # icy cyan
    d.ellipse((0.16 * s, 0.18 * s, 0.52 * s, 0.54 * s), fill=c)
    d.ellipse((0.48 * s, 0.18 * s, 0.84 * s, 0.54 * s), fill=c)
    d.polygon([(0.18 * s, 0.42 * s), (0.82 * s, 0.42 * s), (0.50 * s, 0.84 * s)], fill=c)
    return img


out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "icon.ico")
heart(256).save(out, format="ICO",
                sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
print("wrote", out)
