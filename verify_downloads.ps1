# ========================================
# ダウンロード整合性検査（ffprobe 使用）
# ========================================
[CmdletBinding()]
param(
    [string]$TargetDir   = "music_download",
    [int]   $MinDuration = 30,
    [int]   $MinBitrate  = 64,
    [int]   $MinSizeKB   = 100,
    [string]$OkFile      = "verify_ok.txt",
    [string]$NgFile      = "verify_ng.txt"
)

$ErrorActionPreference = "Continue"
Set-Location -Path $PSScriptRoot

if (-not (Test-Path $TargetDir)) {
    Write-Host "エラー: $TargetDir が見つかりません。" -ForegroundColor Red
    exit 1
}
if (-not (Get-Command ffprobe -ErrorAction SilentlyContinue)) {
    Write-Host "エラー: ffprobe が見つかりません。" -ForegroundColor Red
    exit 1
}

Write-Host "=== ダウンロード検査 ===" -ForegroundColor Cyan
$absDir = (Resolve-Path $TargetDir).Path
Write-Host "対象: $absDir"

"path,artist,title,duration,bitrate,size_kb" | Set-Content -Path $OkFile -Encoding UTF8
"path,artist,title,reason"                  | Set-Content -Path $NgFile -Encoding UTF8

$files = Get-ChildItem -Path $TargetDir -Recurse -File -Include *.mp3,*.m4a,*.flac,*.opus
$total = @($files).Count
Write-Host "検査対象: $total ファイル" -ForegroundColor Cyan

$okCount = 0; $ngCount = 0; $idx = 0

foreach ($f in $files) {
    $idx++
    $rel = $f.FullName.Substring($absDir.Length + 1)

    $json = & ffprobe -v quiet -print_format json -show_format $f.FullName 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $json) {
        Write-Host ("  [{0}/{1}] NG (decode失敗): {2}" -f $idx,$total,$rel) -ForegroundColor Red
        "`"$rel`",,,ffprobe_decode_error" | Add-Content -Path $NgFile -Encoding UTF8
        $ngCount++; continue
    }

    try { $info = $json | ConvertFrom-Json } catch {
        "`"$rel`",,,json_parse_error" | Add-Content -Path $NgFile -Encoding UTF8
        $ngCount++; continue
    }

    $duration = [double]$info.format.duration
    $bitrate  = [int]([double]$info.format.bit_rate / 1000)
    $sizeKB   = [int]($f.Length / 1KB)

    $artist = ""; $title = ""
    if ($info.format.tags) {
        foreach ($k in $info.format.tags.PSObject.Properties.Name) {
            $lk = $k.ToLower()
            if ($lk -in @("artist","album_artist","albumartist")) { $artist = $info.format.tags.$k }
            if ($lk -eq "title") { $title = $info.format.tags.$k }
        }
    }

    $reasons = @()
    if ($duration -lt $MinDuration) { $reasons += "duration=${duration}s" }
    if ($bitrate  -lt $MinBitrate)  { $reasons += "bitrate=${bitrate}kbps" }
    if ($sizeKB   -lt $MinSizeKB)   { $reasons += "size=${sizeKB}KB" }
    if ($title -eq "NA")            { $reasons += "title_NA" }
    if ($artist -eq "NA")           { $reasons += "artist_NA" }

    if ($reasons.Count -gt 0) {
        Write-Host ("  [{0}/{1}] NG: {2}  ({3})" -f $idx,$total,$rel,($reasons -join "; ")) -ForegroundColor Red
        "`"$rel`",`"$artist`",`"$title`",`"$($reasons -join '; ')`"" | Add-Content -Path $NgFile -Encoding UTF8
        $ngCount++
    } else {
        Write-Host ("  [{0}/{1}] OK: {2}" -f $idx,$total,$rel) -ForegroundColor Green
        "`"$rel`",`"$artist`",`"$title`",$duration,$bitrate,$sizeKB" | Add-Content -Path $OkFile -Encoding UTF8
        $okCount++
    }
}

Write-Host "========================================"
Write-Host "検査完了" -ForegroundColor Cyan
Write-Host ("  OK: {0} / NG: {1} / 合計: {2}" -f $okCount, $ngCount, $total)
Write-Host ("  OK: $OkFile  / NG: $NgFile")

if ($ngCount -gt 0) { exit 10 } else { exit 0 }