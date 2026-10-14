# 把本项目提交并推送到你的 GitHub 仓库
#
# 用法（把占位换成你自己的信息）：
#   pwsh -File tools/publish_to_github.ps1 -UserName 你的GitHub用户名 -Email 你的邮箱
#
# 可选参数：
#   -RepoName   仓库名，默认 moodjournal
#   -Message    提交信息
#
# 前置条件：
#   1. 已在 GitHub 网页上创建**空仓库**（不要勾选 README / .gitignore / License，避免冲突）
#   2. 本机已能向 GitHub 推送（首次推送会弹出登录，或用 PAT / SSH）
#
# 说明：git 身份只设置在**本仓库**（local），不会改动你的全局配置。

param(
  [Parameter(Mandatory = $true)][string]$UserName,
  [Parameter(Mandatory = $true)][string]$Email,
  [string]$RepoName = 'moodjournal',
  [string]$Message = '心情手记 v1.7.0：离线优先的 HarmonyOS 心情日记应用'
)

$ErrorActionPreference = 'Continue'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

Write-Host '=== 1. 设置本仓库的提交身份（不影响全局配置）===' -ForegroundColor Cyan
git config user.name $UserName
git config user.email $Email
Write-Host ("  user.name  = " + (git config user.name))
Write-Host ("  user.email = " + (git config user.email))

Write-Host "`n=== 2. 安全检查：确认敏感文件没有被纳入版本控制 ===" -ForegroundColor Cyan
$forbidden = @('build-profile.json5', 'tools/signing.local.txt', 'build-profile.json5.autosign.bak')
$bad = @()
foreach ($f in $forbidden) {
  git ls-files --error-unmatch $f *>$null
  if ($LASTEXITCODE -eq 0) { $bad += $f }
}
$resume = git ls-files 'resume_task/*'
if ($resume) { $bad += 'resume_task/*' }

# 口令本身不写在脚本里：从本机私有文件 / 环境变量读取后再拿去比对
$secret = $env:DATELOG_KEY_PASS
if (-not $secret) {
  $localPassFile = Join-Path $PSScriptRoot 'signing.local.txt'
  if (Test-Path $localPassFile) { $secret = (Get-Content $localPassFile -Raw).Trim() }
}
if ($secret) {
  $leak = git grep --cached -l $secret 2>$null
  if ($leak) { $bad += ('口令明文: ' + ($leak -join ', ')) }
} else {
  Write-Host '  ! 未找到本机口令文件，跳过「口令泄露」检查（其余检查照常）' -ForegroundColor Yellow
}

if ($bad.Count -gt 0) {
  Write-Host '  ✗ 发现不该提交的内容，已中止：' -ForegroundColor Red
  $bad | ForEach-Object { Write-Host ('    - ' + $_) -ForegroundColor Red }
  Write-Host '  请先处理后再运行。' -ForegroundColor Red
  exit 1
}
Write-Host '  ✓ 无签名口令、无本机签名配置、无个人材料' -ForegroundColor Green

Write-Host "`n=== 3. 用你的名字填好许可证与 README 里的署名 ===" -ForegroundColor Cyan
foreach ($rel in @('LICENSE', 'README.md')) {
  $p = Join-Path $root $rel
  if (Test-Path $p) {
    $raw = Get-Content $p -Raw
    if ($raw.Contains('<GITHUB_USERNAME>')) {
      Set-Content -Path $p -Value $raw.Replace('<GITHUB_USERNAME>', $UserName) -NoNewline -Encoding UTF8
      Write-Host ("  已署名: " + $rel)
    } else {
      Write-Host ("  无需处理: " + $rel)
    }
  }
}

Write-Host "`n=== 4. 暂存并提交 ===" -ForegroundColor Cyan
git add -A
$count = (git diff --cached --name-only | Measure-Object).Count
Write-Host ("  待提交文件: " + $count + " 个")
if ($count -eq 0) {
  Write-Host '  没有变更需要提交，跳过。'
} else {
  git commit -m $Message
  if ($LASTEXITCODE -ne 0) { Write-Host '  ✗ 提交失败' -ForegroundColor Red; exit 1 }
  Write-Host '  ✓ 已提交' -ForegroundColor Green
}

Write-Host "`n=== 5. 关联远程仓库 ===" -ForegroundColor Cyan
$url = "https://github.com/$UserName/$RepoName.git"
$exists = git remote get-url origin 2>$null
if ($LASTEXITCODE -eq 0) {
  git remote set-url origin $url
  Write-Host ("  已更新 origin → " + $url)
} else {
  git remote add origin $url
  Write-Host ("  已添加 origin → " + $url)
}

Write-Host "`n=== 6. 推送 ===" -ForegroundColor Cyan
Write-Host '  如果仓库还没在 GitHub 上创建，这一步会失败 —— 先去网页建一个空仓库再重跑本脚本。'
git push -u origin main
if ($LASTEXITCODE -ne 0) {
  Write-Host "`n✗ 推送失败。常见原因：" -ForegroundColor Red
  Write-Host '  1. GitHub 上还没有这个仓库 → 到 https://github.com/new 创建一个空仓库（名为 ' + $RepoName + '）'
  Write-Host '  2. 未登录 / 无权限 → 首次推送会弹登录窗口；或使用 PAT、或改用 SSH 地址'
  exit 1
}

Write-Host "`n✓ 完成，仓库地址：$url" -ForegroundColor Green
