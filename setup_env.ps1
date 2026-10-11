# ========================================
# setup_env.ps1
# YoutubeDownload 環境自動セットアップ
# ========================================
# 処理:
#   1. yt-dlp / ffmpeg / ffprobe / fpcalc / Picard の存在確認
#   2. PATH にない場合、一般的な場所を自動探索
#   3. 見つかったらユーザー PATH に永続追加（管理者不要）
#   4. 見つからなければダウンロードURL / winget コマンドを提示
#   5. winget があれば未検出ツールを自動インストール提案
# ========================================
[CmdletBinding()]
param(
    [switch]$DryRun,        # PATH 書き込みせず確認のみ
    [switch]$AutoInstall,   # winget インストール提案をスキップして自動実行
    [switch]$SkipDiagnose   # 完了後の diagnose.ps1 呼び出しをスキップ
)

$ErrorActionPreference = "Continue"
Set-Location -Path $PSScriptRoot

# ----------------------------------------
# 出力ヘルパー
# ----------------------------------------
function Write-Title { param([string]$m)
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Magenta
    Write-Host ("  " + $m) -ForegroundColor Magenta
    Write-Host ("=" * 60) -ForegroundColor Magenta
}
function Write-OK    { param([string]$m) Write-Host "  [OK]    $m" -ForegroundColor Green }
function Write-NG    { param([string]$m) Write-Host "  [NG]    $m" -ForegroundColor Red }
function Write-Warn  { param([string]$m) Write-Host "  [WARN]  $m" -ForegroundColor Yellow }
function Write-Info  { param([string]$m) Write-Host "  [INFO]  $m" -ForegroundColor Gray }
function Write-Found { param([string]$m) Write-Host "  [FOUND] $m" -ForegroundColor Cyan }
function Write-Add   { param([string]$m) Write-Host "  [ADD]   $m" -ForegroundColor Cyan }

# ----------------------------------------
# 探索ルート候補（存在するものだけ使用）
# ----------------------------------------
$searchRoots = @(
    "$env:LOCALAPPDATA\Microsoft\WinGet\Links",
    "$env:LOCALAPPDATA\Microsoft\WinGet\Packages",
    "$env:USERPROFILE\scoop\shims",
    "C:\ProgramData\chocolatey\bin",
    "$env:USERPROFILE\Downloads",
    "$env:USERPROFILE\Documents",
    "$env:USERPROFILE\Desktop",
    "C:\ffmpeg",
    "C:\tools",
    "$env:LOCALAPPDATA\Programs",
    "$env:APPDATA\Python",
    "C:\Python313", "C:\Python312", "C:\Python311", "C:\Python310",
    "$env:USERPROFILE\AppData\Local\Programs\Python",
    "C:\Program Files",
    "C:\Program Files (x86)"
) | Where-Object { Test-Path $_ }

# ----------------------------------------
# ツール定義
# ----------------------------------------
$tools = @(
    @{
        Name       = "yt-dlp"
        Cmd        = "yt-dlp"
        Exe        = "yt-dlp.exe"
        PathNeeded = $true
        Url        = "https://github.com/yt-dlp/yt-dlp/releases"
        WingetId   = "yt-dlp.yt-dlp"
    },
    @{
        Name       = "ffmpeg"
        Cmd        = "ffmpeg"
        Exe        = "ffmpeg.exe"
        PathNeeded = $true
        Url        = "https://www.gyan.dev/ffmpeg/builds/"
        WingetId   = "Gyan.FFmpeg"
    },
    @{
        Name       = "ffprobe"
        Cmd        = "ffprobe"
        Exe        = "ffprobe.exe"
        PathNeeded = $true
        Url        = "https://www.gyan.dev/ffmpeg/builds/"
        WingetId   = "Gyan.FFmpeg"
    },
    @{
        Name       = "fpcalc"
        Cmd        = "fpcalc"
        Exe        = "fpcalc.exe"
        PathNeeded = $true
        Url        = "https://acoustid.org/chromaprint"
        WingetId   = "AcoustID.Chromaprint"
    },
    @{
        Name       = "Picard"
        Cmd        = $null                    # PATH 不要
        Exe        = "picard.exe"
        PathNeeded = $false
        Url        = "https://picard.musicbrainz.org/"
        WingetId   = "MusicBrainz.Picard"
        FixedPath  = "C:\Program Files\MusicBrainz Picard\picard.exe"
    }
)

# ----------------------------------------
# ユーザー PATH 操作ヘルパー
# ----------------------------------------
function Get-UserPathParts {
    $p = [Environment]::GetEnvironmentVariable("Path", "User")
    if ([string]::IsNullOrEmpty($p)) { return @() }
    return @($p -split ';' | Where-Object { $_ -ne "" })
}

function Add-ToUserPath {
    param([string]$Dir)
    if ([string]::IsNullOrWhiteSpace($Dir)) { return "invalid" }
    if (-not (Test-Path $Dir)) { return "invalid" }

    # ---- 1. 現在のプロセスに即時反映（永続化の有無に関わらず必須） ----
    $pathParts = @($env:Path -split ';' | Where-Object { $_ -ne "" })
    if ($pathParts -notcontains $Dir) {
        $env:Path = "$env:Path;$Dir"
    }

    # ---- 2. ユーザー PATH（レジストリ）への永続化判定 ----
    $userParts = Get-UserPathParts
    if ($userParts -contains $Dir) {
        return "already"    # 永続化済み・今回のプロセスに反映した
    }

    $newPath = ($userParts + $Dir) -join ';'
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    return "added"          # 新規に永続化した
}
# ----------------------------------------
# 探索関数
# ----------------------------------------
function Find-Exe {
    param(
        [string]$ExeName,
        [string[]]$Roots,
        [string]$FixedPath,
        [int]$MaxDepth = 5
    )

    if ($FixedPath -and (Test-Path $FixedPath)) {
        return $FixedPath
    }

    foreach ($root in $Roots) {
        if (-not (Test-Path $root)) { continue }
        try {
            $found = Get-ChildItem -Path $root -Filter $ExeName -Recurse `
                        -Depth $MaxDepth -File -ErrorAction SilentlyContinue |
                     Select-Object -First 1
            if ($found) { return $found.FullName }
        } catch { }
    }
    return $null
}

# ========================================
# メイン処理
# ========================================
$script:AddedDirs   = New-Object System.Collections.Generic.List[string]
$script:FoundTools  = New-Object System.Collections.Generic.List[string]
$script:MissingTools = New-Object System.Collections.Generic.List[object]

$startTime = Get-Date

Write-Title "YoutubeDownload 環境セットアップ"
Write-Info ("ユーザー  : {0}" -f $env:USERNAME)
Write-Info ("日時      : {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
Write-Info ("探索ルート: {0} 個" -f $searchRoots.Count)
if ($DryRun) { Write-Host "  ★ DryRun モード（PATH 書き込みしません）" -ForegroundColor Magenta }

foreach ($t in $tools) {
    Write-Host ""
    Write-Host ("--- {0} ---" -f $t.Name) -ForegroundColor White

    # 1. PATH / FixedPath 確認
    if ($t.Cmd) {
        $cmdInfo = Get-Command $t.Cmd -ErrorAction SilentlyContinue
        if ($cmdInfo) {
            Write-OK ("PATH 上に存在: {0}" -f $cmdInfo.Source)
            $script:FoundTools.Add($t.Name)
            continue
        }
    } elseif ($t.FixedPath) {
        if (Test-Path $t.FixedPath) {
            Write-OK ("インストール済み: {0}" -f $t.FixedPath)
            $script:FoundTools.Add($t.Name)
            continue
        }
    }

    # 2. 探索
    Write-Warn "PATH 上にありません。一般的な場所を探索中..."
    $foundPath = Find-Exe -ExeName $t.Exe -Roots $searchRoots -FixedPath $t.FixedPath

    if ($foundPath) {
        Write-Found $foundPath

        # 3. PATH 追加（PathNeeded の場合のみ）
    if ($t.PathNeeded) {
        $foundDir = Split-Path $foundPath -Parent
        Write-Info ("ディレクトリ: {0}" -f $foundDir)

        if ($DryRun) {
            Write-Warn ("[DryRun] ユーザー PATH に追加予定: {0}" -f $foundDir)
        } else {
            switch (Add-ToUserPath -Dir $foundDir) {
                "added" {
                    Write-Add ("ユーザー PATH に追加: {0}" -f $foundDir)
                    $script:AddedDirs.Add($foundDir)
                }
                "already" {
                    Write-Info "既にユーザー PATH に含まれています（プロセスに反映）"
                }
                default {
                    Write-Warn ("パスが不正のためスキップ: {0}" -f $foundDir)
                }
            }
        }
    }
        $script:FoundTools.Add($t.Name)
    } else {
        Write-NG "PATH にも一般的な場所にも見つかりません"
        Write-Info ("  ダウンロード: {0}" -f $t.Url)
        if ($t.WingetId) {
            Write-Info ("  winget でインストール: winget install {0}" -f $t.WingetId)
        }
        $script:MissingTools.Add($t)
    }
}

# ========================================
# サマリ
# ========================================
Write-Title "セットアップ結果"

Write-Host ("  検出/追加済み: {0} / {1}" -f $script:FoundTools.Count, $tools.Count) -ForegroundColor Cyan
foreach ($name in $script:FoundTools) {
    Write-Host ("    [✓] {0}" -f $name) -ForegroundColor Green
}

if ($script:MissingTools.Count -gt 0) {
    Write-Host ""
    Write-Host ("  未検出: {0}" -f $script:MissingTools.Count) -ForegroundColor Red
    foreach ($t in $script:MissingTools) {
        Write-Host ("    [×] {0}" -f $t.Name) -ForegroundColor Red
        Write-Host ("        → {0}" -f $t.Url) -ForegroundColor DarkGray
    }
}

if ($script:AddedDirs.Count -gt 0) {
    Write-Host ""
    Write-Host ("  PATH 追加: {0} 件" -f $script:AddedDirs.Count) -ForegroundColor Cyan
    foreach ($d in $script:AddedDirs) {
        Write-Host ("    + {0}" -f $d) -ForegroundColor Cyan
    }
    Write-Host ""
    Write-Host "  ★ PATH 反映には PowerShell / コマンドプロンプトの再起動が必要です" -ForegroundColor Yellow
}

# ========================================
# winget 自動インストール提案
# ========================================
if ($script:MissingTools.Count -gt 0 -and -not $DryRun) {
    $hasWinget = Get-Command winget -ErrorAction SilentlyContinue
    if ($hasWinget) {
        Write-Host ""
        Write-Host "  winget が利用可能です。未検出ツールを自動インストールしますか?" -ForegroundColor Yellow
        Write-Host "    (y/N): " -ForegroundColor Yellow -NoNewline

        $ans = if ($AutoInstall) { "y" } else { Read-Host }

        if ($ans -match '^[yY]') {
            foreach ($t in $script:MissingTools) {
                if (-not $t.WingetId) { continue }
                Write-Host ""
                Write-Host ("  winget install --id {0}" -f $t.WingetId) -ForegroundColor Cyan
                & winget install --id $t.WingetId `
                    --accept-source-agreements `
                    --accept-package-agreements
            }
            Write-Host ""
            Write-Host "  インストール完了後、setup.bat を再実行して PATH を確認してください" -ForegroundColor Yellow
        }
    } else {
        Write-Host ""
        Write-Info "  winget が利用できないため自動インストールはスキップ"
        Write-Info "  上記 URL から手動でインストールしてください"
    }
}

# ========================================
# 経過時間
# ========================================
$elapsed = (Get-Date) - $startTime
Write-Host ""
Write-Host ("  所要時間: {0:mm\:ss}" -f $elapsed) -ForegroundColor DarkGray

# ========================================
# 終了処理
# ========================================
if ($script:MissingTools.Count -eq 0) {
    Write-Host ""
    Write-Host "  ★ 全ツールが揃っています ★" -ForegroundColor Green

    # diagnose.ps1 呼び出し
    if (-not $SkipDiagnose -and (Test-Path "$PSScriptRoot\diagnose.ps1")) {
        Write-Host ""
        Write-Host "  最終確認のため diagnose.ps1 を実行しますか? (y/N): " -ForegroundColor Yellow -NoNewline
        $ans = Read-Host
        if ($ans -match '^[yY]') {
            Write-Host ""
            & "$PSScriptRoot\diagnose.ps1"
        }
    }

    Write-Host ""
    Write-Host "  次の手順:" -ForegroundColor Yellow
    Write-Host "    1. PowerShell を閉じて開き直す（PATH 反映）" -ForegroundColor Yellow
    Write-Host "    2. .\diagnose.ps1 で最終確認" -ForegroundColor Yellow
    Write-Host "    3. .\run_all.ps1 で本実行" -ForegroundColor Yellow
    exit 0
} else {
    Write-Host ""
    Write-Host ("  ★ {0} 件のツールが不足しています ★" -f $script:MissingTools.Count) -ForegroundColor Red
    Write-Host "  インストール後、setup.bat を再実行してください" -ForegroundColor Yellow
    exit 1
}