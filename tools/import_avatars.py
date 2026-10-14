"""把外部提供的 6 张头像导入为 App 资源。

用法
----
1. 把 6 张图放进 `avatars-to-import/`，命名必须为：

       m1  m2  m3     （男 3 张）
       f1  f2  f3     （女 3 张）

   扩展名支持 .png / .jpg / .jpeg / .webp，文件名大小写不敏感。

2. 运行：

       <python> tools/import_avatars.py

   脚本会：
     * 居中裁成正方形 → 缩放到 256x256（LANCZOS）
     * 写入 entry/src/main/resources/base/media/avatar_{m,f}1..3.png
     * 复制原图到 docs/store/avatars/
     * 生成 3x2 总览图 docs/store/avatars-overview.png
     * 校验 6 张齐全、尺寸正确，缺哪张就报哪张

注意
----
应用里头像是**圆形**显示（对正方形图做圆角裁切），所以请保证主体居中、
四周留出余量，别把脸贴到边上。

> 若素材是一张 4x4 的头像网格图，请改用 `tools/extract_avatars.py`，
> 它会自动切网格并裁出选定的头像。
"""
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIR = os.path.join(ROOT, 'avatars-to-import')
MEDIA_DIR = os.path.join(ROOT, 'entry', 'src', 'main', 'resources', 'base', 'media')
STORE_DIR = os.path.join(ROOT, 'docs', 'store', 'avatars')
OVERVIEW = os.path.join(ROOT, 'docs', 'store', 'avatars-overview.png')

SIZE = 256
EXTS = ['.png', '.jpg', '.jpeg', '.webp']
NAMES = ['m%d' % i for i in range(1, 4)] + ['f%d' % i for i in range(1, 4)]
COLUMNS = 3
BACKGROUND = (0xFD, 0xF8, 0xF0)


def find_source(name):
    """在导入目录里找 name 对应的源文件（扩展名与大小写不敏感）"""
    if not os.path.isdir(SRC_DIR):
        return None
    for entry in sorted(os.listdir(SRC_DIR)):
        stem, ext = os.path.splitext(entry)
        if stem.lower() == name and ext.lower() in EXTS:
            return os.path.join(SRC_DIR, entry)
    return None


def square_resize(img):
    """居中裁成正方形后缩放到 SIZE（保持不拉伸变形）"""
    w, h = img.size
    side = min(w, h)
    left = (w - side) // 2
    top = (h - side) // 2
    img = img.crop((left, top, left + side, top + side))
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def main():
    if not os.path.isdir(SRC_DIR):
        os.makedirs(SRC_DIR)
        print('已创建导入目录：%s' % os.path.relpath(SRC_DIR, ROOT))
        print('请把 6 张图按 m1..m3 / f1..f3 命名放进去，然后重新运行本脚本。')
        return 1

    missing = [n for n in NAMES if find_source(n) is None]
    if missing:
        print('缺少 %d 张：%s' % (len(missing), ', '.join(missing)))
        print('请在 %s 中补齐（支持 %s，文件名大小写不敏感）'
              % (os.path.relpath(SRC_DIR, ROOT), '/'.join(EXTS)))
        return 1

    if not os.path.isdir(MEDIA_DIR):
        print('找不到资源目录：%s' % MEDIA_DIR)
        return 1
    os.makedirs(STORE_DIR, exist_ok=True)

    count = 0
    for name in NAMES:
        src = find_source(name)
        img = Image.open(src)
        img = img.convert('RGBA') if img.mode in ('RGBA', 'LA', 'P') else img.convert('RGB')
        out = square_resize(img)

        media_path = os.path.join(MEDIA_DIR, 'avatar_%s.png' % name)
        out.save(media_path, 'PNG', optimize=True)

        store_path = os.path.join(STORE_DIR, 'avatar_%s.png' % name)
        out.save(store_path, 'PNG', optimize=True)

        check = Image.open(media_path)
        assert check.size == (SIZE, SIZE), '%s 尺寸不是 %dx%d' % (name, SIZE, SIZE)
        count += 1
        print('  avatar_%s.png  <- %-18s %5.1f KB'
              % (name, os.path.basename(src), os.path.getsize(media_path) / 1024.0))

    assert count == len(NAMES), '应处理 %d 张，实际 %d 张' % (len(NAMES), count)

    rows = (len(NAMES) + COLUMNS - 1) // COLUMNS
    cell = 350
    sheet = Image.new('RGB', (cell * COLUMNS, cell * rows), BACKGROUND)
    for idx, name in enumerate(NAMES):
        icon = Image.open(os.path.join(STORE_DIR, 'avatar_%s.png' % name)).convert('RGBA')
        icon = icon.resize((cell - 30, cell - 30), Image.LANCZOS)
        sheet.paste(icon, ((idx % COLUMNS) * cell + 15, (idx // COLUMNS) * cell + 15), icon)
    sheet.save(OVERVIEW, 'PNG', optimize=True)

    print('\n完成：%d 张已写入 %s' % (len(NAMES), os.path.relpath(MEDIA_DIR, ROOT)))
    print('总览图：%s (%.1f KB)' % (os.path.relpath(OVERVIEW, ROOT),
                                    os.path.getsize(OVERVIEW) / 1024.0))
    print('下一步：重新构建 App（hvigorw assembleApp ... -p buildMode=release）')
    return 0


if __name__ == '__main__':
    sys.exit(main())
