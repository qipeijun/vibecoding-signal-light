#!/usr/bin/env python3
from __future__ import annotations

import struct
import subprocess
import sys
import zlib
from pathlib import Path


def png_chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


def write_png(path: Path, size: int) -> None:
    rows = []
    for y in range(size):
        row = bytearray()
        for x in range(size):
            nx = (x + 0.5) / size
            ny = (y + 0.5) / size
            alpha = 0
            red = green = blue = 0

            # Rounded black glass tile.
            inset = size * 0.14
            radius = size * 0.22
            bx = min(max(x, inset), size - inset)
            by = min(max(y, inset), size - inset)
            if (x - bx) ** 2 + (y - by) ** 2 <= radius ** 2:
                alpha = 255
                shade = int(12 + 18 * (1 - ny))
                red = green = blue = shade

            # Three pure signal lights.
            centers = [
                (0.50, 0.32, (48, 255, 88)),
                (0.50, 0.50, (255, 214, 72)),
                (0.50, 0.68, (255, 69, 58)),
            ]
            for cx, cy, color in centers:
                dist = ((nx - cx) ** 2 + (ny - cy) ** 2) ** 0.5
                lamp_radius = 0.075
                glow_radius = 0.13
                if dist < glow_radius:
                    glow = max(0.0, 1.0 - dist / glow_radius)
                    alpha = max(alpha, int(80 * glow))
                    red = max(red, int(color[0] * glow * 0.75))
                    green = max(green, int(color[1] * glow * 0.75))
                    blue = max(blue, int(color[2] * glow * 0.75))
                if dist < lamp_radius:
                    alpha = 255
                    red, green, blue = color

            row.extend((red, green, blue, alpha))
        rows.append(b"\x00" + bytes(row))

    raw = b"".join(rows)
    data = (
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
        + png_chunk(b"IDAT", zlib.compress(raw, 9))
        + png_chunk(b"IEND", b"")
    )
    path.write_bytes(data)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: make-app-icon.py <iconset-dir>", file=sys.stderr)
        return 2

    iconset = Path(sys.argv[1])
    iconset.mkdir(parents=True, exist_ok=True)
    sizes = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }
    for filename, size in sizes.items():
        write_png(iconset / filename, size)

    icns_path = iconset.with_suffix(".icns")
    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(icns_path)], check=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
