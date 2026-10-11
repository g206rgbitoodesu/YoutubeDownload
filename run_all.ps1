# ========================================
# 統合フロー：ダウンロード → Picard → Navidrome
# ========================================
# 使い方:
#   .\run_all.ps1                    # CSV全体を処理
#   .\run_all.ps1 -StartFrom 6       # ステップ6から開始
#   .\run_all.ps1 -SkipSteps 3,4     # 3,4をスキップ
#   .\run_all.ps1 -DryRun            # 影響の大きいステップをDryRunで確認
# ========================================
[CmdletBinding()]
param(
    [ValidateSet("csv","playlist")]
    [string]$Source    = "csv",
    [string]$CsvFile   = "songlist.csv",
    [string]$PlaylistFile = "playlist.txt",
    [int[]] $SkipSteps = @(),
    [int]   $StartFrom = 1,
    [switch]$DryRun,
    [switch]$NoPause
)

$ErrorActionPreference = "Continue"
Set-Location -Path $PSScriptRoot

$TotalSteps = 9
$StepNames = @{
    1 = "CSV整形 (clean_songlist)"
    2 = "未DL抽出 (make_todo)"
    3 = "ダウンロード (download_pc)"
    4 = "検査 (verify_downloads)"
    5 = "再ダウンロード (redownload_failed)"
    6 = "Picard タグ付け (run_picard)"
    7 = "ファイル名整形 (clean_music_download)"
    8 = "Picard 再実行 (run_picard)"
    9 = "残りを移動 (move_leftovers)"
}

function Step-Header {
    param([int]$n, [string]$name)
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Magenta
    Write-Host ("  [{0}/{1}] {2}" -f $n, $TotalSteps, $name) -ForegroundColor Magenta
    Write-Host ("=" * 70) -ForegroundColor Magenta
}

function Skip-Check {
    param([int]$n)
    if ($n -lt $StartFrom) {
        Write-Host ("  ※ StartFrom={0} のためスキップ" -f $StartFrom) -ForegroundColor DarkGray
        return $true
    }
    if ($SkipSteps -contains $n) {
        Write-Host ("  ※ SkipSteps 指定のためスキップ") -ForegroundColor DarkGray
        return $true
    }
    return $false
}

function Pause-Step {
    if ($NoPause -or $DryRun) { return }
    Write-Host ""
    Write-Host "  続行しますか? (Enter で次へ / q で終了): " -ForegroundColor Yellow -NoNewline
    $ans = Read-Host
    if ($ans -eq "q") {
        Write-Host "  中断しました。" -ForegroundColor Red
        exit 0
    }
}

# ========================================
$flowStart = Get-Date
Write-Host ""
Write-Host ("#" * 70) -ForegroundColor Cyan
Write-Host ("#  統合フロー開始  " + $flowStart.ToString("yyyy-MM-dd HH:mm:ss")) -ForegroundColor Cyan
Write-Host ("#" * 70) -ForegroundColor Cyan
if ($DryRun) {
    Write-Host "  ★ DryRun モード（書き込み系は計画のみ）" -ForegroundColor Magenta
}

# ========================================
# [1] 入力整形（CSVのときだけ）
# ========================================
Step-Header 1 $StepNames[1]
if ($Source -eq "csv") {
    if (-not (Skip-Check 1)) {
        if ($DryRun) {
            Write-Host "  [DryRun] clean_songlist.ps1 -CsvFile $CsvFile -InPlace" -ForegroundColor Gray
        } else {
            & "$PSScriptRoot\clean_songlist.ps1" -CsvFile $CsvFile -InPlace
        }
    }
} else {
    Write-Host "  playlist モードのためスキップ" -ForegroundColor DarkGray
}

# ========================================
# [2] 未DL抽出（CSVのときだけ）
# ========================================
Step-Header 2 $StepNames[2]
if ($Source -eq "csv") {
    if (-not (Skip-Check 2)) {
        if ($DryRun) {
            Write-Host "  [DryRun] make_todo.ps1 -CsvFile $CsvFile" -ForegroundColor Gray
        } else {
            & "$PSScriptRoot\make_todo.ps1" -CsvFile $CsvFile -OutFile songlist_todo.csv
        }
    }
} else {
    Write-Host "  playlist モードのためスキップ（アーカイブでDL済みを自動スキップ）" -ForegroundColor DarkGray
}

# ========================================
# [3] ダウンロード（Picardスキップ）
# ========================================
Step-Header 3 $StepNames[3]
if (-not (Skip-Check 3)) {
    if ($DryRun) {
        if ($Source -eq "csv") {
            Write-Host "  [DryRun] download_pc.ps1 -CsvFile songlist_todo.csv -SkipPicard" -ForegroundColor Gray
        } else {
            Write-Host "  [DryRun] download_playlist.ps1 -PlaylistFile $PlaylistFile -SkipPicard" -ForegroundColor Gray
        }
    } else {
        if ($Source -eq "csv") {
            & "$PSScriptRoot\download_pc.ps1" -CsvFile songlist_todo.csv -SkipPicard
        } else {
            & "$PSScriptRoot\download_playlist.ps1" -PlaylistFile $PlaylistFile -SkipPicard
        }
    }
}

# ========================================
# [4] 検査
# ========================================
Step-Header 4 $StepNames[4]
$verifyExit = 0
if (-not (Skip-Check 4)) {
    if ($DryRun) {
        Write-Host "  [DryRun] verify_downloads.ps1" -ForegroundColor Gray
    } else {
        & "$PSScriptRoot\verify_downloads.ps1"
        $verifyExit = $LASTEXITCODE
    }
}

# ========================================
# [5] 再DL（NGがあれば）
# ========================================
Step-Header 5 $StepNames[5]
if (-not (Skip-Check 5)) {
    if ($verifyExit -eq 10 -or $DryRun) {
        if ($DryRun) {
            Write-Host "  [DryRun] redownload_failed.ps1" -ForegroundColor Gray
        } else {
            & "$PSScriptRoot\redownload_failed.ps1"
            Write-Host "  → 再検査" -ForegroundColor Cyan
            & "$PSScriptRoot\verify_downloads.ps1"
        }
    } else {
        Write-Host "  NG なし。スキップ。" -ForegroundColor Green
    }
}

# ========================================
# [6] Picard タグ付け（1回目）
# ========================================
Step-Header 6 $StepNames[6]
if (-not (Skip-Check 6)) {
    if ($DryRun) {
        Write-Host "  [DryRun] run_picard.ps1" -ForegroundColor Gray
    } else {
        & "$PSScriptRoot\run_picard.ps1"
    }
}

# ========================================
# [7] ファイル名整形
# ========================================
Step-Header 7 $StepNames[7]
if (-not (Skip-Check 7)) {
    $cdArgs = @{}
    if ($DryRun) { $cdArgs["DryRun"] = $true }
    & "$PSScriptRoot\clean_music_download.ps1" @cdArgs
}

# ========================================
# [8] Picard 再実行（クリーンなファイル名で再マッチ）
# ========================================
Step-Header 8 $StepNames[8]
if (-not (Skip-Check 8)) {
    if ($DryRun) {
        Write-Host "  [DryRun] run_picard.ps1 (再)" -ForegroundColor Gray
    } else {
        $leftover = Get-ChildItem -Path "music_download" -Recurse -File -Include *.mp3 -ErrorAction SilentlyContinue
        if (@($leftover).Count -gt 0) {
            Write-Host ("  残り {0} ファイルを再マッチング" -f @($leftover).Count) -ForegroundColor Cyan
            & "$PSScriptRoot\run_picard.ps1"
            if ($LASTEXITCODE -eq 2) {
                Write-Host "  ※ Picard が起動中のため再マッチをスキップしました" -ForegroundColor Yellow
            } elseif ($LASTEXITCODE -ne 0) {
                Write-Host ("  ※ Picard が異常終了 (exit={0})" -f $LASTEXITCODE) -ForegroundColor Red
            }
        } else {
            Write-Host "  music_download は空。スキップ。" -ForegroundColor Green
        }
    }
}

# ========================================
# [9] 残りを Navidrome へ直接移動
# ========================================
Step-Header 9 $StepNames[9]
if (-not (Skip-Check 9)) {
    $mlArgs = @{ Force = $true }
    if ($DryRun) { $mlArgs["DryRun"] = $true }
    & "$PSScriptRoot\move_leftovers.ps1" @mlArgs
}

# ========================================
# 完了サマリ
# ========================================
$flowElapsed = (Get-Date) - $flowStart
Write-Host ""
Write-Host ("#" * 70) -ForegroundColor Cyan
Write-Host ("#  統合フロー完了  所要時間 {0:hh\:mm\:ss}" -f $flowElapsed) -ForegroundColor Cyan
Write-Host ("#" * 70) -ForegroundColor Cyan
Write-Host ""

Write-Host "  最終状態:" -ForegroundColor Yellow
$left = @(Get-ChildItem -Path "music_download" -Recurse -File -Include *.mp3,*.m4a,*.flac,*.opus -ErrorAction SilentlyContinue).Count
Write-Host ("    music_download: {0} ファイル" -f $left)
$naviCount = @(Get-ChildItem -Path "$env:USERPROFILE\Downloads\navidrome\music" -Recurse -File -ErrorAction SilentlyContinue).Count
Write-Host ("    Navidrome music: {0} ファイル" -f $naviCount)
Write-Host ""
Write-Host "  ★ Navidrome で Quick scan を忘れずに実行してください ★" -ForegroundColor Magenta
Write-Host ""