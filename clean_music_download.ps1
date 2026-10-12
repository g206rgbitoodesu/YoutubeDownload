# ========================================
# music_download ファイル名クリーンアップ
# ========================================
# 処理:
#   - "Artist - Artist - Title" → "Artist - Title"（二重アーティスト除去）
#   - "Artist - Title - Info" → "Artist - Title"
#   - 装飾を除去: (Official Video), -Music Video-, [LIVE ...], 【...】, etc.
# ========================================
[CmdletBinding()]
param(
    [string]$TargetDir = "music_download",
    [switch]$DryRun
)

$ErrorActionPreference = "Continue"
Set-Location -Path $PSScriptRoot


if (-not (Test-Path $TargetDir)) {
    if ($DryRun) {
        Write-Host "  [DryRun] $TargetDir は存在しません（本実行時はスキップされます）" -ForegroundColor Gray
        exit 0
    }
    Write-Host "エラー: $TargetDir が見つかりません。" -ForegroundColor Red
    exit 1
}


Write-Host ""
Write-Host "=== music_download ファイル名クリーンアップ ===" -ForegroundColor Magenta
if ($DryRun) { Write-Host "  ★ DryRun モード" -ForegroundColor Magenta }
Write-Host ""

# 装飾除去パターン（順に適用）
# 装飾除去パターン（順に適用）
# ★ 重要: 「」は曲名本体のことが多いので削除しない
$decorations = @(
    # 区切り記号系
    '\s*⧸\s*',
    '\s*-\s*Music Video\s*-?',
    '\s*-Music Video-',

    # 括弧なしの装飾（行末まで）
    '\s+Official\s+Music\s+Video.*$',
    '\s+Official\s+Lyric\s+Video.*$',
    '\s+Official\s+Video.*$',
    '\s+Music\s+Video.*$',
    '\s+Lyric\s+Video.*$',

    # 括弧付きの装飾
    '\s*\[Official[^\]]*\]',
    '\s*\(Official[^)]*\)',
    '\s*\[LIVE[^\]]*\]',
    '\s*【[^】]*】',              # ★ 【】は装飾として削除（LIVE等）
    '\s*＂[^＂]*＂',
    '\s*\(Top Of The Pops[^)]*\)',
    '\s*\(Live at [^)]*\)',
    '\s*\(Remastered[^)]*\)',
    '\s*\(Lyric Video[^)]*\)',
    '\s*\(Music Video[^)]*\)',
    '\s*\(Audio[^)]*\)',
    '\s*\(MV[^)]*\)',
    '\s*\(HD[^)]*\)',
    '\s*\(4K[^)]*\)',
    '\s*from\s*「[^」]*」',
    '\s*from\s*$',
    '\s*-\s*사카낙션.*$'
)

$files = @(Get-ChildItem -Path $TargetDir -Recurse -File -Include *.mp3,*.m4a,*.flac,*.opus)
$total = @($files).Count
Write-Host "対象: $total ファイル" -ForegroundColor Cyan

$renamed = 0
$skipped = 0

foreach ($f in $files) {
    $base = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
    $ext  = $f.Extension
    $orig = $base

    # ----------------------------------------
    # 二重アーティスト除去
    # ----------------------------------------
    # (1) "Artist - Artist - Title" → "Artist - Title"
    if ($base -match '^(.+?)\s+-\s+\1\s+-\s+(.+)$') {
        $base = "$($matches[1]) - $($matches[2])"
    }

    # (2) "Artist - Artist ⧸ Title" → "Artist - Title"
    if ($base -match '^(.+?)\s+-\s+\1\s+⧸\s*(.+)$') {
        $base = "$($matches[1]) - $($matches[2])"
    }

    # (3) "Artist - Artist「Title」" → "Artist - Title"
    #     Mrs.GREEN APPLE 系のYouTubeタイトル「アーティスト名「曲名」」対策
    if ($base -match '^(.+?)\s+-\s+\1「(.+)」') {
        $base = "$($matches[1]) - $($matches[2])"
    }

    # (4) "Artist - Artist Title" 形式（区切りなし・アーティスト名が先頭に重複）
    #     例: "Mrs. GREEN APPLE - Mrs. GREEN APPLE ライラック"
    #     アーティスト名がタイトル先頭に付いている場合のみ除去
    if ($base -match '^(.+?)\s+-\s+\1\s+(.+)$') {
        $base = "$($matches[1]) - $($matches[2])"
    }

    # ----------------------------------------
    # 装飾除去（順序重要: 長い/具体的 → 短い/一般）
    # ----------------------------------------
    foreach ($pat in $decorations) {
        $base = $base -replace $pat, ''
    }

    # ----------------------------------------
    # 連続する記号・空白整理
    # ----------------------------------------
    $base = $base -replace '\s{2,}', ' '
    $base = $base.Trim(' ', '-', '_', '.', '　')

    # ----------------------------------------
    # 変化なし判定
    # ----------------------------------------
    if ($base -eq $orig) {
        $skipped++
        continue
    }
    $newName = "$base$ext"
    Write-Host ("  変更: {0}" -f $orig) -ForegroundColor Gray
    Write-Host ("     → {0}" -f $base) -ForegroundColor Green

    if (-not $DryRun) {
        $dest = Join-Path $f.DirectoryName $newName
        if (Test-Path $dest) {
            Write-Host "    ※ 同名ファイルが既に存在。スキップ" -ForegroundColor Yellow
            continue
        }
        Rename-Item -LiteralPath $f.FullName -NewName $newName -Force
    }
    $renamed++
}

Write-Host ""
Write-Host "========================================"
Write-Host "クリーンアップ完了" -ForegroundColor Cyan
Write-Host ("  リネーム: {0} / 変更なし: {1} / 合計: {2}" -f $renamed, $skipped, $total)
