# ========================================
# Picard 自動整理スクリプト（改良版 v2）
# ========================================
[CmdletBinding()]
param(
    [string]$PicardPath  = "C:\Program Files\MusicBrainz Picard\picard.exe",
    [string]$CommandFile = "$PSScriptRoot\picard_commands.txt"
)

$ErrorActionPreference = "Continue"

if (-not (Test-Path $PicardPath)) {
    Write-Host "エラー: Picard が見つかりません: $PicardPath" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $CommandFile)) {
    Write-Host "エラー: コマンドファイルが見つかりません: $CommandFile" -ForegroundColor Red
    exit 1
}

# 二重起動チェック
$Running = Get-Process -Name "picard" -ErrorAction SilentlyContinue
if ($Running) {
    Write-Host "警告: Picard が既に起動しています。" -ForegroundColor Yellow
    Write-Host ("  起動中 PID: {0}" -f (($Running | ForEach-Object { $_.Id }) -join ", ")) -ForegroundColor Yellow
    exit 2
}

Write-Host "Picard を起動します..." -ForegroundColor Cyan
Write-Host "  実行ファイル    : $PicardPath"
Write-Host "  コマンドファイル: $CommandFile"

$StartTime = Get-Date
$Proc = Start-Process -FilePath $PicardPath `
    -ArgumentList "-e", "FROM_FILE `"$CommandFile`"" `
    -PassThru -Wait
$Elapsed = (Get-Date) - $StartTime

$ExitCode = $Proc.ExitCode
Write-Host ("Picard が終了しました (exit={0}, 所要時間={1:mm\:ss})" -f $ExitCode, $Elapsed) -ForegroundColor Green

if ($ExitCode -ne 0) {
    Write-Host "Picard が異常終了しました (exit=$ExitCode)" -ForegroundColor Red
}
exit $ExitCode