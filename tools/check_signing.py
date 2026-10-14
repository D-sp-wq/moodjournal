"""上架前签名自检：确认签名配置、材料一致性、以及包里嵌的是不是这份发布 Profile。

用法： <python> tools/check_signing.py
退出码 0 = 可以上架；1 = 有问题（逐条列出）

判据说明
--------
* 签名是否正确的**决定性判据**是「p12 的私钥 ↔ .cer 的发布证书 ↔ Profile 的分发证书」
  三者公钥一致；这三张证书的 EC 公钥应完全相同。
* 另外确认包内嵌的 Profile uuid 与 datelog-release.p7b 的 uuid 相同
  —— 若构建误用了"自动生成的签名"，嵌进去的会是另一份 Profile。
"""
import base64
import json
import os
import re
import subprocess
import sys
import tempfile
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, 'build', 'outputs', 'default', 'DevecoStudioProject-default-signed.app')
BUILD_PROFILE = os.path.join(ROOT, 'build-profile.json5')

# ── 本机路径：可用环境变量覆盖，默认取自系统标准位置，仓库内不含任何用户名 ──
DEVECO_HOME = os.environ.get('DEVECO_HOME', r'E:\huawei\DevEco Studio')
CFG = os.environ.get('OHOS_CONFIG_DIR', os.path.join(os.path.expanduser('~'), '.ohos', 'config'))
P12 = os.path.join(CFG, 'datelog.p12')
CER = os.path.join(CFG, 'datelog-release.cer')
P7B = os.path.join(CFG, 'datelog-release.p7b')
KEYTOOL = os.path.join(DEVECO_HOME, 'jbr', 'bin', 'keytool.exe')


def _read_p12_pass() -> str:
    """签名口令不写进仓库：优先环境变量，其次本机私有文件（已被 .gitignore 排除）"""
    from_env = os.environ.get('DATELOG_KEY_PASS')
    if from_env:
        return from_env
    local = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'signing.local.txt')
    if os.path.isfile(local):
        with open(local, 'r', encoding='utf-8') as fh:
            return fh.read().strip()
    return ''


P12_PASS = _read_p12_pass()

problems = []


def blocks(text):
    return re.findall(r'-----BEGIN CERTIFICATE-----(.*?)-----END CERTIFICATE-----', text, re.S)


def ec_pubkey(b64):
    """取 EC 公钥的 65 字节未压缩点"""
    der = base64.b64decode(re.sub(r'\s+', '', b64))
    i = der.find(b'\x03\x42\x00\x04')
    return der[i + 3:i + 3 + 65].hex().upper() if i >= 0 else None


def short(h):
    return (h[:20] + '…' + h[-12:]) if h else '(未找到)'


print('=== 1. 包内版本信息 ===')
with zipfile.ZipFile(APP) as z:
    info = json.loads(z.read('pack.info').decode('utf-8', 'replace'))
    hap_names = [n for n in z.namelist() if n.endswith('.hap')]
app = info['summary']['app']
print('  bundleName = %s' % app['bundleName'])
print('  versionCode= %s   versionName = %s' % (app['version']['code'], app['version']['name']))
if app['bundleName'] != 'com.datelog.couple':
    problems.append('包名不是 com.datelog.couple')

print('\n=== 2. 签名方式与材料 ===')
txt = open(BUILD_PROFILE, 'r', encoding='utf-8').read()
# 两种签名路线：
#  A. product 引用了 signingConfig → 由 DevEco/hvigor 签，材料写在 build-profile.json5
#  B. product 没引用 → 由 tools/sign_release.ps1 自控签，材料写在那个脚本里
#     （DevEco 一打开项目就会把配置改回自动签名，所以路线 B 时不能只看 json5，
#      否则会误报「keyAlias 是 debugKey」）
if re.search(r'"signingConfig"\s*:\s*"', txt):
    print('  方式：DevEco 签名配置（product 引用了 signingConfig）')
    src = txt
    pats = (r'"keyAlias"\s*:\s*"([^"]+)"', r'"storeFile"\s*:\s*"([^"]+)"',
            r'"certpath"\s*:\s*"([^"]+)"', r'"profile"\s*:\s*"([^"]+)"')
else:
    print('  方式：自控签名（product 未引用 signingConfig，由 tools/sign_release.ps1 签）')
    src = open(os.path.join(ROOT, 'tools', 'sign_release.ps1'), 'r', encoding='utf-8').read()
    pats = (r"\$keyAlias\s*=\s*[\"']([^\"']+)[\"']", r"\$keystore\s*=\s*[\"']([^\"']+)[\"']",
            r"\$cert\s*=\s*[\"']([^\"']+)[\"']", r"\$profile\s*=\s*[\"']([^\"']+)[\"']")


def pick(pat):
    found = re.search(pat, src)
    return found.group(1) if found else ''


alias = pick(pats[0])
store = pick(pats[1])
certp = pick(pats[2])
proff = pick(pats[3])
print('  keyAlias  = %s' % (alias if alias else '?'))
print('  storeFile = %s' % (os.path.basename(store) if store else '?'))
print('  certpath  = %s' % (os.path.basename(certp) if certp else '?'))
print('  profile   = %s' % (os.path.basename(proff) if proff else '?'))
if alias != 'datelog':
    problems.append('keyAlias 是 %s（不是发布用的 datelog）' % alias)
if 'datelog.p12' not in store:
    problems.append('storeFile 不是 datelog.p12')
if 'datelog-release.cer' not in certp:
    problems.append('certpath 不是 datelog-release.cer')
if 'datelog-release.p7b' not in proff:
    problems.append('profile 不是 datelog-release.p7b')

print('\n=== 3. Profile 绑定 ===')
p7b_text = open(P7B, 'rb').read().decode('utf-8', 'ignore')
bundle = re.search(r'"bundle-name":"([^"]+)"', p7b_text)
ptype = re.search(r'"type":"([^"]+)"', p7b_text)
uuid = re.search(r'"uuid":"([^"]+)"', p7b_text)
print('  bundle-name = %s   type = %s' % (bundle.group(1) if bundle else '?',
                                          ptype.group(1) if ptype else '?'))
print('  profile uuid = %s' % (uuid.group(1) if uuid else '?'))
if ptype and ptype.group(1) != 'release':
    problems.append('Profile 不是发布类型（%s）' % ptype.group(1))

print('\n=== 4. 三张证书的公钥是否一致（签名是否正确的决定性判据）===')
tmp = tempfile.mkdtemp(prefix='sig')
try:
    pem = os.path.join(tmp, 'p12.pem')
    subprocess.run([KEYTOOL, '-exportcert', '-alias', 'datelog', '-keystore', P12,
                    '-storetype', 'PKCS12', '-storepass', P12_PASS, '-rfc', '-file', pem],
                   capture_output=True, text=True)
    p12_pub = None
    if os.path.isfile(pem):
        cb = blocks(open(pem, 'r', encoding='utf-8').read())
        if cb:
            p12_pub = ec_pubkey(cb[0])
    cer_pubs = [ec_pubkey(b) for b in blocks(open(CER, 'r', encoding='utf-8').read())]
    dist = re.search(r'"distribution-certificate":"(.*?)","bundle-name"', p7b_text, re.S)
    prof_pub = None
    if dist:
        cb = blocks(dist.group(1).replace('\\n', '\n'))
        if cb:
            prof_pub = ec_pubkey(cb[0])
    print('  p12 私钥对应公钥      : %s' % short(p12_pub))
    print('  .cer 里的发布证书公钥 : %s' % short(cer_pubs[2] if len(cer_pubs) > 2 else None))
    print('  Profile 分发证书公钥  : %s' % short(prof_pub))
    if not (p12_pub and p12_pub == prof_pub):
        problems.append('p12 的私钥与 Profile 指定的分发证书不匹配')
    if not (len(cer_pubs) > 2 and cer_pubs[2] == prof_pub):
        problems.append('.cer 里的发布证书与 Profile 指定的分发证书不一致')
finally:
    import shutil
    shutil.rmtree(tmp, ignore_errors=True)

print('\n=== 5. 包里嵌的 Profile 是不是这份 ===')
# 注意：Profile 存放在 .app 级的签名块里（在 zip 中央目录之外），
# 只能扫原始文件字节；用 zipfile 读条目是找不到的。
target_uuid = uuid.group(1) if uuid else None
raw_app = open(APP, 'rb').read()
found = bool(target_uuid) and target_uuid.encode() in raw_app
print('  在 .app 原始字节中查找 uuid %s : %s' % (target_uuid, '找到' if found else '未找到'))
if not found:
    problems.append('包里嵌的 Profile 不是 datelog-release.p7b（很可能构建时用的是自动生成的签名）')

print('\n=== 结论 ===')
if problems:
    print('  ✗ 不能上架：')
    for p in problems:
        print('    - %s' % p)
    sys.exit(1)
print('  ✓ 签名配置、证书一致性、内嵌 Profile 全部正确，可以上架')
sys.exit(0)
