# ========================================
# NA タグを songlist.csv の情報で補完
# ========================================
[CmdletBinding()]
param(
    [string]$CsvFile     = "songlist.csv",
    [string[]]$ScanFolders = @(
        "music_download",
        "$env:USERPROFILE\Downloads\navidrome\music"
    ),
    [switch]$DryRun
)

$ErrorActionPreference = "Continue"
Set-Location -Path $PSScriptRoot

if (-not (Test-Path $CsvFile)) { Write-Host "CSV なし" -ForegroundColor Red; exit 1 }

# ----------------------------------------
# タイトル正規化キー生成
# ----------------------------------------
function Get-Key {
    param([string]$s)
    if ([string]::IsNullOrEmpty($s)) { return "" }
    $t = $s.ToLowerInvariant()
    $pattern = @'
[\s\.\,\!\?'"\-_\(\)\[\]\{\}、。！？・「」『』【】]
'@
    return ($t -replace $pattern, '')
}

# ----------------------------------------
# CSV を辞書化（タイトルの正規化キー → artist/title）
# ----------------------------------------
$csvMap = @{}
$rows = @(Import-Csv -Path $CsvFile -Encoding UTF8)
foreach ($r in $rows) {
    $k = Get-Key $r.'曲名'
    if ($k) { $csvMap[$k] = @{ Artist = $r.'アーティスト'; Title = $r.'曲名' } }
}
Write-Host ("CSV登録曲: {0}" -f $csvMap.Count) -ForegroundColor Cyan

$scanned = 0; $fixed = 0; $left = 0

foreach ($dir in $ScanFolders) {
    if (-not (Test-Path $dir)) { continue }
    Get-ChildItem -Path $dir -Recurse -File -Include *.mp3 | ForEach-Object {
        $scanned++
        $file = $_.FullName
        $json = & ffprobe -v quiet -print_format json -show_format $file 2>$null | ConvertFrom-Json
        $artist = $json.format.tags.artist
        $title  = $json.format.tags.title

        $needsFix = ($artist -eq "NA" -or [string]::IsNullOrWhiteSpace($artist) `
                     -or $title -eq "NA" -or [string]::IsNullOrWhiteSpace($title))
        if (-not $needsFix) { return }

        # ファイル名からタイトル推定
        $base  = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
        $clean = $base -replace '^\d+\s+', ''
        $clean = $clean -replace '\s*\[[^\]]*\]', ''
        $clean = $clean -replace '\s*\([^)]*\)', ''

        $key = Get-Key ($clean -replace '^.*?-\s*','')
        $newArtist = $null; $newTitle = $null

        if ($csvMap.ContainsKey($key)) {
            $newArtist = $csvMap[$key].Artist
            $newTitle  = $csvMap[$key].Title
        } elseif ($title -eq "NA" -and $clean) {
            $newTitle = ($clean -replace '^.*?-\s*','').Trim()
        }

        if (-not $newArtist -and -not $newTitle) { $left++; return }

        Write-Host ("修正: {0}  → artist={1} / title={2}" -f $_.Name, $newArtist, $newTitle) -ForegroundColor Yellow

        if ($DryRun) { $fixed++; return }

        # ★ $args を $ffArgs にリネーム（PowerShell 自動変数との衝突回避）
        $ffArgs = @("-y","-i",$file,"-c","copy","-map_metadata","0")
        if ($newArtist) { $ffArgs += @("-metadata", "artist=$newArtist") }
        if ($newTitle)  { $ffArgs += @("-metadata", "title=$newTitle") }
        $tmp = "$file.enrich.tmp.mp3"
        $ffArgs += $tmp

        & ffmpeg @ffArgs 2>$null
        if ($LASTEXITCODE -eq 0) {
            Move-Item -LiteralPath $tmp -Destination $file -Force
            $fixed++
        } else {
            Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
            Write-Host "  ffmpeg失敗" -ForegroundColor Red
        }
    }
}

Write-Host "========================================"
Write-Host ("スキャン: {0} / 修正: {1} / 保留: {2}" -f $scanned, $fixed, $left) -ForegroundColor Cyan
if ($DryRun) { Write-Host "※ DryRun モード（実際には書き込みしていません）" -ForegroundColor Magenta }