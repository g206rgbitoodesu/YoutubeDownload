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
$decorations = @(
    '\s*⧸\s*',                          # 全角スラッシュ区切り
    '\s*-\s*Music Video\s*-?',          # "- Music Video-" 系（前後の空白・ハイフン込み）
    '\s*\[LIVE[^\]]*\]',
    '\s*【[^】]*】',
    '\s*「[^」]*」',
    '\s*＂[^＂]*＂',
    '\s*\[Official[^\]]*\]',
    '\s*\(Official[^)]*\)',
    '\s*\(Top Of The Tops[^)]*\)',
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

    # 二重アーティスト除去（例: "Queen - Queen - Title" → "Queen - Title"）
    #   "A - A - ..." のパターンを検出
    if ($base -match '^(.+?)\s+-\s+\1\s+-\s+(.+)$') {
        $base = "$($matches[1]) - $($matches[2])"
    }

    # 追加（⧸ 区切り対応）
    if ($base -match '^(.+?)\s+-\s+\1\s+⧸\s*(.+)$') {
        $base = "$($matches[1]) - $($matches[2])"
    }

    # 装飾除去
    foreach ($pat in $decorations) {
        $base = $base -replace $pat, ''
    }

    # 連続する記号・空白整理
    $base = $base -replace '\s{2,}', ' '
    $base = $base.Trim(' ', '-', '_', '.', '　')

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
