# ========================================
# プレイリスト一括ダウンロード → Picard 自動整理（改良版 v2）
# ========================================
# 変更点:
#   - -StartIndex で途中再開に対応
#   - -Force でアーカイブ無視
#   - -SkipPicard で Picard 連携スキップ
#   - $Urls の配列化（1行CSV対応）
# ========================================

[CmdletBinding()]
param(
    [string]$PlaylistFile = "playlist.txt",
    [string]$OutputDir    = "music_download",
    [string]$ArchiveFile  = "downloaded_playlist.txt",
    [string]$FailLog      = "failed_playlist.log",
    [string]$SuccessLog   = "success_playlist.log",
    [int]   $SleepTime    = 5,
    [int]   $MaxRetries   = 2,
    [int]   $StartIndex   = 1,      # この行番号以降を処理
    [switch]$Force,                 # アーカイブ無視
    [switch]$SkipPicard             # Picard 連携スキップ
)

$ErrorActionPreference = "Continue"
Set-Location -Path $PSScriptRoot

# ========================================
# 事前チェック
# ========================================
if (-not (Test-Path $PlaylistFile)) {
    Write-Host "エラー: $PlaylistFile が見つかりません。" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

Write-Host "=== プレイリスト一括ダウンロード ===" -ForegroundColor Cyan
if ($StartIndex -gt 1) {
    Write-Host ("※ {0} 行目から処理を開始します" -f $StartIndex) -ForegroundColor Magenta
}
if ($Force) {
    Write-Host "※ -Force 指定: アーカイブを無視" -ForegroundColor Magenta
}
$StartTime = Get-Date

# ========================================
# 出力テンプレート & メタデータ設定
# ========================================
$OutputTemplate = "$OutputDir/%(playlist_index)02d %(artist,uploader,channel,creator)s - %(title)s.%(ext)s"
$ParseMetaArgs  = @("--parse-metadata", "%(artist,uploader,channel,creator)s:%(meta_artist)s")

# ========================================
# URL読み込み（@() で必ず配列化）
# ========================================
$Urls = @(Get-Content -Path $PlaylistFile -Encoding UTF8 |
    ForEach-Object { $_.TrimStart([char]0xFEFF) } |
    Where-Object {
        -not [string]::IsNullOrWhiteSpace($_) -and -not $_.TrimStart().StartsWith("#")
    } | ForEach-Object { $_.Trim() })

if ($Urls.Count -eq 0) {
    Write-Host "playlist.txt に有効なURLがありません。" -ForegroundColor Red
    exit 1
}

$Total        = $Urls.Count
$Index        = 0
$CountSuccess = 0
$CountFailed  = 0
$CountPartial = 0
$CountSkipped = 0

# ========================================
# メインループ
# ========================================
foreach ($Url in $Urls) {
    $Index++

    if ($Index -lt $StartIndex) {
        $CountSkipped++
        continue
    }

    Write-Host "----------------------------------------"
    Write-Host "[$Index/$Total] プレイリスト処理中" -ForegroundColor Yellow
    Write-Host "  URL: $Url" -ForegroundColor DarkGray

    if ($Url -notmatch '^https?://') {
        Write-Host "  -> URL形式ではありません。スキップ" -ForegroundColor Red
        "$Url,URL形式不正" | Add-Content -Path $FailLog -Encoding UTF8
        $CountFailed++
        continue
    }

    $Clients   = @("web_safari", "android", "ios", "tv_embedded", "")
    $Success   = $false
    $LastError = ""
    $HadErrors = $false

    foreach ($Client in $Clients) {
        if ($Success) { break }

        for ($Retry = 1; $Retry -le $MaxRetries; $Retry++) {
            if ($Client -eq "") {
                Write-Host "  -> [標準設定] 試行 $Retry/$MaxRetries..." -ForegroundColor Gray
                $ExtractorArgs = @()
            } else {
                Write-Host "  -> [$Client] 試行 $Retry/$MaxRetries..." -ForegroundColor Gray
                $ExtractorArgs = @("--extractor-args", "youtube:player_client=$Client")
            }

            $CommonArgs = @(
                "-x",
                "--audio-format", "mp3",
                "--audio-quality", "0",
                "--embed-metadata",
                "--embed-thumbnail",
                "--convert-thumbnails", "jpg",
                "--sponsorblock-remove", "music_offtopic",
                "--yes-playlist",
                "--ignore-errors",
                "--windows-filenames",
                "--retries", "5",
                "--fragment-retries", "5",
                "--retry-sleep", "linear=1:2:5",
                "-o", $OutputTemplate
            ) + $ParseMetaArgs

            # アーカイブは -Force 時のみ無効化
            if (-not $Force) {
                $CommonArgs = @("--download-archive", $ArchiveFile) + $CommonArgs
            }

            $AllArgs = $CommonArgs + $ExtractorArgs + @($Url)

            $YtOutput = & yt-dlp @AllArgs 2>&1 | Tee-Object -Variable YtLines
            $YtExit   = $LASTEXITCODE

            $ErrorCount = @($YtLines | Where-Object { "$_" -match '^\s*ERROR:' }).Count

            if ($YtExit -eq 0) {
                if ($ErrorCount -gt 0) {
                    Write-Host "  => 部分成功（$ErrorCount 件のエラーを検出）" -ForegroundColor DarkYellow
                    $HadErrors = $true
                } else {
                    Write-Host "  => 成功" -ForegroundColor Green
                }
                $Success = $true
                break
            } else {
                $LastError = "exit=$YtExit (client=$Client, retry=$Retry)"
                Write-Host "  => 失敗。リトライします..." -ForegroundColor DarkYellow
                Start-Sleep -Seconds 5
            }
        }
    }

    if ($Success -and -not $HadErrors) {
        $CountSuccess++
        "$Url" | Add-Content -Path $SuccessLog -Encoding UTF8
    } elseif ($Success -and $HadErrors) {
        $CountPartial++
        "$Url,部分成功(エラーあり)" | Add-Content -Path $FailLog -Encoding UTF8
    } else {
        $CountFailed++
        Write-Host "  => すべてのクライアントで失敗。失敗ログに記録します。" -ForegroundColor Red
        "$Url,$LastError" | Add-Content -Path $FailLog -Encoding UTF8
    }

    Start-Sleep -Seconds $SleepTime
}

# ========================================
# 完了サマリ & Picard 連携
# ========================================
$Elapsed = (Get-Date) - $StartTime
Write-Host "========================================"
Write-Host "すべての処理が完了しました。" -ForegroundColor Cyan
Write-Host ("成功: {0} / 部分成功: {1} / 失敗: {2} / スキップ: {3} / 合計: {4}" -f `
    $CountSuccess, $CountPartial, $CountFailed, $CountSkipped, $Total) -ForegroundColor Cyan
Write-Host ("所要時間: {0:hh\:mm\:ss}" -f $Elapsed) -ForegroundColor Cyan

if ($SkipPicard) {
    Write-Host "SkipPicard 指定のため、Picard 連携をスキップしました。" -ForegroundColor DarkGray
    exit 0
}

Write-Host "ダウンロード完了。Picardによる自動整理を開始します..." -ForegroundColor Cyan
& "$PSScriptRoot\run_picard.ps1"
$PicardExit = $LASTEXITCODE
if ($PicardExit -ne 0) {
    Write-Host "Picard が異常終了しました (exit=$PicardExit)" -ForegroundColor Red
    exit $PicardExit
}
Write-Host "Picardによる整理が完了しました。" -ForegroundColor Green
exit 0