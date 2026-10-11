# ========================================
# songlist.csv クリーンアップ
#   - 重複除去（アーティスト + 曲名、大文字小文字無視）
#   - クォート正規化（カンマ・引用符・前後空白を含むフィールドを "..." で囲む）
#   - 4フィールド以上に誤分解された行を Artist/Title/URL に再統合
#     （例: Queen,All Dead,All Dead → Queen,"All Dead, All Dead",）
# ========================================
[CmdletBinding()]
param(
    [string]$CsvFile   = "songlist.csv",
    [string]$OutFile   = "songlist_clean.csv",
    [string]$BackupDir = "backup",
    [switch]$InPlace   # 指定すると元ファイルを上書き（先にバックアップ取得）
)

$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot

if (-not (Test-Path $CsvFile)) {
    Write-Host "エラー: $CsvFile が見つかりません。" -ForegroundColor Red
    exit 1
}

# ========================================
# 1. 読み込み（BOM / 空行 / コメント除去）
# ========================================
$lines = Get-Content -Path $CsvFile -Encoding UTF8 |
    ForEach-Object { $_.TrimStart([char]0xFEFF) } |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not $_.TrimStart().StartsWith("#") }

if (@($lines).Count -eq 0) {
    Write-Host "エラー: 有効な行がありません。" -ForegroundColor Red
    exit 1
}

# ========================================
# 2. CSV 行パーサ（RFC4180 風）
# ========================================
function Parse-CsvLine {
    param([string]$Line)
    $fields = New-Object System.Collections.Generic.List[string]
    $sb     = New-Object System.Text.StringBuilder
    $inQ    = $false
    for ($i = 0; $i -lt $Line.Length; $i++) {
        $c = $Line[$i]
        if ($c -eq '"') {
            if ($inQ -and ($i + 1) -lt $Line.Length -and $Line[$i + 1] -eq '"') {
                [void]$sb.Append('"'); $i++
            } else {
                $inQ = -not $inQ
            }
        } elseif ($c -eq ',' -and -not $inQ) {
            $fields.Add($sb.ToString()); [void]$sb.Clear()
        } else {
            [void]$sb.Append($c)
        }
    }
    $fields.Add($sb.ToString())
    return ,$fields.ToArray()
}

# ========================================
# 3. 3フィールド (Artist, Title, Url) に正規化
# ========================================
function Normalize-Row {
    param([string[]]$Fields)

    if ($Fields.Count -le 3) {
        $a = if ($Fields.Count -ge 1) { $Fields[0].Trim() } else { "" }
        $t = if ($Fields.Count -ge 2) { $Fields[1].Trim() } else { "" }
        $u = if ($Fields.Count -ge 3) { $Fields[2].Trim() } else { "" }
        return ,@($a, $t, $u)
    }

    # 4フィールド以上: 末尾が URL / 空なら「中間 = タイトル」として結合
    $last = $Fields[-1].Trim()
    if ($last -match '^https?://' -or [string]::IsNullOrWhiteSpace($last)) {
        $a = $Fields[0].Trim()
        $u = $last
        $t = (($Fields[1..($Fields.Count - 2)]) | ForEach-Object { $_.Trim() }) -join ", "
        return ,@($a, $t, $u)
    } else {
        # URLなし・末尾まで本文 → 先頭だけ Artist、残りは全部タイトル
        $a = $Fields[0].Trim()
        $t = (($Fields[1..($Fields.Count - 1)]) | ForEach-Object { $_.Trim() }) -join ", "
        return ,@($a, $t, "")
    }
}

# ========================================
# 4. 出力用クォート付与
# ========================================
function Quote-Field {
    param([string]$Value)
    if ($null -eq $Value) { return "" }
    if ($Value -match '[",\r\n]' -or $Value -match '^\s|\s$') {
        return '"' + ($Value -replace '"', '""') + '"'
    }
    return $Value
}

# ========================================
# 5. パース & 正規化
# ========================================
$rows = New-Object System.Collections.Generic.List[object]
$skipped = 0

foreach ($line in $lines) {
    $f = Parse-CsvLine -Line $line
    $n = Normalize-Row -Fields $f
    if ([string]::IsNullOrWhiteSpace($n[1]) -and [string]::IsNullOrWhiteSpace($n[2])) {
        $skipped++
        continue
    }
    $rows.Add([PSCustomObject]@{ Artist = $n[0]; Title = $n[1]; Url = $n[2] })
}

# ヘッダー行らしき行は除外（正規化前の先頭がヘッダー語彙なら除去）
$headerPattern = '^(アーティスト|Artist|曲名|タイトル|Title|Song|URL|Url|Link)$'
if ($rows.Count -gt 0 -and $rows[0].Artist -match $headerPattern) {
    $rows.RemoveAt(0)
}

# ========================================
# 6. 重複除去（Artist + Title の大文字小文字無視）
# ========================================
$seen   = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$unique = New-Object System.Collections.Generic.List[object]
$dups   = 0

foreach ($r in $rows) {
    $key = "$($r.Artist)`t$($r.Title)"
    if ($seen.Add($key)) {
        $unique.Add($r)
    } else {
        $dups++
        Write-Host ("重複スキップ: {0} - {1}" -f $r.Artist, $r.Title) -ForegroundColor DarkYellow
    }
}

# ========================================
# 7. 出力行生成
# ========================================
$outLines = New-Object System.Collections.Generic.List[string]
$outLines.Add("アーティスト,曲名,URL")
foreach ($r in $unique) {
    $outLines.Add(
        (Quote-Field $r.Artist) + "," +
        (Quote-Field $r.Title)  + "," +
        (Quote-Field $r.Url)
    )
}

# ========================================
# 8. 保存
# ========================================
$utf8Bom = New-Object System.Text.UTF8Encoding($true)

if ($InPlace) {
    # バックアップ
    if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir | Out-Null }
    $stamp   = Get-Date -Format "yyyyMMdd_HHmmss"
    $backup  = Join-Path $BackupDir ("{0}.{1}.bak" -f (Split-Path $CsvFile -Leaf), $stamp)
    Copy-Item -LiteralPath $CsvFile -Destination $backup -Force
    Write-Host "バックアップ: $backup" -ForegroundColor Cyan

    $target = (Resolve-Path -LiteralPath $CsvFile).Path
    [System.IO.File]::WriteAllLines($target, $outLines, $utf8Bom)
    Write-Host "上書き保存: $target" -ForegroundColor Green
} else {
    $target = if ([System.IO.Path]::IsPathRooted($OutFile)) {
        $OutFile
    } else {
        Join-Path $PSScriptRoot $OutFile
    }
    [System.IO.File]::WriteAllLines($target, $outLines, $utf8Bom)
    Write-Host "新規保存: $target" -ForegroundColor Green
}

# ========================================
# 9. サマリ
# ========================================
Write-Host "========================================"
Write-Host "クリーンアップ完了" -ForegroundColor Cyan
Write-Host ("  入力行数      : {0}" -f @($lines).Count)
Write-Host ("  有効データ行  : {0}" -f $rows.Count)
Write-Host ("  空行スキップ  : {0}" -f $skipped)
Write-Host ("  重複除去      : {0}" -f $dups)
Write-Host ("  出力行数      : {0} (ヘッダー含む)" -f $outLines.Count)