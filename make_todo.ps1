# ========================================
# songlist.csv から「未ダウンロードの曲」だけを抽出
# ========================================
# DL済み判定ソース:
#   1) success.log          (artist,title,url 形式)
#   2) music_download\      (実ファイル名からタイトルを推定)
#   3) Navidrome\music\     (同上)
# ========================================
[CmdletBinding()]
param(
    [string]   $CsvFile     = "songlist.csv",
    [string[]] $DoneLogs    = @("success.log"),
    [string[]] $ScanFolders = @(
        "music_download",
        "$env:USERPROFILE\Downloads\navidrome\music"
    ),
    [string]   $OutFile     = "songlist_todo.csv",
    [switch]   $TitleOnly,   # アーティスト無視。タイトル一致のみで判定
    [switch]   $ShowDone     # 除外された（=DL済みの）曲もログに表示
)

$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot

if (-not (Test-Path $CsvFile)) {
    Write-Host "エラー: $CsvFile が見つかりません。" -ForegroundColor Red
    exit 1
}

function Get-NormKey {
    param([string]$s)
    if ([string]::IsNullOrEmpty($s)) { return "" }
    $t = $s.ToLowerInvariant()
    # 全角スペース → 半角スペース
    $t = $t -replace '　', ' '
    # 空白・句読点・括弧類を除去（中身は残す：Ame(A) vs Ame(B) を区別）
    $pattern = @'
[\s\.\,\!\?'"\-_\(\)\[\]\{\}、。！？・「」『』【】]
'@
    $t = $t -replace $pattern, ''
    return $t
}

# ========================================
# CSV 行パーサ（clean_songlist.ps1 と同等）
# ========================================
function Parse-CsvLine {
    param([string]$Line)
    $fields = New-Object System.Collections.Generic.List[string]
    $sb = New-Object System.Text.StringBuilder
    $inQ = $false
    for ($i = 0; $i -lt $Line.Length; $i++) {
        $c = $Line[$i]
        if ($c -eq '"') {
            if ($inQ -and ($i + 1) -lt $Line.Length -and $Line[$i + 1] -eq '"') {
                [void]$sb.Append('"'); $i++
            } else { $inQ = -not $inQ }
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
# 1. songlist.csv 読み込み
# ========================================
$rawLines = Get-Content -Path $CsvFile -Encoding UTF8 |
    ForEach-Object { $_.TrimStart([char]0xFEFF) } |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not $_.TrimStart().StartsWith("#") }

if (@($rawLines).Count -eq 0) {
    Write-Host "エラー: $CsvFile に有効な行がありません。" -ForegroundColor Red
    exit 1
}

# ヘッダー判定
$headerPattern = '^(アーティスト|Artist|曲名|タイトル|Title|Song|URL|Url|Link)$'
$first = Parse-CsvLine -Line $rawLines[0]
$hasHeader = ($first.Count -ge 1) -and ($first[0].Trim() -match $headerPattern)
$dataLines = if ($hasHeader) { $rawLines | Select-Object -Skip 1 } else { $rawLines }

$songs = New-Object System.Collections.Generic.List[object]
foreach ($line in $dataLines) {
    $f = Parse-CsvLine -Line $line
    $a = if ($f.Count -ge 1) { $f[0].Trim() } else { "" }
    $t = if ($f.Count -ge 2) { $f[1].Trim() } else { "" }
    $u = if ($f.Count -ge 3) { $f[2].Trim() } else { "" }
    if ([string]::IsNullOrWhiteSpace($t) -and [string]::IsNullOrWhiteSpace($u)) { continue }
    $songs.Add([PSCustomObject]@{ Artist=$a; Title=$t; Url=$u })
}

Write-Host ("songlist.csv 読み込み: {0} 曲" -f $songs.Count) -ForegroundColor Cyan

# 既知アーティスト集合（ファイル名からのタイトル抽出に使う）
$knownArtists = $songs | ForEach-Object { $_.Artist } |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    Sort-Object -Unique

# ========================================
# 2. DL済みタイトルの収集
# ========================================
$doneTitleKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$doneArtistTitleKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$doneFullNames = New-Object System.Collections.Generic.List[string]  # 正規化済みファイル名（拡張子なし）

function Add-DoneEntry {
    param([string]$Artist, [string]$Title)
    if ([string]::IsNullOrWhiteSpace($Title)) { return }
    $tk = Get-NormKey $Title
    if ($tk) { [void]$doneTitleKeys.Add($tk) }
    if (-not [string]::IsNullOrWhiteSpace($Artist)) {
        $ak = Get-NormKey $Artist
        [void]$doneArtistTitleKeys.Add("$ak|$tk")
    }
}

# --- 2a. success.log などの DoneLogs ---
foreach ($log in $DoneLogs) {
    if (-not (Test-Path $log)) { continue }
    $n = 0
    foreach ($line in Get-Content -Path $log -Encoding UTF8) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $f = Parse-CsvLine -Line $line
        $a = if ($f.Count -ge 1) { $f[0].Trim() } else { "" }
        $t = if ($f.Count -ge 2) { $f[1].Trim() } else { "" }
        if ([string]::IsNullOrWhiteSpace($t)) { continue }
        Add-DoneEntry -Artist $a -Title $t
        $n++
    }
    Write-Host ("DL済みソース [{0}]: {1} 行" -f $log, $n) -ForegroundColor Cyan
}

# --- 2b. フォルダ内の実ファイル ---
function Get-TitleFromFileName {
    param([string]$BaseName)   # 拡張子なし
    $b = $BaseName -replace '^\d+\s+', ''
    foreach ($a in $knownArtists) {
        $prefix = "$a - "
        if ($b.StartsWith($prefix)) {
            return $b.Substring($prefix.Length)
        }
    }
    # フォールバック: 最初の " - " で分割
    $idx = $b.IndexOf(' - ')
    if ($idx -ge 0) { return $b.Substring($idx + 3) }
    return $b
}

foreach ($dir in $ScanFolders) {
    if (-not (Test-Path $dir)) {
        Write-Host ("スキャン対象なし: {0}" -f $dir) -ForegroundColor DarkGray
        continue
    }
    $count = 0
    Get-ChildItem -Path $dir -Recurse -File -Include *.mp3,*.m4a,*.flac,*.opus |
        ForEach-Object {
            $base = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
            $title = Get-TitleFromFileName -BaseName $base
            if (-not [string]::IsNullOrWhiteSpace($title)) {
                Add-DoneEntry -Artist "" -Title $title
                $doneFullNames.Add((Get-NormKey $base))
                $count++
            }
        }
    Write-Host ("DL済みソース [{0}]: {1} ファイル" -f $dir, $count) -ForegroundColor Cyan
}

Write-Host ("DL済みタイトル: {0} 件 / DL済み(artist,title)ペア: {1} 件" -f $doneTitleKeys.Count, $doneArtistTitleKeys.Count) -ForegroundColor Cyan

# ========================================
# 3. 突き合わせ → TODO 抽出
# ========================================
function Test-Done {
    param([string]$Artist, [string]$Title)
    $tk = Get-NormKey $Title
    if (-not $tk) { return $true }  # タイトル空は除外

    if (-not $TitleOnly) {
        $ak = Get-NormKey $Artist
        if ($ak -and $doneArtistTitleKeys.Contains("$ak|$tk")) { return $true }
    }
    if ($doneTitleKeys.Contains($tk)) { return $true }

    # ファイル名の中に正規化タイトルが完全一致で含まれるか
    foreach ($fn in $doneFullNames) {
        if ($fn -eq $tk) { return $true }
        if ($fn.EndsWith($tk)) { return $true }
    }
    return $false
}

$todo  = New-Object System.Collections.Generic.List[object]
$done  = New-Object System.Collections.Generic.List[object]

foreach ($s in $songs) {
    if (Test-Done -Artist $s.Artist -Title $s.Title) {
        $done.Add($s)
        if ($ShowDone) {
            Write-Host ("  [済] {0} - {1}" -f $s.Artist, $s.Title) -ForegroundColor DarkGray
        }
    } else {
        $todo.Add($s)
    }
}

# ========================================
# 4. 出力（songlist.csv と同じ形式）
# ========================================
function Quote-Field {
    param([string]$v)
    if ($null -eq $v) { return "" }
    if ($v -match '[",\r\n]' -or $v -match '^\s|\s$') {
        return '"' + ($v -replace '"', '""') + '"'
    }
    return $v
}

$outLines = New-Object System.Collections.Generic.List[string]
$outLines.Add("アーティスト,曲名,URL")
foreach ($s in $todo) {
    $outLines.Add((Quote-Field $s.Artist) + "," + (Quote-Field $s.Title) + "," + (Quote-Field $s.Url))
}

$utf8Bom = New-Object System.Text.UTF8Encoding($true)
$target = if ([System.IO.Path]::IsPathRooted($OutFile)) { $OutFile } else { Join-Path $PSScriptRoot $OutFile }
[System.IO.File]::WriteAllLines($target, $outLines, $utf8Bom)

# ========================================
# 5. サマリ
# ========================================
Write-Host "========================================"
Write-Host "TODO 抽出完了" -ForegroundColor Cyan
Write-Host ("  入力曲数  : {0}" -f $songs.Count)
Write-Host ("  DL済み    : {0}" -f $done.Count)
Write-Host ("  未DL(TODO): {0}" -f $todo.Count) -ForegroundColor Yellow
Write-Host ("  出力先    : {0}" -f $target) -ForegroundColor Green

if ($todo.Count -eq 0) {
    Write-Host ""
    Write-Host "  ★ 全曲DL済みです。次は verify_downloads.ps1 以降を実行してください。" -ForegroundColor Green
    exit 0
}