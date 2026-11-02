"""Draws the KlaseKo brand images (app icon, adaptive icon layers, splash) into assets/branding/.

The mark: a navy rounded square holding a white answer bubble with a navy check, and a gold
shaded bubble at the upper right. Drawn at 4x and scaled down for smooth edges.

Run from the project folder:  python tool/make_brand_assets.py
"""
from pathlib import Path

from PIL import Image, ImageDraw

NAVY = (23, 62, 117)
NAVY_DEEP = (15, 45, 87)
GOLD = (216, 181, 103)
WHITE = (255, 255, 255)
SS = 4  # supersampling

OUT = Path(__file__).resolve().parent.parent / "assets" / "branding"


def _gradient_square(size, radius):
    """Navy rounded square with a gentle diagonal gradient."""
    grad = Image.new("RGB", (size, size))
    px = grad.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            px[x, y] = tuple(round(a + (b - a) * t) for a, b in zip(NAVY, NAVY_DEEP))
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(grad, (0, 0), mask)
    return out


def _draw_symbol(img, cx, cy, scale):
    """Bubble, check and gold dot centred on (cx, cy); scale 1.0 = the 1024 px icon layout."""
    d = ImageDraw.Draw(img)
    s = scale
    # white answer bubble
    r = 262 * s
    bx, by = cx - 40 * s, cy + 30 * s
    d.ellipse([bx - r, by - r, bx + r, by + r], fill=WHITE)
    # navy check mark with rounded ends
    w = int(66 * s)
    pts = [(bx - 120 * s, by + 4 * s), (bx - 28 * s, by + 98 * s), (bx + 138 * s, by - 112 * s)]
    d.line(pts, fill=NAVY_DEEP, width=w, joint="curve")
    for x, y in (pts[0], pts[2]):
        d.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill=NAVY_DEEP)
    # gold shaded bubble
    gr = 104 * s
    gx, gy = cx + 236 * s, cy - 236 * s
    d.ellipse([gx - gr, gy - gr, gx + gr, gy + gr], fill=GOLD)


def _finish(img, size):
    return img.resize((size, size), Image.LANCZOS)


def app_icon(size=1024):
    big = size * SS
    img = _gradient_square(big, radius=int(big * 0.225))
    _draw_symbol(img, big / 2, big / 2, big / 1024)
    return _finish(img, size)


def adaptive_foreground(size=1024):
    """Transparent layer for Android adaptive icons; the symbol stays inside the 66% safe zone."""
    big = size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    _draw_symbol(img, big / 2, big / 2, big / 1024 * 0.62)
    return _finish(img, size)


def splash(size, symbol_scale):
    big = size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    _draw_symbol(img, big / 2, big / 2, big / 1024 * symbol_scale)
    return _finish(img, size)


def monochrome(size=1024):
    """Single-colour layer for Android 13 themed icons."""
    fg = adaptive_foreground(size)
    alpha = fg.split()[3]
    out = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    out.putalpha(alpha)
    return out


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    app_icon().save(OUT / "app_icon.png")
    adaptive_foreground().save(OUT / "app_icon_foreground.png")
    monochrome().save(OUT / "app_icon_monochrome.png")
    splash(1152, 0.62).save(OUT / "splash_android12.png")  # Android 12+: symbol inside the 768 px circle
    splash(768, 0.9).save(OUT / "splash.png")
    print("Wrote brand images to", OUT)
