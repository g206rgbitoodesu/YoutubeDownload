# ========================================
# check_syntax.ps1
# 全 .ps1 ファイルの構文を一括チェック
# ========================================
[CmdletBinding()]
param(
    [string]$RootDir = $PSScriptRoot,
    [string[]]$ExcludeDirs = @("_sanitize_backup", "backup", "duplicates_backup", "music_download")
)

$ErrorActionPreference = "Continue"
Set-Location -Path $RootDir

# 除外パターンの正規表現を事前構築
$excludePattern = ($ExcludeDirs | ForEach-Object { [regex]::Escape($_) }) -join '|'

$files = Get-ChildItem -Path $RootDir -Filter *.ps1 -File -Recurse |
    Where-Object { $_.FullName -notmatch "\\($excludePattern)\\" }

Write-Host ""
Write-Host ("=== 構文チェック ({0} ファイル) ===" -f $files.Count) -ForegroundColor Magenta
if ($ExcludeDirs.Count -gt 0) {
    Write-Host ("  除外: {0}" -f ($ExcludeDirs -join ", ")) -ForegroundColor DarkGray
}
Write-Host ""

$ngFiles = New-Object System.Collections.Generic.List[string]

foreach ($f in $files) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors) | Out-Null

    if ($errors.Count -gt 0) {
        Write-Host ("[NG] {0}" -f $f.FullName.Substring($RootDir.Length + 1)) -ForegroundColor Red
        foreach ($e in $errors) {
            Write-Host ("     L{0}: {1}" -f $e.Extent.StartLineNumber, $e.Message) -ForegroundColor Red
        }
        $ngFiles.Add($f.FullName)
    } else {
        Write-Host ("[OK] {0}" -f $f.Name) -ForegroundColor Green
    }
}

Write-Host ""
if ($ngFiles.Count -eq 0) {
    Write-Host "★ 全ファイル構文 OK ★" -ForegroundColor Green
    exit 0
} else {
    Write-Host ("★ {0} ファイルに構文エラー ★" -f $ngFiles.Count) -ForegroundColor Red
    exit 1
}