"""心情手记（原 DateLog）应用图标生成脚本。

设计规格
--------
- 背景层 background.png：暖黄奶咖调斜向渐变（#F7CE8A -> #E09A32）+ 左上柔光，
  完全不透明，**不烤圆角**（圆角由系统遮罩决定）。
- 前景层 foreground.png：透明底 + 纯白「便签 + 笑脸」。
  便签 = 记录，笑脸 = 心情；便签右上角做折角（纸张/日记联想）。
  便签宽度占画布 55%，落在系统遮罩的安全区内，便签以外 alpha 必须为 0。
- 启动图标 startIcon.png：同款渐变 + 便签笑脸，自行烤 squircle 圆角。
- 预览图 icon_preview.png：合成并加圆角与投影，模拟桌面观感（不随包发布）。

用法
----
    python tools/generate_icon.py

改配色 / 便签占比 / 圆角，只需改下面「设计常量」。
"""

import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

# ---------------------------- 设计常量 ----------------------------
BRAND_LIGHT = (0xF7, 0xCE, 0x8A)      # #F7CE8A 渐变起点（左上，暖黄奶咖）
BRAND_DEEP = (0xE0, 0x9A, 0x32)       # #E09A32 渐变终点（右下，焦糖金）
GLOW_ALPHA = 0.16                     # 左上柔光强度 0~1
GLOW_CENTER = (0.30, 0.26)            # 柔光圆心（相对画布比例）
GLOW_RADIUS = 0.72                    # 柔光半径（相对画布宽度）

# --- 便签（前景图形主体）---
NOTE_COLOR = (0xFF, 0xFF, 0xFF)       # 纯白便签纸
NOTE_WIDTH_RATIO = 0.55               # 便签宽度占画布比例（要求 0.52~0.58）
NOTE_HEIGHT_RATIO = 0.63              # 便签高度占画布比例（略大于宽度）
NOTE_CENTER_X = 0.498                 # 便签横向中心（考虑折角后略左移做视觉居中）
NOTE_CENTER_Y = 0.497                 # 便签纵向中心（略高于几何中心做视觉居中）
NOTE_RADIUS_RATIO = 0.105             # 便签圆角半径（相对便签宽度）

# --- 右上角折角（纸张/日记联想）---
FOLD_RATIO = 0.235                    # 折角边长（相对便签宽度）
FOLD_FLAP_COLOR = (0xEC, 0xDF, 0xC9)  # 翻起的纸背（浅米色，与纯白便签拉开对比）
FOLD_EDGE_COLOR = (0xB8, 0x9A, 0x70)  # 折边深色描边（小尺寸下保住折角辨识度）
FOLD_EDGE_RATIO = 0.032               # 折边描边宽度（相对便签宽度）

# --- 笑脸（心情）---
FACE_COLOR = (0x4A, 0x33, 0x1C)       # 暖调深咖（眼睛与微笑）
EYE_DX_RATIO = 0.155                  # 眼睛横向偏移（相对便签宽度）
EYE_CY_RATIO = 0.405                  # 眼睛纵向位置（相对便签高度）
EYE_R_RATIO = 0.062                   # 眼睛半径（相对便签宽度）
SMILE_R_RATIO = 0.325                 # 微笑圆弧半径（相对便签宽度）
SMILE_CY_RATIO = 0.445                # 微笑圆弧圆心纵向位置（相对便签高度）
SMILE_WIDTH_RATIO = 0.075             # 微笑线条宽度（相对便签宽度）
SMILE_FLAT = 0.18                     # 圆弧只取圆心以下这一段（0~1，越小笑得越开）
SMILE_TUCK = 0.30                     # 微笑两端上收比例 0~0.5（越大嘴角越翘）

SUPERSAMPLE = 4                       # 超采样倍数（抗锯齿）

ICON_SIZE = 1024                      # 分层图标边长
START_ICON_SIZE = 152                 # 启动图标边长
ROUND_RADIUS_RATIO = 0.22             # squircle 圆角比例（启动图标与预览图）
PREVIEW_ICON_RATIO = 0.82             # 预览图里图标的占比
PREVIEW_BACKDROP = (0xF2, 0xF2, 0xF7)  # 预览图背景（模拟浅色桌面）

# ---------------------------- 路径 ----------------------------
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MEDIA_DIRS = [
    os.path.join(ROOT, 'AppScope', 'resources', 'base', 'media'),
    os.path.join(ROOT, 'entry', 'src', 'main', 'resources', 'base', 'media'),
]
START_ICON_PATH = os.path.join(MEDIA_DIRS[1], 'startIcon.png')
PREVIEW_PATH = os.path.join(ROOT, 'icon_preview.png')

# 应用商店（AGC）用：AGC 的图标位要求上传「直角图标」并自行叠加 Mask 蒙层，
# 所以这里不烤圆角，输出不透明的正方形图标。
STORE_ICON_DIR = os.path.join(ROOT, 'docs', 'store')
STORE_ICON_SIZES = [1024, 216]


def make_background(size):
    """暖黄奶咖斜向渐变 + 左上柔光；完全不透明，不烤圆角。"""
    xs, ys = np.meshgrid(
        np.arange(size, dtype=np.float32),
        np.arange(size, dtype=np.float32),
    )
    # 135 度斜向：左上 -> 右下
    t = (xs / (size - 1) + ys / (size - 1)) / 2.0

    rgb = np.zeros((size, size, 3), dtype=np.float32)
    for c in range(3):
        rgb[..., c] = BRAND_LIGHT[c] + (BRAND_DEEP[c] - BRAND_LIGHT[c]) * t

    # 左上柔光：让渐变有层次而不显脏
    cx = GLOW_CENTER[0] * size
    cy = GLOW_CENTER[1] * size
    radius = GLOW_RADIUS * size
    dist = np.sqrt((xs - cx) ** 2 + (ys - cy) ** 2)
    glow = (np.clip(1.0 - dist / radius, 0.0, 1.0) ** 2) * GLOW_ALPHA
    rgb = rgb + (255.0 - rgb) * glow[..., None]

    alpha = np.full((size, size, 1), 255, dtype=np.uint8)
    arr = np.clip(rgb, 0, 255).astype(np.uint8)
    return Image.fromarray(np.concatenate([arr, alpha], axis=2), 'RGBA')


# ---------------------------- 图形工具 ----------------------------

def make_foreground(size):
    """透明底 + 纯白「便签 + 笑脸」；4 倍超采样抗锯齿。

    便签 = 记录，笑脸 = 心情：白色圆角便签居中偏上，右上角折角，
    中央一张深咖色笑脸（两个圆点眼睛 + 一条弧形微笑）。
    """
    big = size * SUPERSAMPLE
    # 全部几何量都在「放大后的画布像素坐标」里计算，避免单位混用
    note_w = big * NOTE_WIDTH_RATIO
    note_h = big * NOTE_HEIGHT_RATIO
    radius = note_w * NOTE_RADIUS_RATIO
    fold = note_w * FOLD_RATIO

    left = big * NOTE_CENTER_X - note_w / 2.0
    top = big * NOTE_CENTER_Y - note_h / 2.0

    yy, xx = np.mgrid[0:big, 0:big]
    x = xx + 0.5
    y = yy + 0.5

    # 1) 便签纸本体：圆角矩形（局部坐标），再沿对角线裁掉右上角
    lx = x - left
    ly = y - top
    rx = np.clip(lx, radius, note_w - radius)
    ry = np.clip(ly, radius, note_h - radius)
    inscribed = (lx >= 0) & (lx <= note_w) & (ly >= 0) & (ly <= note_h)
    rounded = ((lx - rx) ** 2 + (ly - ry) ** 2) <= radius * radius
    cut = (lx + ly) >= (note_w + note_h - fold)
    note_mask = inscribed & rounded & (~cut)

    # 2) 折角翻起的纸背：直角三角形，直角在便签右上角，
    #    两直角边各长 fold，斜边正好贴在被裁掉的那条对角线上。
    flap = (lx >= note_w - fold) & (lx <= note_w) & (ly >= 0) & (ly <= fold)

    # 3) 折边描边：贴着对角折线的一条细带（比纸背深，小尺寸下也看得见）
    #    d 为到折线的带符号距离（折线过 (note_w-fold, 0) 与 (note_w, fold)，
    #    法线为 (1,1)，故实际线宽 = edge）
    edge = note_w * FOLD_EDGE_RATIO
    d = ly - (lx - (note_w - fold))
    edge_band = flap & (np.abs(d) <= math.sqrt(2.0) * edge / 2.0)

    # 4) 笑脸：两个实心圆点眼睛 + 一条弧形微笑（深咖色）
    eye_r = note_w * EYE_R_RATIO
    eye_dx = note_w * EYE_DX_RATIO
    eye_cy = note_h * EYE_CY_RATIO
    note_cx = note_w / 2.0
    eyes = (((lx - (note_cx - eye_dx)) ** 2 + (ly - eye_cy) ** 2) <= eye_r * eye_r) | \
           (((lx - (note_cx + eye_dx)) ** 2 + (ly - eye_cy) ** 2) <= eye_r * eye_r)

    # 微笑：圆形下弧，用「圆环 ∩ 圆心以下部分」得到一条有宽度的弧线
    smile_r = note_w * SMILE_R_RATIO
    smile_w = note_w * SMILE_WIDTH_RATIO
    smile_cy = note_h * SMILE_CY_RATIO          # 相对便签顶部
    dxs = lx - note_cx
    dys = ly - smile_cy
    rr = np.sqrt(dxs * dxs + dys * dys)
    smile_ring = (rr <= smile_r + smile_w / 2.0) & (rr >= smile_r - smile_w / 2.0)
    # 只保留圆心以下（按 SMILE_FLAT 控制张角）的那一段
    y_base = smile_r * SMILE_FLAT
    smile = smile_ring & (dys >= y_base) & (ly >= smile_cy)
    if SMILE_TUCK > 0:
        # 两端上收：靠外侧的一段嘴角抬起来，避免笑成一条平线
        limit = smile_r * (1.0 - SMILE_TUCK)
        over = np.clip((np.abs(dxs) - limit) / (smile_r * SMILE_TUCK), 0.0, 1.0)
        smile = smile & (dys >= y_base + (over ** 1.5) * (smile_r * 0.35))

    # --- 合成：白色便签 -> 折角纸背 -> 折边 -> 笑脸 ---
    rgb = np.zeros((big, big, 3), dtype=np.float32)
    rgb[note_mask] = NOTE_COLOR
    rgb[flap] = FOLD_FLAP_COLOR
    rgb[edge_band] = FOLD_EDGE_COLOR
    face = (eyes | smile) & note_mask
    rgb[face] = FACE_COLOR

    alpha = (note_mask | flap).astype(np.uint8) * 255
    fg = Image.fromarray(np.concatenate([np.clip(rgb, 0, 255).astype(np.uint8), alpha[..., None]],
                                        axis=2), 'RGBA')
    return fg.resize((size, size), Image.LANCZOS)


def rounded_mask(size, radius_ratio):
    """squircle 遮罩（仅在启动图标/预览图上使用）。"""
    big = size * 4
    mask = Image.new('L', (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, big - 1, big - 1], radius=int(big * radius_ratio), fill=255)
    return mask.resize((size, size), Image.LANCZOS)


def make_start_icon(size):
    """启动图标：渐变 + 便签笑脸 + 自烤圆角。"""
    icon = Image.alpha_composite(make_background(size), make_foreground(size))
    icon.putalpha(rounded_mask(size, ROUND_RADIUS_RATIO))
    return icon


def make_store_icon(size):
    """应用商店用直角图标：渐变 + 便签笑脸，方形、不烤圆角、完全不透明。"""
    return Image.alpha_composite(make_background(size), make_foreground(size))


def make_preview(size):
    """预览图：浅色底 + 带投影的圆角图标，模拟桌面观感。"""
    inner = int(size * PREVIEW_ICON_RATIO)
    offset = (size - inner) // 2
    icon = make_start_icon(inner)

    shadow = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    shadow_mask = Image.new('L', (size, size), 0)
    shadow_mask.paste(rounded_mask(inner, ROUND_RADIUS_RATIO),
                      (offset, offset + int(size * 0.014)))
    shadow_mask = shadow_mask.filter(ImageFilter.GaussianBlur(size * 0.018))
    shadow.putalpha(shadow_mask.point(lambda v: int(v * 0.30)))

    canvas = Image.new('RGBA', (size, size), PREVIEW_BACKDROP + (255,))
    canvas = Image.alpha_composite(canvas, shadow)
    canvas.paste(icon, (offset, offset), icon)
    return canvas


def corners(img):
    """四角像素，用于断言 alpha 是否符合分层图标要求。"""
    w, h = img.size
    return [img.getpixel(p)[3] for p in
            [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]]


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, 'PNG', optimize=True)
    print('  wrote %-58s %s  %6.1f KB'
          % (os.path.relpath(path, ROOT), img.size, os.path.getsize(path) / 1024.0))


def main():
    print('生成分层图标背景层 ...')
    background = make_background(ICON_SIZE)

    print('生成分层图标前景层 ...')
    foreground = make_foreground(ICON_SIZE)

    # --- 断言：分层图标的两层语义必须正确 ---
    bg_corners = corners(background)
    assert all(a == 255 for a in bg_corners), '背景层必须完全不透明，实测四角 alpha=%s' % bg_corners
    fg_corners = corners(foreground)
    assert all(a == 0 for a in fg_corners), '前景层四角必须透明，实测 alpha=%s' % fg_corners
    assert foreground.getpixel((ICON_SIZE // 2, int(ICON_SIZE * 0.42)))[3] == 255, \
        '前景层便签区域应有内容'
    assert foreground.getpixel((int(ICON_SIZE * 0.80), int(ICON_SIZE * 0.22)))[3] == 0, \
        '前景层便签右上折角外侧必须透明'
    print('  alpha 断言通过：背景四角=255，前景四角=0，便签有内容，折角外侧透明')

    print('写出资源文件 ...')
    for media_dir in MEDIA_DIRS:
        save(background, os.path.join(media_dir, 'background.png'))
        save(foreground, os.path.join(media_dir, 'foreground.png'))

    start_icon = make_start_icon(START_ICON_SIZE)
    assert start_icon.getpixel((0, 0))[3] == 0, '启动图标圆角外应透明'
    save(start_icon, START_ICON_PATH)

    print('生成商店用直角图标 ...')
    for size in STORE_ICON_SIZES:
        store_icon = make_store_icon(size)
        assert all(a == 255 for a in corners(store_icon)), '商店图标必须完全不透明'
        save(store_icon, os.path.join(STORE_ICON_DIR, 'app-icon-square-%d.png' % size))

    print('生成预览图 ...')
    save(make_preview(ICON_SIZE), PREVIEW_PATH)

    print('完成。')


if __name__ == '__main__':
    main()
