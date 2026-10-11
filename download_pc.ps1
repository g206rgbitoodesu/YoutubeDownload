# ========================================
# CSV一括ダウンロード → Picard 自動整理（改良版 v2）
# ========================================
# 変更点:
#   - --parse-metadata の左辺を正しいフィールド参照に修正（artist=NA 問題の解決）
#   - -StartIndex で途中再開に対応
#   - -Force でアーカイブを無視した強制DL（再DL用）
#   - Picard の終了コードを親プロセスで正しく判定
# ========================================

[CmdletBinding()]
param(
    [string]$CsvFile     = "songlist.csv",
    [string]$OutputDir   = "music_download",
    [string]$ArchiveFile = "downloaded.txt",
    [string]$FailLog     = "failed.log",
    [string]$SuccessLog  = "success.log",
    [int]   $SleepTime   = 5,
    [int]   $MaxRetries  = 2,
    [int]   $StartIndex  = 1,      # この行番号以降を処理（1始まり）
    [switch]$Force,                # アーカイブ無視で強制再DL
    [switch]$SkipPicard            # Picard 連携をスキップ
)

$ErrorActionPreference = "Continue"
Set-Location -Path $PSScriptRoot

# ========================================
# 事前チェック
# ========================================
if (-not (Test-Path $CsvFile)) {
    Write-Host "エラー: $CsvFile が見つかりません。" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

Write-Host "=== CSV一括ダウンロード ===" -ForegroundColor Cyan
if ($StartIndex -gt 1) {
    Write-Host ("※ {0} 行目から処理を開始します（1〜{1} 行目はスキップ）" -f $StartIndex, ($StartIndex - 1)) -ForegroundColor Magenta
}
if ($Force) {
    Write-Host "※ -Force 指定: アーカイブを無視して強制ダウンロードします" -ForegroundColor Magenta
}
$StartTime = Get-Date


# ========================================
# CSV読み込み（BOM/空行/コメント対応）
# ========================================
$RawLines = @(Get-Content -Path $CsvFile -Encoding UTF8 | Where-Object {
    -not [string]::IsNullOrWhiteSpace($_) -and -not $_.TrimStart().StartsWith("#")
})

if ($RawLines.Count -eq 0) {
    Write-Host "CSVにデータがありません。" -ForegroundColor Red
    exit 1
}

# BOM が残っている場合の対策（@() で再度配列化：1行CSVでも文字列化しない）
$RawLines = @($RawLines | ForEach-Object { $_.TrimStart([char]0xFEFF) })

$FirstLine = $RawLines[0]
$IsHeader  = $FirstLine -match '(アーティスト|Artist|曲名|タイトル|Title|Song|URL|Url|Link)'

$DataLines = if ($IsHeader) { $RawLines | Select-Object -Skip 1 } else { $RawLines }

# ========================================
# CSV パース（ダブルクォート対応）
# ========================================
function ConvertFrom-CsvLine {
    param([string]$Line)
    $fields = @()
    $current = ""
    $inQuote = $false
    for ($i = 0; $i -lt $Line.Length; $i++) {
        $c = $Line[$i]
        if ($c -eq '"') {
            if ($inQuote -and ($i + 1) -lt $Line.Length -and $Line[$i + 1] -eq '"') {
                $current += '"'; $i++
            } else {
                $inQuote = -not $inQuote
            }
        } elseif ($c -eq ',' -and -not $inQuote) {
            $fields += $current; $current = ""
        } else {
            $current += $c
        }
    }
    $fields += $current
    return $fields
}

$Rows = foreach ($line in $DataLines) {
    $fields = ConvertFrom-CsvLine -Line $line
    [PSCustomObject]@{
        Artist = if ($fields.Count -ge 1) { $fields[0].Trim() } else { "" }
        Title  = if ($fields.Count -ge 2) { $fields[1].Trim() } else { "" }
        Url    = if ($fields.Count -ge 3) { $fields[2].Trim() } else { "" }
    }
}

$Total        = @($Rows).Count
$Index        = 0
$CountSuccess = 0
$CountFailed  = 0
$CountSkipped = 0

# ========================================
# メインループ
# ========================================
foreach ($Row in $Rows) {
    $Index++

    # -StartIndex より前はスキップ
    if ($Index -lt $StartIndex) {
        $CountSkipped++
        continue
    }

    $CsvArtist = $Row.Artist
    $CsvTitle  = $Row.Title
    $CsvUrl    = $Row.Url

    if ([string]::IsNullOrWhiteSpace($CsvTitle) -and [string]::IsNullOrWhiteSpace($CsvUrl)) {
        $CountSkipped++
        continue
    }

    $Label = if ($CsvArtist) { "$CsvArtist - $CsvTitle" } else { $CsvTitle }
    Write-Host "----------------------------------------"
    Write-Host "[$Index/$Total] 処理中: $Label" -ForegroundColor Yellow

    # ダウンロード対象を決定
    if (-not [string]::IsNullOrWhiteSpace($CsvUrl) -and $CsvUrl -match '^https?://') {
        $Target = $CsvUrl
    } elseif (-not [string]::IsNullOrWhiteSpace($CsvArtist) -and -not [string]::IsNullOrWhiteSpace($CsvTitle)) {
        $Target = "ytsearch1:$CsvArtist $CsvTitle"
    } elseif (-not [string]::IsNullOrWhiteSpace($CsvTitle)) {
        $Target = "ytsearch1:$CsvTitle"
    } else {
        $CountFailed++
        continue
    }

    # ========================================
    # 出力テンプレート & メタデータ設定
    # ========================================
    # 【重要】--parse-metadata の左辺は「フィールド名」を書く場所。
    #   旧コード: "${CsvArtist}:%(meta_artist)s"  → '%(Queen)s' と解釈され NA になる
    #   新コード: "%(artist,uploader,channel,creator)s:%(meta_artist)s"
    #             → YouTube メタデータから artist を取得して meta_artist にコピー
    #   CSV のアーティスト名は「ファイル名」と「Picard/enrich_tags での補完」に使う。
    if (-not [string]::IsNullOrWhiteSpace($CsvArtist)) {
        $OutputTemplate = "$OutputDir/$CsvArtist - %(title)s.%(ext)s"
    } else {
        $OutputTemplate = "$OutputDir/%(artist,uploader,channel,creator)s - %(title)s.%(ext)s"
    }
    $ParseMetaArgs = @("--parse-metadata", "%(artist,uploader,channel,creator)s:%(meta_artist)s")

    $Clients   = @("web_safari", "android", "ios", "tv_embedded", "")
    $Success   = $false
    $LastError = ""

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
                "--no-playlist",
                "--windows-filenames",
                "--retries", "5",
                "--fragment-retries", "5",
                "--retry-sleep", "linear=1:2:5",
                "-o", $OutputTemplate
            ) + $ParseMetaArgs

            # アーカイブは -Force 指定時のみ無効化
            if (-not $Force) {
                $CommonArgs = @("--download-archive", $ArchiveFile) + $CommonArgs
            }

            $AllArgs = $CommonArgs + $ExtractorArgs + @($Target)
            & yt-dlp @AllArgs

            if ($LASTEXITCODE -eq 0) {
                Write-Host "  => 成功" -ForegroundColor Green
                $Success = $true
                break
            } else {
                $LastError = "exit=$LASTEXITCODE (client=$Client, retry=$Retry)"
                Write-Host "  => 失敗。リトライします..." -ForegroundColor DarkYellow
                Start-Sleep -Seconds 5
            }
        }
    }

    if ($Success) {
        $CountSuccess++
        "$CsvArtist,$CsvTitle,$CsvUrl" | Add-Content -Path $SuccessLog -Encoding UTF8
    } else {
        $CountFailed++
        Write-Host "  => すべてのクライアントで失敗。失敗ログに記録します。" -ForegroundColor Red
        "$CsvArtist,$CsvTitle,$CsvUrl,$LastError" | Add-Content -Path $FailLog -Encoding UTF8
    }

    Start-Sleep -Seconds $SleepTime
}

# ========================================
# 完了サマリ & Picard 連携
# ========================================
$Elapsed = (Get-Date) - $StartTime
Write-Host "========================================"
Write-Host "すべての処理が完了しました。" -ForegroundColor Cyan
Write-Host ("成功: {0} / 失敗: {1} / スキップ: {2} / 合計: {3}" -f $CountSuccess, $CountFailed, $CountSkipped, $Total) -ForegroundColor Cyan
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