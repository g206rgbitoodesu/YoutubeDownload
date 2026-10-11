# ========================================
# ⚠ 非推奨: run_all.ps1 を使用してください
# ========================================
# 本スクリプトは後方互換のための薄いラッパーです。
# 実体は run_all.ps1 に統合されました。
#
# 旧 → 新 パラメータマッピング:
#   -Source csv       → そのまま
#   -Source playlist  → そのまま
#   -SkipDownload     → -SkipSteps 1,2,3
#   -SkipVerify       → -SkipSteps 4,5
#   -SkipRedownload   → -SkipSteps 5
#   -SkipPicard       → -SkipSteps 6,8
#   -SkipEnrich       → (run_all に直接対応なし。無視)
#
# 推奨:
#   .\run_all.ps1                    # 全9ステップ
#   .\run_all.ps1 -StartFrom 6       # ステップ6から
#   .\run_all.ps1 -SkipSteps 3,4     # 個別スキップ
# ========================================
[CmdletBinding()]
param(
    [ValidateSet("csv","playlist")]
    [string]$Source = "csv",
    [string]$CsvFile = "songlist.csv",
    [switch]$SkipDownload,
    [switch]$SkipVerify,
    [switch]$SkipRedownload,
    [switch]$SkipPicard,
    [switch]$SkipEnrich,
    [switch]$Quiet          # 非推奨警告を抑制
)

$ErrorActionPreference = "Continue"
Set-Location -Path $PSScriptRoot

# ========================================
# 非推奨警告
# ========================================
if (-not $Quiet) {
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Yellow
    Write-Host "  ⚠ pipeline.ps1 は非推奨です" -ForegroundColor Yellow
    Write-Host ("=" * 60) -ForegroundColor Yellow
    Write-Host "  次回からは .\run_all.ps1 を使用してください。" -ForegroundColor Yellow
    Write-Host "  本スクリプトは run_all.ps1 に転送します。" -ForegroundColor Gray
    Write-Host ("=" * 60) -ForegroundColor Yellow
    Write-Host ""
}

# ========================================
# 旧 → 新 パラメータ変換
# ========================================
$skipSteps = New-Object System.Collections.Generic.List[int]

if ($SkipDownload)   { $skipSteps.AddRange(@(1, 2, 3)) }
if ($SkipVerify)     { $skipSteps.AddRange(@(4, 5)) }
if ($SkipRedownload) { $skipSteps.Add(5) }
if ($SkipPicard)     { $skipSteps.AddRange(@(6, 8)) }
if ($SkipEnrich) {
    # run_all.ps1 に独立した enrich ステップはない
    # （enrich_tags.ps1 は move_leftovers と役割が近いが別物）
    Write-Host "  [INFO] -SkipEnrich は run_all.ps1 に対応する独立ステップがありません（無視）" -ForegroundColor DarkGray
}

$skipArray = @($skipSteps | Select-Object -Unique | Sort-Object)

# ========================================
# run_all.ps1 に転送
# ========================================
$runAll = Join-Path $PSScriptRoot "run_all.ps1"
if (-not (Test-Path $runAll)) {
    Write-Host "エラー: run_all.ps1 が見つかりません: $runAll" -ForegroundColor Red
    exit 1
}

Write-Host "  → run_all.ps1 を実行" -ForegroundColor Cyan
Write-Host ("     Source    : {0}" -f $Source) -ForegroundColor DarkGray
Write-Host ("     CsvFile   : {0}" -f $CsvFile) -ForegroundColor DarkGray
if ($skipArray.Count -gt 0) {
    Write-Host ("     SkipSteps : {0}" -f ($skipArray -join ", ")) -ForegroundColor DarkGray
}
Write-Host ""

# パラメータ組み立て
$runArgs = @{
    Source  = $Source
    CsvFile = $CsvFile
    NoPause = $true
}
if ($skipArray.Count -gt 0) {
    $runArgs["SkipSteps"] = $skipArray
}

& $runAll @runArgs
exit $LASTEXITCODE