# ========================================
# Navidrome music フォルダ 重複統合パッチ
# ========================================
# 処理:
#   1. "ファイル名 (N).拡張子" パターンを検出（Nは数字）
#   2. 対応する元ファイル "ファイル名.拡張子" が存在するか確認
#   3. 存在すれば「重複」とみなし、退避フォルダへ移動
#   4. 存在しなければ「(N)付きだが元がない」= 唯一のファイルなので残す
# ========================================
[CmdletBinding()]
param(
    [string]$TargetDir   = "$env:USERPROFILE\Downloads\navidrome\music",
    [string]$BackupDir   = "$env:USERPROFILE\Documents\YoutubeDownload\duplicates_backup",
    [string[]]$Extensions = @(".mp3", ".m4a", ".flac", ".opus", ".jpg", ".jpeg", ".png", ".pdf"),
    [switch]$DryRun,
    [switch]$Force       # 確認プロンプトを省略
)

$ErrorActionPreference = "Continue"

function Write-OK   { param([string]$m) Write-Host "  [OK]   $m" -ForegroundColor Green }
function Write-Skip { param([string]$m) Write-Host "  [SKIP] $m" -ForegroundColor DarkGray }
function Write-Move { param([string]$m) Write-Host "  [MOVE] $m" -ForegroundColor Yellow }
function Write-Warn { param([string]$m) Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function Write-Info { param([string]$m) Write-Host "  [INFO] $m" -ForegroundColor Gray }

Write-Host ""
Write-Host "=== Navidrome 重複統合パッチ ===" -ForegroundColor Magenta
Write-Host ""

if (-not (Test-Path $TargetDir)) {
    Write-Host "エラー: $TargetDir が存在しません。" -ForegroundColor Red
    exit 1
}

$absTarget = (Resolve-Path $TargetDir).Path
Write-Info ("対象: {0}" -f $absTarget)
Write-Info ("退避先: {0}" -f $BackupDir)
if ($DryRun) {
    Write-Host "  ★ DryRun モード（実際には移動しません）" -ForegroundColor Magenta
}

# ========================================
# 重複パターン: ファイル名末尾の " (数字)"
# ========================================
#  例: "cover (1).jpg"  →  base="cover",  suffix=1
#      "01 song (2).mp3" →  base="01 song", suffix=2
# ========================================
$pattern = '^(?<base>.+?)\s*\((?<num>\d+)\)$'

# 拡張子フィルタを正規表現化
$extRegex = ($Extensions | ForEach-Object { [regex]::Escape($_) }) -join '|'

# 全ファイル列挙
$allFiles = Get-ChildItem -Path $absTarget -Recurse -File |
    Where-Object { $_.Extension -match "^($extRegex)$" }

Write-Info ("総ファイル数: {0}" -f @($allFiles).Count)

# グループ化用の辞書: フォルダ + ベース名 → ファイルリスト
$groups = @{}
foreach ($f in $allFiles) {
    $dir  = $f.DirectoryName
    $base = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
    $ext  = $f.Extension.ToLower()

    $match = [regex]::Match($base, $pattern)
    if ($match.Success) {
        $keyBase = $match.Groups['base'].Value
        $key = "$dir|$keyBase|$ext"
        if (-not $groups.ContainsKey($key)) {
            $groups[$key] = @{ Target = $null; Duplicates = @() }
        }
        $groups[$key].Duplicates += $f
    } else {
        # 元ファイル
        $key = "$dir|$base|$ext"
        if (-not $groups.ContainsKey($key)) {
            $groups[$key] = @{ Target = $null; Duplicates = @() }
        }
        $groups[$key].Target = $f
    }
}

# ========================================
# 判定 & 移動
# ========================================
$moveCount = 0
$skipCount = 0
$keepCount = 0
$totalSize = 0

$moveList = New-Object System.Collections.Generic.List[object]

foreach ($key in $groups.Keys) {
    $g = $groups[$key]
    if ($g.Duplicates.Count -eq 0) { continue }

    if ($g.Target) {
        # 元ファイルあり → 重複は退避
        foreach ($dup in $g.Duplicates) {
            $moveList.Add([PSCustomObject]@{
                Duplicate = $dup
                Original  = $g.Target
            })
        }
    } else {
        # 元なし。(1) だけある状態 → 最も若い番号を「元」として残し、他を退避
        $sorted = $g.Duplicates | Sort-Object {
            $m = [regex]::Match([System.IO.Path]::GetFileNameWithoutExtension($_.Name), $pattern)
            [int]$m.Groups['num'].Value
        }
        $keep = $sorted[0]
        $keepCount++
        Write-Info ("元なし→最若番を保持: {0}" -f $keep.Name)
        foreach ($dup in ($sorted | Select-Object -Skip 1)) {
            $moveList.Add([PSCustomObject]@{
                Duplicate = $dup
                Original  = $keep
            })
        }
    }
}

Write-Host ""
Write-Info ("退避対象: {0} ファイル" -f $moveList.Count)
Write-Host ""

if ($moveList.Count -eq 0) {
    Write-Host "重複は見つかりませんでした。" -ForegroundColor Green
    exit 0
}

# 確認プロンプト（Force でなければ）
if (-not $DryRun -and -not $Force) {
    Write-Host ("{0} ファイルを {1} に移動します。よろしいですか? (y/N): " -f $moveList.Count, $BackupDir) -ForegroundColor Yellow -NoNewline
    $answer = Read-Host
    if ($answer -notmatch '^[yY]') {
        Write-Host "中断しました。" -ForegroundColor Red
        exit 0
    }
}

# ========================================
# 実行
# ========================================
foreach ($item in $moveList) {
    $dup = $item.Duplicate
    $rel = $dup.FullName.Substring($absTarget.Length + 1)
    $dest = Join-Path $BackupDir $rel
    $destDir = Split-Path $dest -Parent

    if ($DryRun) {
        Write-Move ("[DryRun] {0}  (← 元: {1})" -f $rel, $item.Original.Name)
        $moveCount++
        $totalSize += $dup.Length
    } else {
        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        try {
            Move-Item -LiteralPath $dup.FullName -Destination $dest -Force
            Write-Move ("{0}" -f $rel)
            $moveCount++
            $totalSize += $dup.Length
        } catch {
            Write-Warn ("移動失敗: {0} - {1}" -f $rel, $_)
        }
    }
}

# ========================================
# サマリ
# ========================================
Write-Host ""
Write-Host "========================================"
Write-Host "重複統合 完了" -ForegroundColor Cyan
Write-Host ("  退避: {0} ファイル" -f $moveCount)
Write-Host ("  保持（元なし→最若番）: {0}" -f $keepCount)
Write-Host ("  合計サイズ: {0:N2} MB" -f ($totalSize / 1MB))
if (-not $DryRun) {
    Write-Host ("  退避先: {0}" -f $BackupDir) -ForegroundColor Green
    Write-Host ""
    Write-Host "  確認後に削除する場合:" -ForegroundColor Yellow
    Write-Host ("    Remove-Item '{0}' -Recurse -Force" -f $BackupDir) -ForegroundColor Yellow
}