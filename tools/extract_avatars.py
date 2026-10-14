"""从用户提供的 4x4 头像网格图中提取指定头像。

源图：avatars-to-import/grid-source.jpg（1317x1279，4 列 x 4 行，第 2 行第 3 格为空）

思路
----
源图的圆形底色与外层背景都极淡（色差常常只有个位数），所以不能用一个全局阈值直接抠圆。
分两步：
  1. **切网格**：用较高阈值（8）得到"确定是内容"的掩码，做列/行投影，各找 4 个连通带
  2. **精测圆**：在每个格子内、用较低阈值（4）的掩码，在过圆心的横/竖扫描线上取
     多个采样行的中位数范围 → 得到真实直径（避免"内容并集"把圆撑大）
  3. 按直径裁正方形 → 256x256 → 套抗锯齿圆形 alpha 蒙版

输出
----
  docs/store/grid-index.png                       带 R#C# 编号的索引图（人工核对用）
  entry/.../media/avatar_{m1,m2,m3,f1,f2,f3}.png  6 张 App 资源
  docs/store/avatars/                             同批副本
  docs/store/avatars-overview.png                 3x2 总览
"""
import os

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'avatars-to-import', 'grid-source.jpg')
MEDIA_DIR = os.path.join(ROOT, 'entry', 'src', 'main', 'resources', 'base', 'media')
STORE_DIR = os.path.join(ROOT, 'docs', 'store', 'avatars')
INDEX_IMG = os.path.join(ROOT, 'docs', 'store', 'grid-index.png')
OVERVIEW = os.path.join(ROOT, 'docs', 'store', 'avatars-overview.png')

SIZE = 256
BAND_THRESHOLD = 8     # 切网格用的高阈值
FINE_THRESHOLD = 4     # 精测圆直径用的低阈值
MIN_GAP = 14           # 合并投影带时的最大间隙
FLOOR = 3              # 投影判定为"有内容"的最小像素数
MIN_AREA = 800         # 小于此面积判为空格
EXPAND = 0.02          # 直径外扩比例，避免裁掉圆形边缘
SAMPLE = 8             # 眉线采样半宽（取中位数抗噪）

# 选定：新 id -> (行, 列)，行列均从 1 开始
PICKS = [
    ('m1', 1, 1),   # 深棕短发 · 浅蓝灰领
    ('m2', 1, 3),   # 棕发右侧分 · 灰绿领
    ('m3', 3, 2),   # 棕发 · 驼色领
    ('f1', 2, 4),   # 中分长直发 · 粉领
    ('f2', 3, 1),   # 马尾
    ('f3', 4, 1),   # 丸子头
]
BACKGROUND = (0xFD, 0xF8, 0xF0)


def erode(mask):
    r = mask.copy()
    r[1:, :] &= mask[:-1, :]
    r[:-1, :] &= mask[1:, :]
    r[:, 1:] &= mask[:, :-1]
    r[:, :-1] &= mask[:, 1:]
    return r


def dilate(mask):
    r = mask.copy()
    r[1:, :] |= mask[:-1, :]
    r[:-1, :] |= mask[1:, :]
    r[:, 1:] |= mask[:, :-1]
    r[:, :-1] |= mask[:, 1:]
    return r


def find_bands(proj, count):
    """把一维投影切成 count 个连通带，返回 [(start, end), ...]（按位置升序）"""
    idx = np.where(proj >= FLOOR)[0]
    if idx.size == 0:
        return []
    groups = []
    start = int(idx[0])
    prev = int(idx[0])
    for raw in idx[1:]:
        i = int(raw)
        if i - prev > MIN_GAP:
            groups.append((start, prev))
            start = i
        prev = i
    groups.append((start, prev))
    if len(groups) > count:
        groups.sort(key=lambda g: -float(proj[g[0]:g[1] + 1].sum()))
        groups = sorted(groups[:count])
    return groups


def measure_circle(fine, band_r, band_c):
    """在格子内精测圆：取过圆心的横/竖扫描线，多条采样取中位数范围"""
    r0, r1 = band_r
    c0, c1 = band_c
    cy = (r0 + r1) // 2
    cx = (c0 + c1) // 2

    lefts, rights = [], []
    for y in range(max(0, cy - SAMPLE), min(fine.shape[0], cy + SAMPLE + 1)):
        xs = np.where(fine[y, c0:c1 + 1])[0]
        if xs.size > 0:
            lefts.append(int(xs.min()))
            rights.append(int(xs.max()))

    tops, bottoms = [], []
    for x in range(max(0, cx - SAMPLE), min(fine.shape[1], cx + SAMPLE + 1)):
        ys = np.where(fine[r0:r1 + 1, x])[0]
        if ys.size > 0:
            tops.append(int(ys.min()))
            bottoms.append(int(ys.max()))

    if not lefts or not tops:
        return None
    x0 = c0 + int(np.median(lefts))
    x1 = c0 + int(np.median(rights))
    y0 = r0 + int(np.median(tops))
    y1 = r0 + int(np.median(bottoms))

    side = max(x1 - x0, y1 - y0) * (1.0 + EXPAND)
    ccx = (x0 + x1) / 2.0
    ccy = (y0 + y1) / 2.0
    return (int(round(ccx - side / 2)), int(round(ccy - side / 2)),
            int(round(ccx + side / 2)), int(round(ccy + side / 2)))


def circular_alpha(size, ss=4):
    """抗锯齿的圆形 alpha 蒙版"""
    big = Image.new('L', (size * ss, size * ss), 0)
    ImageDraw.Draw(big).ellipse((0, 0, size * ss - 1, size * ss - 1), fill=255)
    return big.resize((size, size), Image.LANCZOS)


def main():
    if not os.path.isfile(SRC):
        print('找不到源图：%s' % SRC)
        return 1

    img = Image.open(SRC).convert('RGB')
    arr = np.asarray(img).astype(int)
    h, w, _ = arr.shape

    flat = arr.reshape(-1, 3)
    colors, counts = np.unique(flat, axis=0, return_counts=True)
    bg = colors[int(np.argmax(counts))].astype(int)
    print('源图 %dx%d，背景色 RGB(%d, %d, %d)' % (w, h, bg[0], bg[1], bg[2]))

    dist = np.max(np.abs(arr - bg), axis=2)
    coarse = dilate(erode(dist > BAND_THRESHOLD))
    fine = dist > FINE_THRESHOLD

    col_bands = find_bands(coarse.sum(axis=0), 4)
    row_bands = find_bands(coarse.sum(axis=1), 4)
    print('列带：%s' % (col_bands,))
    print('行带：%s' % (row_bands,))
    if len(col_bands) != 4 or len(row_bands) != 4:
        print('网格切分失败，请调整 BAND_THRESHOLD / MIN_GAP / FLOOR')
        return 1

    cells = {}
    annotated = img.copy()
    draw = ImageDraw.Draw(annotated)

    for ri, band_r in enumerate(row_bands):
        for ci, band_c in enumerate(col_bands):
            label = 'R%dC%d' % (ri + 1, ci + 1)
            r0, r1 = band_r
            c0, c1 = band_c
            area = int(coarse[r0:r1 + 1, c0:c1 + 1].sum())
            if area < MIN_AREA:
                draw.rectangle((c0, r0, c1, r1), outline=(255, 0, 0), width=2)
                draw.text((c0 + 8, r0 + 8), label + ' EMPTY', fill=(255, 0, 0))
                print('  %-6s EMPTY' % label)
                continue
            box = measure_circle(fine, band_r, band_c)
            if box is None:
                print('  %-6s 测量失败' % label)
                continue
            cells[label] = box
            draw.rectangle(box, outline=(0, 170, 0), width=3)
            draw.text((box[0] + 8, box[1] + 8), label, fill=(0, 120, 0))
            print('  %-6s 框%s 边长%4d 面积%6d' % (label, box, box[2] - box[0], area))

    os.makedirs(os.path.dirname(INDEX_IMG), exist_ok=True)
    annotated.save(INDEX_IMG, 'PNG', optimize=True)
    print('\n索引图：%s（请肉眼核对绿框是否正好套住圆、编号是否对应）'
          % os.path.relpath(INDEX_IMG, ROOT))

    missing = []
    os.makedirs(STORE_DIR, exist_ok=True)
    os.makedirs(MEDIA_DIR, exist_ok=True)
    for new_id, r, c in PICKS:
        label = 'R%dC%d' % (r, c)
        if label not in cells:
            missing.append(label)
            continue
        out = img.crop(cells[label]).resize((SIZE, SIZE), Image.LANCZOS).convert('RGBA')
        out.putalpha(circular_alpha(SIZE))
        a = np.asarray(out)[:, :, 3]
        assert out.size == (SIZE, SIZE)
        assert a[0, 0] == 0 and a[0, SIZE - 1] == 0 and a[SIZE - 1, 0] == 0 and a[SIZE - 1, SIZE - 1] == 0, \
            '%s 四角必须透明' % new_id
        assert a[SIZE // 2, SIZE // 2] == 255, '%s 中心必须不透明' % new_id
        out.save(os.path.join(MEDIA_DIR, 'avatar_%s.png' % new_id), 'PNG', optimize=True)
        out.save(os.path.join(STORE_DIR, 'avatar_%s.png' % new_id), 'PNG', optimize=True)
        print('  avatar_%s.png  <- %s  %.1f KB' % (
            new_id, label, os.path.getsize(os.path.join(MEDIA_DIR, 'avatar_%s.png' % new_id)) / 1024.0))

    if missing:
        print('以下选中格未识别到：%s' % ', '.join(missing))
        return 1

    cell = 350
    sheet = Image.new('RGB', (cell * 3, cell * 2), BACKGROUND)
    for idx, (new_id, _, _) in enumerate(PICKS):
        icon = Image.open(os.path.join(STORE_DIR, 'avatar_%s.png' % new_id)).convert('RGBA')
        icon = icon.resize((cell - 30, cell - 30), Image.LANCZOS)
        sheet.paste(icon, ((idx % 3) * cell + 15, (idx // 3) * cell + 15), icon)
    sheet.save(OVERVIEW, 'PNG', optimize=True)
    print('总览图：%s (%.1f KB)' % (os.path.relpath(OVERVIEW, ROOT),
                                    os.path.getsize(OVERVIEW) / 1024.0))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
