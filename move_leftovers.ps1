# ========================================
# music_download に残った曲を Navidrome へ直接移動
# ========================================
# 動作:
#   - 各ファイルのタグ（artist, album, title）を ffprobe で取得
#   - artist/album/title の形で Navidrome music フォルダへ移動
#   - タグが不完全ならファイル名 "Artist - Title" から推定
#   - 同名ファイルが存在する場合は " (1)" を付けて退避
# ========================================
# v2:
#   - music_download が存在しない場合を「Picard が全て移動済み」と
#     みなして正常終了扱いに変更（エラー扱いをやめた）
# ========================================
[CmdletBinding()]
param(
    [string]$SourceDir  = "music_download",
    [string]$DestDir = "$env:USERPROFILE\Downloads\navidrome\music",
    [switch]$DryRun,
    [switch]$Force
)

$ErrorActionPreference = "Continue"
Set-Location -Path $PSScriptRoot

function Write-OK   { param([string]$m) Write-Host "  [OK]   $m" -ForegroundColor Green }
function Write-Move { param([string]$m) Write-Host "  [MOVE] $m" -ForegroundColor Yellow }
function Write-Warn { param([string]$m) Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function Write-Info { param([string]$m) Write-Host "  [INFO] $m" -ForegroundColor Gray }

# ファイル名の不正文字を除去
function Get-SafeFileName {
    param([string]$s)
    if ([string]::IsNullOrWhiteSpace($s)) { return "Unknown" }
    $bad = [System.IO.Path]::GetInvalidFileNameChars() -join ''
    $s = $s -replace "[$bad]", '_'
    return $s.Trim(' ', '.', '_')
}

# ファイル名から "Artist - Title" を推定
function Split-ArtistTitle {
    param([string]$BaseName)
    # 先頭の連番除去
    $b = $BaseName -replace '^\d+\s+', ''
    # 装飾除去（clean_music_download と同等）
    $b = $b -replace '\s*\([^)]*\)', ''
    $b = $b -replace '\s*\[[^\]]*\]', ''
    $b = $b -replace '\s*【[^】]*】', ''
    $b = $b -replace '\s*「[^」]*」', ''
    $b = $b -replace '\s*＂[^＂]*＂', ''
    $b = $b -replace '\s*-Music Video-', ''
    $b = $b -replace '⧸\s*', ''
    $b = ($b -replace '\s{2,}', ' ').Trim(' ', '-', '_', '.', '　')

    # "Artist - Title" 分割
    $idx = $b.IndexOf(' - ')
    if ($idx -ge 0) {
        return @{ Artist = $b.Substring(0, $idx).Trim(); Title = $b.Substring($idx + 3).Trim() }
    }
    return @{ Artist = "Unknown Artist"; Title = $b }
}

# ========================================
# 事前チェック
# ========================================
Write-Host ""
Write-Host "=== music_download → Navidrome 移動 ===" -ForegroundColor Magenta
Write-Host ""

if (-not (Test-Path $SourceDir)) {
    # Picard が全て移動済みの場合は music_download 自体が無くなる。
    # これは正常な状態なので、エラーではなくスキップとして扱う。
    Write-Host "  $SourceDir は存在しません（Picard が全て移動済みの可能性）" -ForegroundColor DarkGray
    Write-Host "  → 移動処理をスキップします" -ForegroundColor DarkGray
    exit 0
}

if (-not (Test-Path $DestDir)) {
    if ($DryRun) {
        Write-Host "  [DryRun] $DestDir は存在しません（本実行時はスキップされます）" -ForegroundColor Gray
        exit 0
    }
    Write-Host "エラー: $DestDir が見つかりません。" -ForegroundColor Red
    exit 1
}

if (-not (Get-Command ffprobe -ErrorAction SilentlyContinue)) {
    Write-Host "エラー: ffprobe が見つかりません。" -ForegroundColor Red
    exit 1
}

$absSrc = (Resolve-Path $SourceDir).Path
$absDst = (Resolve-Path $DestDir).Path
Write-Info ("移動元: {0}" -f $absSrc)
Write-Info ("移動先: {0}" -f $absDst)
if ($DryRun) { Write-Host "  ★ DryRun モード" -ForegroundColor Magenta }

# ========================================
# 対象ファイル列挙
# ========================================
$files = @(Get-ChildItem -Recurse -Path $absSrc -File -Include *.mp3,*.m4a,*.flac,*.opus)
Write-Host ""
Write-Info ("対象: {0} ファイル" -f $files.Count)

if ($files.Count -eq 0) {
    Write-Host ""
    Write-Host "移動対象はありません。" -ForegroundColor Green
    exit 0
}

# ========================================
# 計画作成
# ========================================
$plan = New-Object System.Collections.Generic.List[object]

foreach ($f in $files) {
    # タグ取得
    $artist = ""; $album = ""; $title = ""
    $json = & ffprobe -v quiet -print_format json -show_format $f.FullName 2>$null
    if ($LASTEXITCODE -eq 0 -and $json) {
        try {
            $info = $json | ConvertFrom-Json
            if ($info.format.tags) {
                foreach ($k in $info.format.tags.PSObject.Properties.Name) {
                    $lk = $k.ToLower()
                    $v = $info.format.tags.$k
                    if ($v -eq "NA" -or [string]::IsNullOrWhiteSpace($v)) { continue }
                    if ($lk -in @("artist","album_artist","albumartist") -and -not $artist) { $artist = $v }
                    if ($lk -eq "album" -and -not $album) { $album = $v }
                    if ($lk -eq "title" -and -not $title) { $title = $v }
                }
            }
        } catch { }
    }

    # タグが不完全な場合はファイル名から推定
    if ([string]::IsNullOrWhiteSpace($artist) -or [string]::IsNullOrWhiteSpace($title)) {
        $guess = Split-ArtistTitle -BaseName ([System.IO.Path]::GetFileNameWithoutExtension($f.Name))
        if ([string]::IsNullOrWhiteSpace($artist)) { $artist = $guess.Artist }
        if ([string]::IsNullOrWhiteSpace($title))  { $title  = $guess.Title }
    }
    if ([string]::IsNullOrWhiteSpace($album)) { $album = $title }

    $artist = Get-SafeFileName $artist
    $album  = Get-SafeFileName $album
    $title  = Get-SafeFileName $title

    $destDir  = Join-Path (Join-Path $absDst $artist) $album
    $destName = "$title$($f.Extension)"
    $destPath = Join-Path $destDir $destName

    # 衝突回避
    if (Test-Path $destPath) {
        $n = 1
        do {
            $destName = "$title ($n)$($f.Extension)"
            $destPath = Join-Path $destDir $destName
            $n++
        } while (Test-Path $destPath)
    }

    $plan.Add([PSCustomObject]@{
        Src      = $f.FullName
        SrcName  = $f.Name
        DestPath = $destPath
        DestDir  = $destDir
        Artist   = $artist
        Album    = $album
        Title    = $title
    })
}

# ========================================
# DryRun なら表示のみ
# ========================================
if ($DryRun) {
    Write-Host ""
    Write-Host "--- 移動計画 ---" -ForegroundColor Cyan
    foreach ($p in $plan) {
        Write-Move ("{0}" -f $p.SrcName)
        Write-Info ("     → {0}\{1}\{2}" -f $p.Artist, $p.Album, (Split-Path $p.DestPath -Leaf))
    }
    Write-Host ""
    Write-Host ("合計 {0} ファイルを移動します。" -f $plan.Count) -ForegroundColor Yellow
    exit 0
}

# ========================================
# 確認プロンプト
# ========================================
if (-not $Force) {
    Write-Host ""
    Write-Host ("{0} ファイルを Navidrome へ移動します。よろしいですか? (y/N): " -f $plan.Count) -ForegroundColor Yellow -NoNewline
    $answer = Read-Host
    if ($answer -notmatch '^[yY]') {
        Write-Host "中断しました。" -ForegroundColor Red
        exit 0
    }
}

# ========================================
# 実行
# ========================================
Write-Host ""
$moveCount = 0
$failCount = 0

foreach ($p in $plan) {
    try {
        if (-not (Test-Path $p.DestDir)) {
            New-Item -ItemType Directory -Path $p.DestDir -Force | Out-Null
        }
        Move-Item -LiteralPath $p.Src -Destination $p.DestPath -Force
        Write-Move ("{0} → {1}\{2}" -f $p.SrcName, $p.Artist, (Split-Path $p.DestPath -Leaf))
        $moveCount++
    } catch {
        Write-Warn ("移動失敗: {0} - {1}" -f $p.SrcName, $_)
        $failCount++
    }
}

# ========================================
# サマリ
# ========================================
Write-Host ""
Write-Host "========================================"
Write-Host "移動完了" -ForegroundColor Cyan
Write-Host ("  移動成功: {0}" -f $moveCount)
Write-Host ("  失敗    : {0}" -f $failCount)
Write-Host ("  移動先  : {0}" -f $absDst)