#!/usr/bin/env python3
"""生成 macOS 风格圆角信号灯图标（抗锯齿）。"""
from __future__ import annotations

import math
import struct
import subprocess
import sys
import zlib
from pathlib import Path


def png_chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


def _rounded_rect_coverage(x: float, y: float, rx: float, ry: float, rw: float, rh: float, cr: float) -> float:
    """返回 (x, y) 在圆角矩形内的覆盖率 (0.0–1.0)，支持抗锯齿。"""
    if x < rx - 0.5 or x > rx + rw + 0.5 or y < ry - 0.5 or y > ry + rh + 0.5:
        return 0.0

    # 确定所属的角区域
    corner_dist = -1.0  # -1 表示不在任何角区域
    if x < rx + cr and y < ry + cr:
        corner_dist = math.hypot(x - (rx + cr), y - (ry + cr))
    elif x > rx + rw - cr and y < ry + cr:
        corner_dist = math.hypot(x - (rx + rw - cr), y - (ry + cr))
    elif x < rx + cr and y > ry + rh - cr:
        corner_dist = math.hypot(x - (rx + cr), y - (ry + rh - cr))
    elif x > rx + rw - cr and y > ry + rh - cr:
        corner_dist = math.hypot(x - (rx + rw - cr), y - (ry + rh - cr))
    elif x < rx or x > rx + rw or y < ry or y > ry + rh:
        return 0.0  # 矩形主体外

    if corner_dist >= 0:
        inner = cr - 0.5
        outer = cr + 0.5
        if corner_dist >= outer:
            return 0.0  # 圆角外侧
        if corner_dist >= inner:
            return (outer - corner_dist) / (outer - inner)  # 圆角边缘抗锯齿
        # 圆角内侧，落入主体，继续边缘抗锯齿

    left = _edge_alpha(x, rx)
    right = _edge_alpha(rx + rw - x, 0.0)
    top = _edge_alpha(y, ry)
    bottom = _edge_alpha(ry + rh - y, 0.0)
    return min(left, right, top, bottom)


def _edge_alpha(coord: float, edge: float) -> float:
    """单边抗锯齿：coord 为像素中心到边的距离。"""
    dist = coord - edge
    if dist >= 0.5:
        return 1.0
    if dist <= -0.5:
        return 0.0
    return (dist + 0.5) / 1.0  # (-0.5, 0.5) → (0, 1)


def _circle_coverage(x: float, y: float, cx: float, cy: float, radius: float) -> float:
    """返回 (x, y) 在圆形内的覆盖率。"""
    dist = math.hypot(x - cx, y - cy)
    inner = radius - 0.5
    outer = radius + 0.5
    if dist <= inner:
        return 1.0
    if dist >= outer:
        return 0.0
    return (outer - dist) / (outer - inner)


def _glow_coverage(x: float, y: float, cx: float, cy: float, radius: float) -> float:
    """返回 (x, y) 在圆形光晕内的覆盖率，从中心到边缘线性衰减。"""
    dist = math.hypot(x - cx, y - cy)
    inner = radius * 0.3  # 内部完全不透明
    if dist <= inner:
        return 1.0
    if dist >= radius:
        return 0.0
    smooth = (radius - dist) / (radius - inner)
    return smooth * smooth  # 二次衰减更自然


def write_png(path: Path, size: int) -> None:
    # 背景圆角矩形参数
    padding = size * 0.10
    bg_x = padding
    bg_y = padding
    bg_w = size - padding * 2
    bg_h = size - padding * 2
    corner_radius = bg_w * 0.20

    # 信号灯参数
    lamp_radius = bg_w * 0.08
    glow_radius = bg_w * 0.16
    lamp_spacing = bg_h * 0.22
    cx = size / 2.0
    lamp_center_y_base = size / 2.0 - lamp_spacing

    lamp_colors = [
        (48, 255, 88),   # 绿灯
        (255, 214, 72),  # 黄灯
        (255, 69, 58),   # 红灯
    ]

    rows = []
    for y in range(size):
        row = bytearray()
        py = y + 0.5  # 像素中心坐标，用于抗锯齿计算
        for x in range(size):
            px = x + 0.5

            # 背景覆盖率
            bg_alpha = _rounded_rect_coverage(px, py, bg_x, bg_y, bg_w, bg_h, corner_radius)

            if bg_alpha > 0:
                ny = (py - bg_y) / bg_h
                shade = int(20 + 14 * ny)
                red = float(shade)
                green = float(shade)
                blue = float(shade)
                alpha = bg_alpha
            else:
                red = green = blue = 0.0
                alpha = 0.0

            # 绘制信号灯（带抗锯齿）
            for i, color in enumerate(lamp_colors):
                ly = lamp_center_y_base + i * lamp_spacing

                # 光晕
                glow = _glow_coverage(px, py, cx, ly, glow_radius)
                if glow > 0:
                    glow_alpha = glow * 0.30
                    # alpha 混合
                    inv = glow_alpha * (1.0 - alpha)
                    red += color[0] * inv
                    green += color[1] * inv
                    blue += color[2] * inv
                    alpha = alpha + glow_alpha * (1.0 - alpha)

                # 灯芯
                lamp = _circle_coverage(px, py, cx, ly, lamp_radius)
                if lamp > 0:
                    lamp_alpha = lamp
                    inv = lamp_alpha * (1.0 - alpha)
                    red = red * (1.0 - lamp_alpha) + color[0] * lamp_alpha
                    green = green * (1.0 - lamp_alpha) + color[1] * lamp_alpha
                    blue = blue * (1.0 - lamp_alpha) + color[2] * lamp_alpha
                    alpha = alpha + lamp_alpha * (1.0 - alpha)

            # clamp
            r = max(0, min(255, int(round(red))))
            g = max(0, min(255, int(round(green))))
            b = max(0, min(255, int(round(blue))))
            a = max(0, min(255, int(round(alpha * 255))))

            row.extend((r, g, b, a))
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
