#!/usr/bin/env python3
"""Erzeugt das MusicDesk-App-Icon (Resources/AppIcon.icns + Resources/AppIcon.png).

Zeichnet eine weiße Achtelnote auf einem abgerundeten Quadrat mit Farbverlauf
(tiefes Rot -> Pink). Benötigt nur Pillow, keine Schriftarten.

Aufruf: python3 scripts/make_icon.py
"""
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "Resources"
SIZE = 1024
SS = 4  # Supersampling-Faktor für glatte Kanten

TOP = (255, 94, 128)    # Pink
BOTTOM = (176, 18, 52)  # tiefes Rot


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def gradient(size):
    col = Image.new("RGB", (1, size))
    for y in range(size):
        col.putpixel((0, y), lerp(TOP, BOTTOM, y / (size - 1)))
    return col.resize((size, size), Image.NEAREST)


def rounded_mask(size, margin, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle(
        (margin, margin, size - margin - 1, size - margin - 1), radius=radius, fill=255
    )
    return m


def note_mask(size):
    """Achtelnote (♪) aus Ellipse, Hals und geschwungenem Fähnchen."""
    s = size / 1024.0
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)

    # Notenkopf: schräge Ellipse
    head = Image.new("L", (size, size), 0)
    hd = ImageDraw.Draw(head)
    cx, cy, rx, ry = 430 * s, 700 * s, 120 * s, 88 * s
    hd.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=255)
    head = head.rotate(22, center=(cx, cy), resample=Image.BICUBIC)
    m = ImageChops.lighter(m, head)
    d = ImageDraw.Draw(m)

    # Hals
    stem_x1 = cx + rx * 0.84
    stem_w = 44 * s
    stem_top = 250 * s
    d.rectangle((stem_x1 - stem_w, stem_top, stem_x1, cy), fill=255)

    # Fähnchen: gefüllter Bogen zwischen zwei Kurven
    pts_outer, pts_inner = [], []
    steps = 60
    for i in range(steps + 1):
        t = i / steps
        # äußere Kurve
        x = stem_x1 + (200 * s) * (t ** 0.9) - (40 * s) * (t ** 3)
        y = stem_top + (330 * s) * t
        x += (60 * s) * (4 * t * (1 - t))
        pts_outer.append((x, y))
        # innere Kurve
        xi = stem_x1 + (150 * s) * (t ** 1.1) - (30 * s) * (t ** 3)
        yi = stem_top + (110 * s) + (230 * s) * t
        pts_inner.append((xi, yi))
    poly = [(stem_x1 - stem_w * 0.5, stem_top)] + pts_outer + list(reversed(pts_inner)) + [
        (stem_x1 - stem_w * 0.5, stem_top + 110 * s)
    ]
    d.polygon(poly, fill=255)
    return m


def render():
    big = SIZE * SS
    margin = int(100 / 1024 * big)       # macOS-Icon-Raster: ~824px Inhalt
    radius = int(185 / 1024 * big)
    base = Image.new("RGBA", (big, big), (0, 0, 0, 0))

    # weicher Schatten
    shadow = rounded_mask(big, margin, radius).filter(ImageFilter.GaussianBlur(12 * SS))
    shadow_layer = Image.new("RGBA", (big, big), (0, 0, 0, 90))
    shadow_off = Image.new("L", (big, big), 0)
    shadow_off.paste(shadow, (0, 10 * SS))
    base.paste(shadow_layer, (0, 0), shadow_off)

    tile = gradient(big).convert("RGBA")
    base.paste(tile, (0, 0), rounded_mask(big, margin, radius))

    # Note innerhalb des Tiles skalieren
    inner = big - 2 * margin
    nm = note_mask(inner)
    note = Image.new("L", (big, big), 0)
    note.paste(nm, (margin + int(inner * 0.02), margin))
    white = Image.new("RGBA", (big, big), (255, 255, 255, 255))
    base.paste(white, (0, 0), note)

    return base.resize((SIZE, SIZE), Image.LANCZOS)


def main():
    RES.mkdir(parents=True, exist_ok=True)
    img = render()
    png = RES / "AppIcon.png"
    icns = RES / "AppIcon.icns"
    img.save(png)
    sizes = [(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)]
    img.save(icns, format="ICNS", sizes=sizes)
    print(f"Icon geschrieben: {png}")
    print(f"Icon geschrieben: {icns}")


if __name__ == "__main__":
    main()
