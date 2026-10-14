"""把真机截图（9:19.8）合成为 AppGallery 要求的 1080x1920（9:16）商店海报。

背景渐变与应用品牌色同源（#E5B15E -> #B36B14，135 度斜向），保证商店素材与 App 视觉一致。
"""
import os
import glob
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _resolve(env_name: str, candidates: list, fallback_name: str) -> str:
    """环境变量优先 → 依次尝试候选目录 → 回落到用户目录下的标准名。

    这样仓库里不会出现任何人的用户名，本机也能自动找到 OneDrive 重定向后的真实路径。
    """
    override = os.environ.get(env_name)
    if override:
        return override
    for path in candidates:
        if os.path.isdir(path):
            return path
    return os.path.join(os.path.expanduser('~'), fallback_name)


HOME = os.path.expanduser('~')
SHOT_DIR = _resolve('SHOT_DIR', [os.path.join(HOME, 'OneDrive', '图片'), os.path.join(HOME, 'Pictures')], 'Pictures')
OUT_DIR = os.path.join(ROOT, 'docs', 'store', 'screenshots')
DESKTOP_SHOT_DIR = os.environ.get(
    'DESKTOP_DIR',
    os.path.join(HOME, 'OneDrive', 'Desktop', '心情手记-商店截图'))
DESKTOP_DIR = DESKTOP_SHOT_DIR

CANVAS_W, CANVAS_H = 1080, 1920          # AGC 手机截图规范：9:16
BRAND_LIGHT = (0xE5, 0xB1, 0x5E)         # 应用品牌暖琥珀（与 hero 渐变异曲同工）
BRAND_DEEP = (0xB3, 0x6B, 0x14)

SHOT_H = 1400                            # 截图在画布上的高度
SHOT_RADIUS = 34                         # 截图圆角
SHADOW_ALPHA = 0.30
SHADOW_BLUR = 26

TITLE_Y = 118
SUB_Y = 318
SHOT_TOP = 452

FONT_BOLD = r'C:\Windows\Fonts\msyhbd.ttc'
FONT_REG = r'C:\Windows\Fonts\msyh.ttc'

# 每行：(截图文件名前缀, 主标题, 副标题, 输出文件名)
# ⚠️ 重拍截图后，务必把第一项改成新的文件名前缀（glob 找不到会直接报错，属于有意设计）
POSTERS = [
    ('Screenshot_v16_home', '今天的心情', '一眼看见今天的状态', '01-首页.png'),
    ('Screenshot_v16_calendar', '记录日历', '日期按心情着色，一眼看清这个月', '02-记录日历.png'),
    ('Screenshot_v16_ledger', '记好每一笔', '还能看到「这笔花得值不值」', '03-账本.png'),
    ('Screenshot_v16_mine', '属于你的记录', '记录、习惯、回顾与设置都在这里', '04-我的.png'),
    ('Screenshot_v17_lock', '锁住你的日记', '4 位数字密码，只存在本机', '05-应用锁.png'),
]


def brand_gradient(size):
    w, h = size
    xs, ys = np.meshgrid(np.arange(w, dtype=np.float32), np.arange(h, dtype=np.float32))
    t = (xs / (w - 1) + ys / (h - 1)) / 2.0
    rgb = np.zeros((h, w, 3), dtype=np.float32)
    for c in range(3):
        rgb[..., c] = BRAND_LIGHT[c] + (BRAND_DEEP[c] - BRAND_LIGHT[c]) * t
    return Image.fromarray(rgb.astype(np.uint8), 'RGB').convert('RGBA')


def rounded_mask(size, radius):
    m = Image.new('L', size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return m


def font(path, size):
    return ImageFont.truetype(path, size)


def center_text(draw, y, text, f, fill):
    w = draw.textbbox((0, 0), text, font=f)[2]
    draw.text(((CANVAS_W - w) / 2, y), text, font=f, fill=fill)


def build_poster(shot_path, title, subtitle):
    canvas = brand_gradient((CANVAS_W, CANVAS_H))
    draw = ImageDraw.Draw(canvas)

    # 顶部标题
    center_text(draw, TITLE_Y, title, font(FONT_BOLD, 76), (255, 255, 255, 255))
    center_text(draw, SUB_Y, subtitle, font(FONT_REG, 40), (255, 255, 255, 220))

    # 截图按高度缩放，居中放置（保持原始比例，不裁不压）
    with Image.open(shot_path) as im:
        shot = im.convert('RGBA')
    ratio = shot.width / shot.height
    shot = shot.resize((int(SHOT_H * ratio), SHOT_H), Image.LANCZOS)
    shot.putalpha(rounded_mask(shot.size, SHOT_RADIUS))
    x = (CANVAS_W - shot.width) // 2

    # 先铺投影
    shadow = Image.new('RGBA', canvas.size, (0, 0, 0, 0))
    mask = Image.new('L', canvas.size, 0)
    mask.paste(rounded_mask(shot.size, SHOT_RADIUS), (x, SHOT_TOP + 8))
    mask = mask.filter(ImageFilter.GaussianBlur(SHADOW_BLUR))
    shadow.putalpha(mask.point(lambda v: int(v * SHADOW_ALPHA)))
    canvas = Image.alpha_composite(canvas, shadow)

    canvas.paste(shot, (x, SHOT_TOP), shot)
    return canvas.convert('RGB')


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(DESKTOP_DIR, exist_ok=True)
    for prefix, title, subtitle, out_name in POSTERS:
        matches = glob.glob(os.path.join(SHOT_DIR, prefix + '.png'))
        assert matches, '找不到截图 %s' % prefix
        poster = build_poster(matches[0], title, subtitle)
        assert poster.size == (CANVAS_W, CANVAS_H), '尺寸必须是 %dx%d' % (CANVAS_W, CANVAS_H)
        p1 = os.path.join(OUT_DIR, out_name)
        p2 = os.path.join(DESKTOP_DIR, out_name)
        poster.save(p1, 'PNG', optimize=True)
        poster.save(p2, 'PNG', optimize=True)
        print('  %-16s %dx%d  %6.1f KB  <- %s' % (
            out_name, poster.width, poster.height, os.path.getsize(p1) / 1024.0, prefix))
    print('完成：%d 张' % len(POSTERS))


if __name__ == '__main__':
    main()
