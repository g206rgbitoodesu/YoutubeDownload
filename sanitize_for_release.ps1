# ========================================
# sanitize_for_release.ps1
# 公開用: 個人情報除去 & パス正規化 & 大小文字統一
# ========================================
# 使い方:
#   .\sanitize_for_release.ps1 -DryRun    # 確認（書き込みなし）
#   .\sanitize_for_release.ps1            # 本実行（自動バックアップ）
#   .\sanitize_for_release.ps1 -NoBackup  # バックアップなし
# ========================================
[CmdletBinding()]
param(
    [string]$RootDir   = $PSScriptRoot,
    [string]$BackupDir = "_sanitize_backup",
    [switch]$DryRun,
    [switch]$NoBackup
)

$ErrorActionPreference = "Stop"
Set-Location -Path $RootDir

# 自分自身をスキャン対象から除外（スクリプト内の検出パターン文字列を保護）
$SelfName = Split-Path $PSCommandPath -Leaf

# ----------------------------------------
# 置換ルール（順序が重要: 具体的 → 一般 → 大小文字）
# ----------------------------------------
$rules = @(
    # --- .ps1 用: $env:USERPROFILE に置換（環境非依存化） ---
    @{ Ext = @('.ps1')
       Find = 'C:\Users\yoshi\Documents\youtubeDownload'
       Replace = '$env:USERPROFILE\Documents\YoutubeDownload' }
    @{ Ext = @('.ps1')
       Find = 'C:/Users/yoshi/Documents/youtubeDownload'
       Replace = '$env:USERPROFILE/Documents/YoutubeDownload' }
    @{ Ext = @('.ps1')
       Find = 'C:\Users\yoshi\Downloads\navidrome_0.64.2_windows_amd64'
       Replace = '$env:USERPROFILE\Downloads\navidrome' }
    @{ Ext = @('.ps1')
       Find = 'C:/Users/yoshi/Downloads/navidrome_0.64.2_windows_amd64'
       Replace = '$env:USERPROFILE/Downloads/navidrome' }
    @{ Ext = @('.ps1')
       Find = 'C:\Users\yoshi'
       Replace = '$env:USERPROFILE' }
    @{ Ext = @('.ps1')
       Find = 'C:/Users/yoshi'
       Replace = '$env:USERPROFILE' }

    # --- ドキュメント用: プレースホルダに置換 ---
    @{ Ext = @('.txt','.md')
       Find = 'C:\Users\yoshi\Documents\youtubeDownload'
       Replace = 'C:\Users\<ユーザー名>\Documents\YoutubeDownload' }
    @{ Ext = @('.txt','.md')
       Find = 'C:/Users/yoshi/Documents/youtubeDownload'
       Replace = 'C:/Users/<ユーザー名>/Documents/YoutubeDownload' }
    @{ Ext = @('.txt','.md')
       Find = 'C:\Users\yoshi\Downloads\navidrome_0.64.2_windows_amd64'
       Replace = 'C:\Users\<ユーザー名>\Downloads\navidrome' }
    @{ Ext = @('.txt','.md')
       Find = 'C:\Users\yoshi'
       Replace = 'C:\Users\<ユーザー名>' }
    @{ Ext = @('.txt','.md')
       Find = 'C:/Users/yoshi'
       Replace = 'C:/Users/<ユーザー名>' }

    # --- 大小文字統一（全対象ファイル、最後に適用） ---
    @{ Ext = @('.ps1','.txt','.md','.csv')
       Find = 'youtubeDownload'
       Replace = 'YoutubeDownload' }
)

$targetExtensions = @('.ps1','.txt','.md','.csv')

# ----------------------------------------
# 対象ファイル列挙（自分自身を除外）
# ----------------------------------------
$files = Get-ChildItem -Path $RootDir -Recurse -File |
    Where-Object {
        $targetExtensions -contains $_.Extension.ToLower() -and
        $_.Name -ne $SelfName -and
        $_.FullName -notlike "*\$BackupDir\*"
    }

Write-Host ""
Write-Host "=== 公開用サニタイズ ===" -ForegroundColor Magenta
Write-Host ("  ルート      : {0}" -f $RootDir)
Write-Host ("  対象ファイル: {0}" -f $files.Count)
if ($DryRun) { Write-Host "  ★ DryRun モード" -ForegroundColor Magenta }
Write-Host ""

$totalChanges = 0
$changedFiles = 0

foreach ($file in $files) {
    $ext = $file.Extension.ToLower()

    # BOM 検出
    $bytes  = [System.IO.File]::ReadAllBytes($file.FullName)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)

    $original = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
    $modified = $original
    $fileChanges = 0

    foreach ($rule in $rules) {
        if ($rule.Ext -notcontains $ext) { continue }
        $before   = $modified
        $modified = $modified.Replace($rule.Find, $rule.Replace)
        if ($modified -ne $before) {
            $count = ([regex]::Matches($before, [regex]::Escape($rule.Find))).Count
            $fileChanges += $count
        }
    }

    if ($modified -eq $original) { continue }

    $changedFiles++
    $totalChanges += $fileChanges
    Write-Host ("  [{0,-5}] {1}  ({2}箇所)" -f $ext.Trim('.'), $file.Name, $fileChanges) -ForegroundColor Yellow

    if ($DryRun) { continue }

    # バックアップ
    if (-not $NoBackup) {
        $relPath   = $file.FullName.Substring($RootDir.Length + 1)
        $backupPath = Join-Path $BackupDir $relPath
        $backupParent = Split-Path $backupPath -Parent
        if (-not (Test-Path $backupParent)) {
            New-Item -ItemType Directory -Path $backupParent -Force | Out-Null
        }
        Copy-Item -LiteralPath $file.FullName -Destination $backupPath -Force
    }

    # BOM 状態を保持して書き込み
    $enc = New-Object System.Text.UTF8Encoding($hasBom)
    [System.IO.File]::WriteAllText($file.FullName, $modified, $enc)
}

# ----------------------------------------
# サマリ
# ----------------------------------------
Write-Host ""
Write-Host "========================================"
Write-Host "サニタイズ完了" -ForegroundColor Cyan
Write-Host ("  変更ファイル: {0}" -f $changedFiles)
Write-Host ("  総置換箇所  : {0}" -f $totalChanges)

if (-not $NoBackup -and -not $DryRun -and $changedFiles -gt 0) {
    Write-Host ("  バックアップ: {0}\" -f $BackupDir) -ForegroundColor Green
}

if ($DryRun) {
    Write-Host ""
    Write-Host "  ★ DryRun のため実際には書き込んでいません" -ForegroundColor Magenta
    Write-Host "  本実行するには -DryRun を外してください" -ForegroundColor Yellow
    exit 0
}

# ----------------------------------------
# 残存チェック
# ----------------------------------------
Write-Host ""
Write-Host "--- 残存個人情報チェック ---" -ForegroundColor Cyan

$remaining = @(Get-ChildItem -Path $RootDir -Recurse -File |
    Where-Object {
        $targetExtensions -contains $_.Extension.ToLower() -and
        $_.Name -ne $SelfName -and
        $_.FullName -notlike "*\$BackupDir\*"
    } |
    ForEach-Object {
        $text = [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8)
        if ($text -match 'yoshi' -or $text -match 'youtubeDownload') {
            $_.FullName.Substring($RootDir.Length + 1)
        }
    })

if ($remaining.Count -eq 0) {
    Write-Host "  ★ 個人情報は残っていません" -ForegroundColor Green
} else {
    Write-Host ("  ⚠ 残存: {0} ファイル" -f $remaining.Count) -ForegroundColor Red
    $remaining | ForEach-Object { Write-Host ("    - {0}" -f $_) -ForegroundColor Red }
}

Write-Host ""
Write-Host "次の手順:" -ForegroundColor Yellow
Write-Host "  1. .\diagnose.ps1 を実行して動作確認" -ForegroundColor Yellow
Write-Host "  2. .\run_all.ps1 -DryRun でフロー確認" -ForegroundColor Yellow
Write-Host "  3. 問題なければバックアップを削除:" -ForegroundColor Yellow
Write-Host ("     Remove-Item .\{0} -Recurse -Force" -f $BackupDir) -ForegroundColor Yellow