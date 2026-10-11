# ========================================
# Picard 自動整理スクリプト（改良版 v4）
# ========================================
# 変更点:
#   - picard_commands.txt を実行時に動的生成
#     → sanitize_for_release.ps1 に壊されない
#     → 絶対パスを毎回解決
#     → QUIT を必ず付与（プロセスが終了する）
#   - v4: picard_commands.txt を BOM なし UTF-8 で書き込み
#         Picard は "#" コメントを解釈できないため、コメント行を削除
# ========================================
[CmdletBinding()]
param(
    [string]$PicardPath  = "C:\Program Files\MusicBrainz Picard\picard.exe",
    [string]$MusicDir    = "music_download",
    [int]   $TimeoutSec  = 600      # 10分で強制終了
)

$ErrorActionPreference = "Continue"
Set-Location -Path $PSScriptRoot

if (-not (Test-Path $PicardPath)) {
    Write-Host "エラー: Picard が見つかりません: $PicardPath" -ForegroundColor Red
    exit 1
}

# 二重起動チェック
$Running = Get-Process -Name "picard" -ErrorAction SilentlyContinue
if ($Running) {
    Write-Host "警告: Picard が既に起動しています。" -ForegroundColor Yellow
    Write-Host ("  起動中 PID: {0}" -f (($Running | ForEach-Object { $_.Id }) -join ", ")) -ForegroundColor Yellow
    exit 2
}

# ----------------------------------------
# music_download の絶対パスを解決
# ----------------------------------------
$musicDirAbs = if ([System.IO.Path]::IsPathRooted($MusicDir)) {
    $MusicDir
} else {
    Join-Path $PSScriptRoot $MusicDir
}

if (-not (Test-Path $musicDirAbs)) {
    Write-Host "  music_download が存在しないため Picard をスキップ" -ForegroundColor DarkGray
    exit 0
}

# Picard はスラッシュ区切りを好む
$musicDirPosix = $musicDirAbs -replace '\\', '/'

# ----------------------------------------
# picard_commands.txt を動的生成
# ----------------------------------------
# 重要: Picard の -e モードは "#" をコメントとして解釈しないため、
#       ファイルには「コマンドのみ」を記述する。コメントを入れると
#       "Unknown command: #" エラーになる。
#       また、BOM 付き UTF-8 で書くと先頭行の前に BOM が入り
#       同じエラーを誘発するため、BOM なし UTF-8 で書き込む。
# ----------------------------------------
$commandFile = Join-Path $PSScriptRoot "picard_commands.txt"

$commands = @"
LOAD $musicDirPosix
CLUSTER
LOOKUP
SAVE_MATCHED
REMOVE_SAVED
FINGERPRINT
SCAN
SAVE_MATCHED
REMOVE_SAVED
FINGERPRINT
SCAN
SAVE_MATCHED
REMOVE_SAVED
QUIT
"@

# 先頭・末尾の余分な改行を整理
$commands = $commands.Trim() + "`n"

# BOM なし UTF-8 で書き込み
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($commandFile, $commands, $utf8NoBom)

Write-Host "Picard を起動します..." -ForegroundColor Cyan
Write-Host "  実行ファイル: $PicardPath"
Write-Host "  対象フォルダ: $musicDirAbs"
Write-Host "  コマンドファイル: $commandFile"

# ----------------------------------------
# Picard 起動（タイムアウト付き）
# ----------------------------------------
$StartTime = Get-Date
$Proc = Start-Process -FilePath $PicardPath `
    -ArgumentList "-e", "FROM_FILE `"$commandFile`"" `
    -PassThru

# タイムアウト待機
$exited = $Proc.WaitForExit($TimeoutSec * 1000)

if (-not $exited) {
    Write-Host ("  ※ タイムアウト ({0}秒)。Picard を強制終了します。" -f $TimeoutSec) -ForegroundColor Yellow
    try { $Proc.Kill() } catch { }
    Start-Sleep -Seconds 2
}

$Elapsed = (Get-Date) - $StartTime

# 残存プロセスを掃除（念のため）
$still = Get-Process -Name "picard" -ErrorAction SilentlyContinue
if ($still) {
    Write-Host "  ※ 残存 Picard プロセスを終了します" -ForegroundColor Yellow
    $still | Stop-Process -Force -ErrorAction SilentlyContinue
}

Write-Host ("Picard が終了しました (所要時間={0:mm\:ss})" -f $Elapsed) -ForegroundColor Green
exit 0