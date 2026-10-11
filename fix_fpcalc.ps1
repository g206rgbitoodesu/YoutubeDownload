# ========================================
# fpcalc 自動探索 & PATH 追加
# ========================================
# 処理:
#   1. PATH 上に fpcalc があるか確認
#   2. なければ一般的な場所を探索
#   3. 見つかったらユーザー PATH に追加
#   4. Picard.ini に fpcalc_path を書き込む（設定ファイルがあれば）
# ========================================
[CmdletBinding()]
param(
    [switch]$DryRun   # 実際には変更せず、見つかった場所だけ表示
)

$ErrorActionPreference = "Continue"

function Write-OK   { param([string]$m) Write-Host "  [OK]   $m" -ForegroundColor Green }
function Write-NG   { param([string]$m) Write-Host "  [NG]   $m" -ForegroundColor Red }
function Write-Warn { param([string]$m) Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function Write-Info { param([string]$m) Write-Host "  [INFO] $m" -ForegroundColor Gray }

Write-Host ""
Write-Host "=== fpcalc 自動セットアップ ===" -ForegroundColor Magenta
Write-Host ""

# ========================================
# 1. PATH 上の確認
# ========================================
$existing = Get-Command fpcalc -ErrorAction SilentlyContinue
if ($existing) {
    Write-OK ("PATH 上に既に存在: {0}" -f $existing.Source)
    $fpcalcPath = $existing.Source
} else {
    Write-Warn "PATH 上に fpcalc がありません。探索を開始します..."
    $fpcalcPath = $null
}

# ========================================
# 2. 探索対象フォルダ
# ========================================
if (-not $fpcalcPath) {
    $searchRoots = @(
        "$env:USERPROFILE\Downloads",
        "$env:USERPROFILE\Documents",
        "$env:USERPROFILE\Desktop",
        "C:\Program Files",
        "C:\Program Files (x86)",
        "C:\ffmpeg",
        "C:\tools",
        "$env:LOCALAPPDATA\Microsoft\WinGet\Packages",
        "$env:USERPROFILE\Downloads\navidrome"
    )

    Write-Info ("探索対象: {0} 個のルート" -f $searchRoots.Count)
    foreach ($root in $searchRoots) {
        if (-not (Test-Path $root)) { continue }
        Write-Info ("  探索中: {0}" -f $root)

        $found = Get-ChildItem -Path $root -Filter "fpcalc.exe" -Recurse -File -ErrorAction SilentlyContinue |
                 Select-Object -First 1
        if ($found) {
            $fpcalcPath = $found.FullName
            Write-OK ("見つかりました: {0}" -f $fpcalcPath)
            break
        }
    }
}

if (-not $fpcalcPath) {
    Write-NG "fpcalc.exe が見つかりませんでした"
    Write-Info "  Chromaprint をダウンロードして、任意の場所に配置してください:"
    Write-Info "    https://acoustid.org/chromaprint"
    exit 1
}

# ========================================
# 3. 実行テスト
# ========================================
Write-Host ""
Write-Info "実行テスト..."
try {
    $verOut = & $fpcalcPath -version 2>&1
    Write-OK ("fpcalc -version: {0}" -f ($verOut -join " "))
} catch {
    Write-NG ("実行できません: {0}" -f $_)
    exit 1
}

# ========================================
# 4. PATH 追加
# ========================================
$fpcalcDir = Split-Path $fpcalcPath -Parent
Write-Host ""
Write-Info ("fpcalc フォルダ: {0}" -f $fpcalcDir)

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$pathParts = $userPath -split ';' | Where-Object { $_ -ne "" }

if ($pathParts -contains $fpcalcDir) {
    Write-OK "既にユーザー PATH に含まれています"
} else {
    if ($DryRun) {
        Write-Warn ("[DryRun] ユーザー PATH に追加予定: {0}" -f $fpcalcDir)
    } else {
        $newPath = ($pathParts + $fpcalcDir) -join ';'
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        Write-OK ("ユーザー PATH に追加しました: {0}" -f $fpcalcDir)
        Write-Warn "  ※ 反映には PowerShell の再起動が必要です"
    }
}

# 現在のプロセスにも即時反映（このスクリプト内で使えるように）
$env:Path = "$env:Path;$fpcalcDir"

# ========================================
# 5. Picard.ini の更新
# ========================================
Write-Host ""
Write-Info "Picard 設定ファイルを確認..."

$configPaths = @(
    "$env:APPDATA\MusicBrainz\Picard\Picard.ini",
    "$env:LOCALAPPDATA\MusicBrainz\Picard\Picard.ini",
    "$env:USERPROFILE\AppData\Roaming\MusicBrainz\Picard\Picard.ini",
    "$env:USERPROFILE\AppData\Local\MusicBrainz\Picard\Picard.ini"
)

$configFound = $null
foreach ($p in $configPaths) {
    if (Test-Path $p) { $configFound = $p; break }
}

if (-not $configFound) {
    Write-Warn "Picard.ini が見つかりません"
    Write-Info "  → Picard を一度起動して GUI から fpcalc を設定してください:"
    Write-Info "     オプション → 指紋 → 'fpcalc の場所' に以下を入力"
    Write-Info ("     {0}" -f $fpcalcPath)
} else {
    Write-OK ("設定ファイル: {0}" -f $configFound)

    if ($DryRun) {
        Write-Warn "[DryRun] fpcalc_path を書き込む予定"
    } else {
        # バックアップ
        $backup = "$configFound.bak_$(Get-Date -Format yyyyMMdd_HHmmss)"
        Copy-Item -LiteralPath $configFound -Destination $backup -Force
        Write-OK ("バックアップ: {0}" -f $backup)

        $content = Get-Content -Path $configFound -Encoding UTF8
        $updated = $false
        $newContent = foreach ($line in $content) {
            if ($line -match '^\s*fpcalc_path\s*=') {
                $updated = $true
                "fpcalc_path = $fpcalcPath"
            } else {
                $line
            }
        }

        if (-not $updated) {
            # [fingerprinting] セクションを探して追記
            $newContent = @($newContent) + @("", "[fingerprinting]", "fpcalc_path = $fpcalcPath")
        }

        $newContent | Set-Content -Path $configFound -Encoding UTF8
        Write-OK ("fpcalc_path を書き込みました: {0}" -f $fpcalcPath)
    }
}

# ========================================
# 6. サマリ
# ========================================
Write-Host ""
Write-Host "========================================"
Write-Host "セットアップ完了" -ForegroundColor Cyan
Write-Host ("  fpcalc: {0}" -f $fpcalcPath)
Write-Host ""
Write-Host "次の手順:" -ForegroundColor Yellow
Write-Host "  1. PowerShell を閉じて開き直す（PATH 反映）" -ForegroundColor Yellow
Write-Host "  2. .\diagnose.ps1 で再確認" -ForegroundColor Yellow
Write-Host "  3. 全て [OK] になったら .\run_picard.ps1 を実行" -ForegroundColor Yellow