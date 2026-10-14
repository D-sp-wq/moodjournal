# 打包并签名发布包（不依赖 DevEco 的「自动生成签名」）
#
# 背景：DevEco Studio 一旦打开项目，可能把 build-profile.json5 的签名配置改回
# 「自动生成签名」（keyAlias 变成 debugKey），用调试证书签出来的包 AGC 判 993 不合格。
# 而且 DevEco 写在配置里的口令是 IDE 专有加密串，明文会被拒（"length ... less than 32"）。
#
# 所以这里改成完全自控：让 hvigor 出**未签名**包，再用 hap-sign-tool 手工签名。
# 前提：build-profile.json5 里 product 不引用 signingConfig。
#
# 用法： pwsh -File tools/sign_release.ps1

# 注意：不能用 'Stop' —— hvigor 会把日志写到 stderr，
# Windows PowerShell 5.1 会把原生命令的 stderr 当成终止错误，脚本会在第一步就中断。
# 因此这里保持 Continue，用 $LASTEXITCODE 与日志内容判断成败。
$ErrorActionPreference = 'Continue'

$root = Split-Path $PSScriptRoot -Parent

# ── 本机路径：全部可通过环境变量覆盖，默认值取自系统标准目录，
#    这样仓库里不会出现任何人的用户名 ──
$devecoHome = if ($env:DEVECO_HOME) { $env:DEVECO_HOME } else { 'E:\huawei\DevEco Studio' }
$sdk     = Join-Path $devecoHome 'sdk'
$java    = Join-Path $devecoHome 'jbr\bin\java.exe'
$tool    = Join-Path $sdk 'default\openharmony\toolchains\lib\hap-sign-tool.jar'
$cfgDir  = if ($env:OHOS_CONFIG_DIR) { $env:OHOS_CONFIG_DIR } else { Join-Path $env:USERPROFILE '.ohos\config' }
$desktop = if ($env:DESKTOP_DIR) { $env:DESKTOP_DIR } else { [Environment]::GetFolderPath('Desktop') }

$keyAlias = 'datelog'
# ⚠️ 签名口令**不写进仓库**（开源仓库里等于公开你的发布签名密钥）。
# 取值顺序：环境变量 DATELOG_KEY_PASS → 本机私有文件 tools\signing.local.txt（已被 .gitignore 排除）
$keyPass = $env:DATELOG_KEY_PASS
if (-not $keyPass) {
  $localPassFile = Join-Path $PSScriptRoot 'signing.local.txt'
  if (Test-Path $localPassFile) {
    $keyPass = (Get-Content $localPassFile -Raw).Trim()
  }
}
if (-not $keyPass) {
  throw '缺少签名口令。请设置环境变量 DATELOG_KEY_PASS，或在 tools\signing.local.txt 中写入口令（该文件已被 .gitignore 排除）'
}
$cert = "$cfgDir\datelog-release.cer"
$profile = "$cfgDir\datelog-release.p7b"
$keystore = "$cfgDir\datelog.p12"

# 版本号从 app.json5 读，避免脚本里写死
$appJson = Get-Content (Join-Path $root 'AppScope\app.json5') -Raw
$versionName = ([regex]'"versionName"\s*:\s*"([^"]+)"').Match($appJson).Groups[1].Value
if (-not $versionName) { throw '读不到 AppScope/app.json5 里的 versionName' }

$work = Join-Path $env:TEMP 'signwork'
$outDir = Join-Path $root 'build\outputs\default'
$unsignedApp = Join-Path $outDir 'DevecoStudioProject-default-unsigned.app'

Write-Host '=== 1. 构建未签名包 ==='
$env:PATH = "E:\huawei\DevEco Studio\tools\node;E:\huawei\DevEco Studio\tools\ohpm\bin;" +
            "E:\huawei\DevEco Studio\tools\hvigor\bin;$env:PATH"
$env:DEVECO_SDK_HOME = $sdk
Push-Location $root
try {
  hvigorw clean --no-daemon | Out-Null
  $buildLog = hvigorw assembleApp --mode project -p product=default -p buildMode=release --no-daemon 2>&1 | Out-String
} finally {
  Pop-Location
}
if ($buildLog -match 'BUILD FAILED') {
  Write-Host $buildLog
  throw '构建失败'
}
if (-not (Test-Path $unsignedApp)) { throw "没找到未签名包：$unsignedApp" }

Write-Host '=== 2. 解包 ==='
Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $work | Out-Null
Copy-Item $unsignedApp (Join-Path $work 'app.zip') -Force
Expand-Archive (Join-Path $work 'app.zip') -DestinationPath (Join-Path $work 'unpacked') -Force

$hap = Join-Path $work 'unpacked\entry-default.hap'
if (-not (Test-Path $hap)) { throw '未签名包里没有 entry-default.hap' }

Write-Host '=== 3. 签 hap ==='
$signedHap = Join-Path $work 'entry-default-signed.hap'
& $java -jar $tool sign-app -mode localSign -keyAlias $keyAlias -keyPwd $keyPass `
  -appCertFile $cert -profileFile $profile -inFile $hap -outFile $signedHap `
  -signAlg SHA256withECDSA -keystoreFile $keystore -keystorePwd $keyPass `
  -compatibleVersion 24 -signCode 1 | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $signedHap)) { throw 'hap 签名失败' }

Write-Host '=== 4. 装回并重打包 ==='
Copy-Item $signedHap $hap -Force
$packed = Join-Path $work 'app-packed.app'
Remove-Item $packed -Force -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $work 'unpacked\*') -DestinationPath (Join-Path $work 'app-packed.zip') -Force
Move-Item (Join-Path $work 'app-packed.zip') $packed -Force

Write-Host '=== 5. 签 app ==='
$final = Join-Path $work 'app-final.app'
& $java -jar $tool sign-app -mode localSign -keyAlias $keyAlias -keyPwd $keyPass `
  -appCertFile $cert -profileFile $profile -inFile $packed -outFile $final `
  -signAlg SHA256withECDSA -keystoreFile $keystore -keystorePwd $keyPass -inForm zip | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $final)) { throw 'app 签名失败' }

Write-Host '=== 6. 官方验签 ==='
$vf = Join-Path $work 'verify'
Remove-Item $vf -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $vf | Out-Null
$verifyLog = & $java -jar $tool verify-app -inFile $final -inForm zip `
  -outCertChain (Join-Path $vf 'c.cer') -outProfile (Join-Path $vf 'p.p7b') 2>&1 | Out-String
if ($verifyLog -notmatch 'Verify success') { Write-Host $verifyLog; throw '官方验签未通过' }
Write-Host '  Verify success'

Write-Host '=== 7. 就位 ==='
$target = Join-Path $outDir 'DevecoStudioProject-default-signed.app'
Copy-Item $final $target -Force
$deskName = "心情手记-$versionName-signed.app"
Copy-Item $final (Join-Path $desktop $deskName) -Force
$hash = (Get-FileHash $final -Algorithm SHA256).Hash
Write-Host ''
Write-Host "交付  $deskName"
Write-Host ("大小  " + [math]::Round((Get-Item $final).Length / 1KB, 1) + ' KB')
Write-Host "SHA256 $hash"
Write-Host ''
Write-Host '别忘了跑一次签名自检：python tools/check_signing.py'
