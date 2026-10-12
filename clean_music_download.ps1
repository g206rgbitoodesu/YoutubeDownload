# ========================================
# music_download ファイル名クリーンアップ
# ========================================
# 処理:
#   - "Artist - Artist - Title" → "Artist - Title"（二重アーティスト除去）
#   - "Artist - Title - Info" → "Artist - Title"
#   - 装飾を除去: (Official Video), -Music Video-, [LIVE ...], 【...】, etc.
# ========================================
# v2 修正:
#   - ⧸ は削除せず " - " に置換（Kansas City ⧸ Hey-Hey 連結バグ修正）
#   - 先頭の連番 "NN " を分離してパターン適用（playlist_index 対応）
#   - 「」は曲名本体のため削除しない
#   - 括弧なし "Official Music Video" を行末まで削除
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

# ========================================
# 装飾除去パターン（順に適用）
# ========================================
# ★ 重要:
#   - 「」は曲名本体のことが多いので削除しない
#   - ⧸ は区切り文字なので $decorations では扱わない（本体で " - " に置換）
# ========================================
$decorations = @(
    # 区切り記号系
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
    '\s*【[^】]*】',
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
    # 0a. 先頭の連番 "NN " を退避
    # ----------------------------------------
    # 例: "02 Queen - Queen - Title" → prefix="02 ", body="Queen - Queen - Title"
    $prefix = ""
    $body   = $base
    if ($base -match '^(\d+\s+)(.+)$') {
        $prefix = $matches[1]
        $body   = $matches[2]
    }

    # ----------------------------------------
    # 0b. ⧸ を区切り文字 " - " に置換（削除ではなく置換）
    # ----------------------------------------
    # 例: "Kansas City ⧸ Hey-Hey-Hey-Hey" → "Kansas City - Hey-Hey-Hey-Hey"
    $body = $body -replace '\s*⧸\s*', ' - '

    # ----------------------------------------
    # 二重アーティスト除去
    # ----------------------------------------
    # (1) "Artist - Artist - Title" → "Artist - Title"
    if ($body -match '^(.+?)\s+-\s+\1\s+-\s+(.+)$') {
        $body = "$($matches[1]) - $($matches[2])"
    }

    # (2) "Artist - Artist「Title」" → "Artist - Title"
    #     Mrs.GREEN APPLE 系のYouTubeタイトル対策
    if ($body -match '^(.+?)\s+-\s+\1「(.+)」') {
        $body = "$($matches[1]) - $($matches[2])"
    }

    # (3) "Artist - Artist Title" 形式（区切りなし・アーティスト名が先頭に重複）
    if ($body -match '^(.+?)\s+-\s+\1\s+(.+)$') {
        $body = "$($matches[1]) - $($matches[2])"
    }

    # ----------------------------------------
    # 装飾除去（順序重要: 長い/具体的 → 短い/一般）
    # ----------------------------------------
    foreach ($pat in $decorations) {
        $body = $body -replace $pat, ''
    }

    # ----------------------------------------
    # 連続する記号・空白整理
    # ----------------------------------------
    $body = $body -replace '\s{2,}', ' '
    $body = $body.Trim(' ', '-', '_', '.', '　')

    # ----------------------------------------
    # prefix を戻して最終名を組み立て
    # ----------------------------------------
    $base = "$prefix$body"

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
