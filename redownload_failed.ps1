# ========================================
# 検査NG曲を download_pc.ps1 -Force で再DL
# ========================================
[CmdletBinding()]
param(
    [string]$NgFile     = "verify_ng.txt",
    [string]$NgCsv      = "songlist_ng.csv"
)

$ErrorActionPreference = "Continue"
Set-Location -Path $PSScriptRoot

if (-not (Test-Path $NgFile)) {
    Write-Host "$NgFile がありません。再DL不要です。" -ForegroundColor Green
    exit 0
}

$rows = @(Import-Csv -Path $NgFile -Encoding UTF8 | Where-Object { $_.path })
if ($rows.Count -eq 0) {
    Write-Host "NG ファイルなし。再DL不要です。" -ForegroundColor Green
    exit 0
}

Write-Host ("再DL対象: {0} 件" -f $rows.Count) -ForegroundColor Cyan

# NGファイルから artist/title を推定して songlist_ng.csv を作成
"アーティスト,曲名,URL" | Set-Content -Path $NgCsv -Encoding UTF8

foreach ($r in $rows) {
    $base  = [System.IO.Path]::GetFileNameWithoutExtension($r.path)
    $clean = $base -replace '^\d+\s+', ''
    $clean = $clean -replace '\s*\[[^\]]*\]', ''
    $clean = $clean -replace '\s*\([^)]*\)', ''

    # "Artist - Title" 形式を分離
    $artist = $r.artist
    $title  = $r.title
    if ([string]::IsNullOrWhiteSpace($artist) -or [string]::IsNullOrWhiteSpace($title)) {
        $idx = $clean.IndexOf(' - ')
        if ($idx -ge 0) {
            $artist = $clean.Substring(0, $idx).Trim()
            $title  = $clean.Substring($idx + 3).Trim()
        } else {
            $title = $clean.Trim()
        }
    }

    # 壊れたファイルは退避（再DLで同名が来る前に）
    if (Test-Path $r.path) {
        Move-Item -LiteralPath $r.path -Destination "$($r.path).bad" -Force
    }

    # CSV にクォート付きで追記
    $qa = if ($artist -match '[",]') { '"' + ($artist -replace '"','""') + '"' } else { $artist }
    $qt = if ($title  -match '[",]') { '"' + ($title  -replace '"','""') + '"' } else { $title  }
    "$qa,$qt," | Add-Content -Path $NgCsv -Encoding UTF8
}

Write-Host "→ download_pc.ps1 -Force を呼び出します..." -ForegroundColor Cyan
& "$PSScriptRoot\download_pc.ps1" -CsvFile $NgCsv -Force -SkipPicard

# 成功したら .bad を削除、失敗なら戻す
Get-ChildItem -Path "music_download" -Filter "*.bad" -Recurse | ForEach-Object {
    $orig = $_.FullName -replace '\.bad$',''
    if (Test-Path $orig) {
        Remove-Item -LiteralPath $_.FullName -Force
    } else {
        Move-Item -LiteralPath $_.FullName -Destination $orig -Force
    }
}