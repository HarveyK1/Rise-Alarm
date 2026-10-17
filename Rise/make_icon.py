"""Draws Rise's app icon (a sunrise) as Icon.png, 1024x1024, with no dependencies.

Run:  python make_icon.py   (then rebuild; xtool.yml points iconPath at Icon.png)
"""
import math
import struct
import zlib

SIZE = 1024
HORIZON = 660
SUN_X, SUN_R = 512, 250


def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(x + (y - x) * t for x, y in zip(a, b))


SKY = [(0.0, (11, 16, 48)), (0.55, (70, 32, 92)), (1.0, (255, 122, 47))]   # navy -> purple -> orange
SUN_TOP, SUN_BOTTOM = (255, 228, 122), (255, 150, 28)
GLOW = (255, 170, 70)
GROUND_TOP, GROUND_BOTTOM = (26, 14, 30), (8, 8, 16)
# Reflection stripes under the horizon: (y, half-length, thickness)
STRIPES = [(690, 210, 10), (726, 170, 8), (764, 128, 7), (806, 88, 6), (852, 52, 5)]


def sky(y):
    t = y / HORIZON
    for (t0, c0), (t1, c1) in zip(SKY, SKY[1:]):
        if t <= t1:
            return mix(c0, c1, (t - t0) / (t1 - t0))
    return SKY[-1][1]


def pixel(x, y):
    if y < HORIZON:
        color = sky(y)
        d = math.hypot(x - SUN_X, y - HORIZON)
        glow = max(0.0, 1 - (d - SUN_R) / 140) ** 2 * 0.5 if d > SUN_R else 0.0
        color = mix(color, GLOW, glow)
        cover = max(0.0, min(1.0, SUN_R + 0.5 - d))   # anti-aliased sun edge
        if cover:
            color = mix(color, mix(SUN_TOP, SUN_BOTTOM, (y - (HORIZON - SUN_R)) / SUN_R), cover)
        return color
    color = mix(GROUND_TOP, GROUND_BOTTOM, (y - HORIZON) / (SIZE - HORIZON))
    for sy, half, thick in STRIPES:
        if sy <= y < sy + thick:
            edge = max(0.0, min(1.0, half + 0.5 - abs(x - SUN_X)))
            color = mix(color, SUN_BOTTOM, edge * 0.85)
    return color


def write_png(path, rows):
    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    raw = b"".join(b"\x00" + bytes(row) for row in rows)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))   # 8-bit RGB, no alpha
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


if __name__ == "__main__":
    rows = []
    for y in range(SIZE):
        row = []
        for x in range(SIZE):
            row.extend(int(round(c)) for c in pixel(x, y))
        rows.append(row)
    write_png("Icon.png", rows)
    assert open("Icon.png", "rb").read(8) == b"\x89PNG\r\n\x1a\n"
    print("wrote Icon.png")
