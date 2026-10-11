# ========================================
# ⚠ 非推奨: run_all.ps1 を使用してください
# ========================================
# このスクリプトは旧版です。以下を推奨します:
#   .\run_all.ps1           # 9ステップ統合フロー
#   .\run_all.ps1 -StartFrom 6
# 本ファイルは互換性維持のため残置しています。
# ========================================
# ========================================
# フルパイプライン
#   DL → 検査 → 再DL → Picard → タグ補完
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
    [switch]$SkipEnrich
)

$ErrorActionPreference = "Continue"
Set-Location -Path $PSScriptRoot

$sw = [System.Diagnostics.Stopwatch]::StartNew()
Write-Host "========== パイプライン開始 ==========" -ForegroundColor Magenta

# [1] DL
if (-not $SkipDownload) {
    Write-Host "`n[1/5] ダウンロード" -ForegroundColor Magenta
    if ($Source -eq "csv") {
        & .\download_pc.ps1 -CsvFile $CsvFile -SkipPicard
    } else {
        & .\download_playlist.ps1
    }
}

# [2] 検査
$verifyExit = 0
if (-not $SkipVerify) {
    Write-Host "`n[2/5] 検査" -ForegroundColor Magenta
    & .\verify_downloads.ps1
    $verifyExit = $LASTEXITCODE
}

# [3] 再DL
if (-not $SkipRedownload) {
    Write-Host "`n[3/5] 再ダウンロード" -ForegroundColor Magenta
    if ($verifyExit -eq 10) {
        & .\redownload_failed.ps1
        # 再DL後に再検査
        Write-Host "`n[3.5/5] 再検査" -ForegroundColor Magenta
        & .\verify_downloads.ps1
    } else {
        Write-Host "  NG なし。スキップ。" -ForegroundColor Green
    }
}

# [4] Picard
if (-not $SkipPicard) {
    Write-Host "`n[4/5] Picard タグ付け・移動" -ForegroundColor Magenta
    & .\run_picard.ps1
}

# [5] タグ補完
if (-not $SkipEnrich) {
    Write-Host "`n[5/5] タグ補完" -ForegroundColor Magenta
    & .\enrich_tags.ps1
}

$sw.Stop()
Write-Host "`n========== 完了 ({0:hh\:mm\:ss}) ==========" -f $sw.Elapsed -ForegroundColor Magenta