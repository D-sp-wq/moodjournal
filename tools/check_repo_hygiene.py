"""仓库健康检查：在不依赖 HarmonyOS SDK 的普通环境里也能跑，因此可用于 CI。

检查三类**真实存在过的风险**（都有历史教训）：

1. 签名材料与口令混进版本控制
   —— 仓库里曾出现签名口令明文、本机证书路径配置。
2. 测试文件写了却没被注册
   —— `List.test.ets` 是唯一的测试入口，漏注册的用例会"存在但从不运行"，
      表面上测试全绿，实际有覆盖空洞。
3. 版本号回退
   —— `versionCode` 必须单调递增，否则应用市场会拒绝上传。

用法： python tools/check_repo_hygiene.py
退出码 0 = 通过；1 = 有问题（逐条打印）
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEST_DIR = os.path.join(ROOT, 'entry', 'src', 'test')
LIST_TEST = os.path.join(TEST_DIR, 'List.test.ets')
APP_JSON = os.path.join(ROOT, 'AppScope', 'app.json5')

# 出现这些文件名即为泄露风险（.example 模板不在此列）
FORBIDDEN_FILES = [
    'build-profile.json5',
    'tools/signing.local.txt',
    'build-profile.json5.autosign.bak',
]
FORBIDDEN_SUFFIX = ('.p12', '.cer', '.p7b', '.csr', '.keystore', '.jks')

problems = []


def section(title):
    print('\n=== %s ===' % title)


def tracked_files():
    """取需要检查的文件列表 = git 跟踪的文件 + 未跟踪但未被 .gitignore 排除的文件。

    为什么要算上未跟踪的文件：最常见的泄露场景是"刚写好一个脚本、里面写了本机路径，
    还没 git add 就被提交"。只看已跟踪文件会漏掉这种情况。

    不在 git 仓库里时回退为遍历工作区。
    """
    try:
        result = []
        for extra in ([], ['--others', '--exclude-standard']):
            out = subprocess.run(['git', 'ls-files'] + extra, cwd=ROOT, capture_output=True,
                                 text=True, encoding='utf-8', errors='ignore')
            if out.returncode == 0:
                result += [line.strip() for line in out.stdout.splitlines() if line.strip()]
        if result:
            return sorted(set(result))
    except Exception:
        pass
    files = []
    for base, dirs, names in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in ('.git', 'build', 'oh_modules', '.hvigor', '.test', '.preview')]
        for n in names:
            files.append(os.path.relpath(os.path.join(base, n), ROOT).replace('\\', '/'))
    return sorted(files)


# ── 1. 敏感内容 ──────────────────────────────────────────────
section('1. 敏感文件与口令')
files = tracked_files()
print('  受检文件数: %d' % len(files))

for rel in files:
    if rel in FORBIDDEN_FILES:
        problems.append('不应跟踪的文件被纳入版本控制: %s' % rel)
    if rel.lower().endswith(FORBIDDEN_SUFFIX):
        problems.append('证书/密钥类文件被纳入版本控制: %s' % rel)

# 口令本身不写在本脚本里：从环境变量或本机私有文件读取后再比对
secret = os.environ.get('DATELOG_KEY_PASS')
if not secret:
    local = os.path.join(ROOT, 'tools', 'signing.local.txt')
    if os.path.isfile(local):
        with open(local, 'r', encoding='utf-8') as fh:
            secret = fh.read().strip()

if secret:
    hit = []
    for rel in files:
        p = os.path.join(ROOT, rel)
        try:
            with open(p, 'r', encoding='utf-8', errors='ignore') as fh:
                if secret in fh.read():
                    hit.append(rel)
        except (OSError, UnicodeError):
            continue
    # 本机私有文件本身允许包含口令，忽略
    hit = [h for h in hit if not h.endswith('signing.local.txt')]
    if hit:
        problems.append('签名口令出现在: %s' % ', '.join(hit))
    print('  口令泄露检查: 已比对')
else:
    print('  口令泄露检查: 跳过（未设置 DATELOG_KEY_PASS，且无 tools/signing.local.txt）')

# 本机用户名痕迹
user_hits = []
for rel in files:
    p = os.path.join(ROOT, rel)
    try:
        with open(p, 'r', encoding='utf-8', errors='ignore') as fh:
            if re.search(r'C:\\Users\\(?!<)[A-Za-z0-9_.-]+', fh.read()):
                user_hits.append(rel)
    except (OSError, UnicodeError):
        continue
if user_hits:
    problems.append('含本机用户名路径: %s' % ', '.join(user_hits[:5]))

if not any('敏感' in p or '口令' in p or '证书' in p or '用户名' in p for p in problems):
    print('  ✓ 未发现敏感内容')

# ── 2. 测试注册完整性 ────────────────────────────────────────
section('2. 测试文件是否都已注册进 List.test.ets')
if not os.path.isfile(LIST_TEST):
    problems.append('找不到 List.test.ets（测试入口）')
else:
    with open(LIST_TEST, 'r', encoding='utf-8') as fh:
        registry = fh.read()

    test_files = sorted(f for f in os.listdir(TEST_DIR)
                        if f.endswith('.test.ets') and f != 'List.test.ets')
    unregistered = []
    for name in test_files:
        stem = name[:-len('.test.ets')]
        # List.test.ets 里的写法形如：
        #   import annualReportTest from './AnnualReport.test';
        #   export default function testsuite() { ... annualReportTest(); }
        # 注意导入的局部名首字母可能被改成小写，所以必须先用正则取出实际名字再找调用，
        # 不能拿文件名的首字母去猜（第一版就是这么错的，把 25 个文件全判成了未注册）。
        imported = re.search(r"import\s+(\w+)\s+from\s+'\./%s\.test'" % re.escape(stem), registry)
        if not imported:
            unregistered.append(name)
            continue
        local_name = imported.group(1)
        if not re.search(r'\b%s\s*\(\s*\)' % re.escape(local_name), registry):
            unregistered.append(name)

    print('  测试文件 %d 个，已注册 %d 个' % (len(test_files), len(test_files) - len(unregistered)))
    if unregistered:
        problems.append('写了但未注册（永远不会运行）: %s' % ', '.join(unregistered))
    else:
        print('  ✓ 全部已注册')

# ── 3. 版本号 ────────────────────────────────────────────────
section('3. 版本号')
if not os.path.isfile(APP_JSON):
    problems.append('找不到 AppScope/app.json5')
else:
    with open(APP_JSON, 'r', encoding='utf-8') as fh:
        app = fh.read()
    code = re.search(r'"versionCode"\s*:\s*(\d+)', app)
    name = re.search(r'"versionName"\s*:\s*"([^"]+)"', app)
    if not code or not name:
        problems.append('app.json5 里读不到 versionCode / versionName')
    else:
        print('  versionName = %s' % name.group(1))
        print('  versionCode = %s' % code.group(1))
        if int(code.group(1)) <= 1000009:
            problems.append('versionCode %s 未大于已上架版本 1000009，应用市场会拒绝'
                            % code.group(1))
        else:
            print('  ✓ 大于已上架版本 1000009')

# ── 4. 返回页面时是否会刷新 ───────────────────────────────────
# 教训来源：应用市场审核反馈「我的-时间轴-编辑：改变心情无法实时更新」。
# 根因是页面只有 aboutToAppear（仅首次创建时执行），router.back() 返回不会重跑，
# 于是页面一直显示旧数据。凡是会跳转到别的页面、又可能被"改完再回来"的页面，
# 都必须在 onPageShow 里重新读数据。
section('4. 会跳转的页面是否在 onPageShow 里刷新')
PAGES_DIR = os.path.join(ROOT, 'entry', 'src', 'main', 'ets', 'pages')
if not os.path.isdir(PAGES_DIR):
    print('  跳过（找不到 pages 目录）')
else:
    stale_pages = []
    navigable = 0
    for name in sorted(os.listdir(PAGES_DIR)):
        if not name.endswith('.ets'):
            continue
        with open(os.path.join(PAGES_DIR, name), 'r', encoding='utf-8', errors='ignore') as fh:
            body = fh.read()
        if 'pushUrl' not in body and 'pushPath' not in body:
            continue          # 自包含页面，没有"去别的页再回来"的路径
        navigable += 1
        if 'onPageShow' not in body:
            stale_pages.append(name)

    print('  会跳转的页面 %d 个，其中缺少 onPageShow 的 %d 个' % (navigable, len(stale_pages)))
    if stale_pages:
        problems.append('这些页面跳转后返回不会刷新，会显示旧数据: %s' % ', '.join(stale_pages))
    else:
        print('  ✓ 全部会在返回时刷新')

# ── 5. service 层是否有"写了但没接线"的函数 ───────────────────
# 教训来源：应用市场审核反馈「导出的是 TXT，而恢复需要 JSON，导致无法恢复」。
# 根因是 buildExportJson 实现完整、单元测试也覆盖，却**没有任何调用点** ——
# 功能在代码里存在，用户却根本用不到。
# 规则：services 下的 export function，若在「定义文件之外、且测试目录之外」无任何引用，即为未接线。
# 只被测试引用不算接线：单测全绿不等于用户能用上。
section('5. service 层导出函数是否都接了线')
SERVICES_DIR = os.path.join(ROOT, 'entry', 'src', 'main', 'ets', 'services')
TEST_PREFIX = 'entry/src/test/'

# 一次读入全部源码，避免逐个函数重复读文件
source_corpus = []          # [(绝对路径, 相对路径, 内容)]
for base, dirs, names in os.walk(os.path.join(ROOT, 'entry', 'src')):
    dirs[:] = [d for d in dirs if d not in ('build', 'oh_modules')]
    for n in names:
        if not n.endswith('.ets'):
            continue
        p = os.path.join(base, n)
        rel = os.path.relpath(p, ROOT).replace('\\', '/')
        with open(p, 'r', encoding='utf-8', errors='ignore') as fh:
            source_corpus.append((os.path.abspath(p), rel, fh.read()))

if not os.path.isdir(SERVICES_DIR):
    print('  跳过（找不到 services 目录）')
else:
    unused_fns = []
    total_fn = 0
    for own_abs, own_rel, own_body in source_corpus:
        if not own_abs.startswith(os.path.abspath(SERVICES_DIR)):
            continue
        for m in re.finditer(r'^export\s+(?:async\s+)?function\s+(\w+)', own_body, re.M):
            fn = m.group(1)
            total_fn += 1
            wired = False
            for other_abs, other_rel, other_body in source_corpus:
                if other_abs == own_abs or other_rel.startswith(TEST_PREFIX):
                    continue
                if re.search(r'\b%s\b' % re.escape(fn), other_body):
                    wired = True
                    break
            if not wired:
                unused_fns.append('%s (%s)' % (fn, os.path.basename(own_rel)))

    print('  service 导出函数 %d 个，未接线 %d 个' % (total_fn, len(unused_fns)))
    if unused_fns:
        problems.append('这些函数写了却没有调用点，用户用不到: %s' % ', '.join(unused_fns))
    else:
        print('  ✓ 全部已接线')

# ── 6. 代码里用到的路由是否都已注册 ───────────────────────────
# pushUrl 里手写的 'pages/Xxx' 一旦写错，跳转是**静默失败**（不报错、页面不动），
# 真机上极难排查。这里拿 main_pages.json 做一次全量比对。
section('6. 代码里用到的路由是否都在 main_pages.json 中注册')
MAIN_PAGES = os.path.join(ROOT, 'entry', 'src', 'main', 'resources', 'base', 'profile', 'main_pages.json')
if not os.path.isfile(MAIN_PAGES):
    print('  跳过（找不到 main_pages.json）')
else:
    with open(MAIN_PAGES, 'r', encoding='utf-8', errors='ignore') as fh:
        registered = set(re.findall(r'"(pages/[A-Za-z0-9_]+)"', fh.read()))
    used = set()
    for _abs, rel, body in source_corpus:
        if rel.startswith('entry/src/main/ets/'):
            used.update(re.findall(r"['\"](pages/[A-Za-z0-9_]+)['\"]", body))
    missing_routes = sorted(used - registered)
    print('  代码里用到 %d 个路由，main_pages.json 注册 %d 个' % (len(used), len(registered)))
    if missing_routes:
        problems.append('这些路由被引用但未注册，跳转会静默失败: %s' % ', '.join(missing_routes))
    else:
        print('  ✓ 全部已注册')

# ── 结论 ─────────────────────────────────────────────────────
section('结论')
if problems:
    print('  ✗ 发现 %d 个问题：' % len(problems))
    for p in problems:
        print('    - %s' % p)
    sys.exit(1)
print('  ✓ 仓库健康检查全部通过')
sys.exit(0)
