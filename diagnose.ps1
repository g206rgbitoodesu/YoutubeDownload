# ========================================
# 音楽ライブラリ自動構築システム 診断ツール
# ========================================
# 用途:
#   - 依存ツール（yt-dlp/ffmpeg/ffprobe/fpcalc/Picard）の存在確認
#   - Picard の設定ファイルから fpcalc パス・AcoustID キーを確認
#   - music_download 内の壊れたファイル検出
#   - Picard プロセスの起動状態確認
# ========================================
# 変更点 (v2):
#   - 冒頭でレジストリの PATH を現在のプロセスに再構築
#     （親プロセスが古い環境を持っていても正しく診断できる）
#   - ユーザー PATH に既登録のツールも Get-Command で拾えるように
# ========================================
[CmdletBinding()]
param(
    [string]$TargetDir = "music_download"
)

$ErrorActionPreference = "Continue"
Set-Location -Path $PSScriptRoot

# ========================================
# 事前処理: レジストリから PATH を再構築
# ========================================
# 親プロセス（cmd.exe や古い PowerShell）が古い $env:Path を
# 引き継いでいる場合、ユーザー PATH に登録済みのツールが
# Get-Command で見つからない。ここで Machine + User を
# 結合し直して、常に最新の PATH 状態で診断する。
$machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
$userPath    = [Environment]::GetEnvironmentVariable("Path", "User")
$env:Path    = (@($machinePath, $userPath) | Where-Object { $_ }) -join ';'

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Magenta
    Write-Host ("  " + $Title) -ForegroundColor Magenta
    Write-Host ("=" * 60) -ForegroundColor Magenta
}

function Write-OK    { param([string]$m) Write-Host "  [OK]   $m" -ForegroundColor Green }
function Write-NG    { param([string]$m) Write-Host "  [NG]   $m" -ForegroundColor Red }
function Write-Warn  { param([string]$m) Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function Write-Info  { param([string]$m) Write-Host "  [INFO] $m" -ForegroundColor Gray }

$script:ProblemCount = 0

# ========================================
# 1. 依存ツールの確認
# ========================================
Write-Section "1. 依存ツールの確認"

$tools = @(
    @{ Name = "yt-dlp";  Cmd = "yt-dlp";  Required = $true },
    @{ Name = "ffmpeg";  Cmd = "ffmpeg";  Required = $true },
    @{ Name = "ffprobe"; Cmd = "ffprobe"; Required = $true },
    @{ Name = "fpcalc";  Cmd = "fpcalc";  Required = $true },
    @{ Name = "python";  Cmd = "python";  Required = $false }
)

foreach ($t in $tools) {
    $cmd = Get-Command $t.Cmd -ErrorAction SilentlyContinue
    if ($cmd) {
        $ver = ""
        try {
            # fpcalc は --version 非対応。-version のみ受け付ける
            $verArg = if ($t.Cmd -eq "fpcalc") { "-version" } else { "--version" }
            $ver = (& $t.Cmd $verArg 2>&1 | Select-Object -First 1) -replace '\s+',' '
            if ($ver.Length -gt 60) { $ver = $ver.Substring(0,60) + "..." }
        } catch { }
        Write-OK ("{0,-8} → {1}" -f $t.Name, $cmd.Source)
        if ($ver) { Write-Info ("         {0}" -f $ver) }
    } else {
        if ($t.Required) {
            Write-NG ("{0,-8} → PATH に見つかりません（必須）" -f $t.Name)
            $script:ProblemCount++
        } else {
            Write-Warn ("{0,-8} → PATH に見つかりません（任意）" -f $t.Name)
        }
    }
}

# ========================================
# 2. fpcalc 詳細診断（PATH + 自動探索）
# ========================================
Write-Section "2. fpcalc 詳細診断"

$fpcalcCmd = Get-Command fpcalc -ErrorAction SilentlyContinue
$fpcalcPath = $null

if ($fpcalcCmd) {
    $fpcalcPath = $fpcalcCmd.Source
    Write-OK ("fpcalc の場所（PATH）: {0}" -f $fpcalcPath)
} else {
    Write-Warn "PATH 上に fpcalc がありません。一般的な場所を探索します..."

    $searchRoots = @(
        "$env:USERPROFILE\Downloads",
        "$env:USERPROFILE\Documents",
        "$env:USERPROFILE\Desktop",
        "C:\Program Files",
        "C:\Program Files (x86)",
        "C:\ffmpeg",
        "C:\tools",
        "$env:LOCALAPPDATA\Microsoft\WinGet\Packages",
        "$env:USERPROFILE\Downloads\navidrome"
    )

    foreach ($root in $searchRoots) {
        if (-not (Test-Path $root)) { continue }
        $found = Get-ChildItem -Path $root -Filter "fpcalc.exe" -Recurse -File -ErrorAction SilentlyContinue |
                 Select-Object -First 1
        if ($found) {
            $fpcalcPath = $found.FullName
            Write-OK ("fpcalc の場所（自動探索）: {0}" -f $fpcalcPath)
            Write-Warn "  ※ PATH に含まれていないため Picard から使えません"
            Write-Info "  → .\fix_fpcalc.ps1 を実行して PATH に追加してください"
            break
        }
    }

    if (-not $fpcalcPath) {
        Write-NG "fpcalc が PATH にも一般的な場所にもありません"
        Write-Info "  Chromaprint を https://acoustid.org/chromaprint からダウンロードして配置してください"
        $script:ProblemCount++
    }
}

if ($fpcalcPath) {
    # 実際に実行できるか
    try {
        $verOut = & $fpcalcPath -version 2>&1
        Write-OK ("fpcalc -version: {0}" -f ($verOut -join " "))
    } catch {
        Write-NG ("fpcalc 実行時にエラー: {0}" -f $_)
        $script:ProblemCount++
    }

    # テスト音源でフィンガープリント生成テスト
    $testFile = Get-ChildItem -Path $TargetDir -Filter "*.mp3" -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Length -gt 1MB } | Select-Object -First 1
    if ($testFile) {
        Write-Info ("テスト対象: {0}" -f $testFile.Name)
        $fpOut = & $fpcalcPath -json $testFile.FullName 2>&1
        $fpExit = $LASTEXITCODE
        if ($fpExit -eq 0 -and $fpOut) {
            Write-OK "fpcalc 実行テスト: 成功"
        } else {
            Write-NG ("fpcalc 実行テスト: 失敗 (exit={0})" -f $fpExit)
            Write-Info ("  出力: {0}" -f ($fpOut -join " / "))
            $script:ProblemCount++
        }
    } else {
        Write-Warn "テスト用 mp3 が見つからないため、実行テストはスキップ"
    }
}

# ========================================
# 3. Picard の確認
# ========================================
Write-Section "3. MusicBrainz Picard の確認"

$picardPath = "C:\Program Files\MusicBrainz Picard\picard.exe"
if (Test-Path $picardPath) {
    Write-OK ("Picard: {0}" -f $picardPath)
} else {
    Write-NG ("Picard が見つかりません: {0}" -f $picardPath)
    $script:ProblemCount++
}

# Picard プロセスの確認
$proc = Get-Process -Name "picard" -ErrorAction SilentlyContinue
if ($proc) {
    Write-Warn ("Picard が起動中 (PID: {0})" -f (($proc | ForEach-Object { $_.Id }) -join ", "))
    Write-Info "  処理を進めるには終了してください: Get-Process picard | Stop-Process -Force"
} else {
    Write-OK "Picard は起動していません（スクリプト実行可能）"
}

# ========================================
# 4. Picard 設定ファイルの確認（重要）
# ========================================
Write-Section "4. Picard 設定ファイルの確認"

$configPaths = @(
    "$env:APPDATA\MusicBrainz\Picard\Picard.ini",
    "$env:LOCALAPPDATA\MusicBrainz\Picard\Picard.ini",
    "$env:USERPROFILE\AppData\Roaming\MusicBrainz\Picard\Picard.ini"
)

$configFound = $null
foreach ($p in $configPaths) {
    if (Test-Path $p) { $configFound = $p; break }
}

if ($configFound) {
    Write-OK ("設定ファイル: {0}" -f $configFound)

    $ini = Get-Content -Path $configFound -Encoding UTF8 -Raw

    # fpcalc パスの設定確認
    if ($ini -match 'fpcalc_path\s*=\s*(.+)') {
        $fpc = $matches[1].Trim()
        if (Test-Path $fpc) {
            Write-OK ("  fpcalc_path: {0}" -f $fpc)
        } else {
            Write-NG ("  fpcalc_path が指すファイルが存在しない: {0}" -f $fpc)
            $script:ProblemCount++
        }
    } else {
        Write-Warn "  fpcalc_path が未設定（Picard が自動検出を試みます）"
        Write-Info "  → GUI の オプション → 指紋 で設定推奨"
    }

    # AcoustID API キー確認
    if ($ini -match 'acoustid_api_key\s*=\s*(.+)') {
        $key = $matches[1].Trim()
        if ($key -and $key.Length -gt 10) {
            Write-OK ("  acoustid_api_key: 設定済み ({0}...)" -f $key.Substring(0,[Math]::Min(8,$key.Length)))
        } else {
            Write-NG "  acoustid_api_key が空または短すぎる"
            $script:ProblemCount++
        }
    } else {
        Write-NG "  acoustid_api_key が未設定"
        Write-Info "  → https://acoustid.org/new-application で取得し、Picard に設定"
        $script:ProblemCount++
    }
} else {
    Write-Warn "Picard の設定ファイルが見つかりません"
    Write-Info "  検索パス:"
    foreach ($p in $configPaths) { Write-Info ("    {0}" -f $p) }
    Write-Info "  → Picard を一度起動して設定を保存するとファイルが生成されます"
}

# ========================================
# 5. music_download の壊れたファイル検出
# ========================================
Write-Section "5. music_download の壊れたファイル検出"

if (-not (Test-Path $TargetDir)) {
    Write-Warn ("{0} が見つかりません（初回実行時は正常）" -f $TargetDir)
    Write-Info "  → download_pc.ps1 を実行すると自動作成されます"
} else {
    $files = Get-ChildItem -Path $TargetDir -Recurse -File -Include *.mp3,*.m4a,*.flac,*.opus
    $broken = New-Object System.Collections.Generic.List[object]
    $ok     = 0

    foreach ($f in $files) {
        # ffprobe で検査
        $null = & ffprobe -v quiet -print_format json -show_format $f.FullName 2>$null
        if ($LASTEXITCODE -ne 0) {
            $broken.Add($f)
        } else {
            $ok++
        }
    }

    Write-Info ("検査対象: {0} ファイル" -f @($files).Count)
    Write-OK   ("正常: {0}" -f $ok)

    if ($broken.Count -gt 0) {
        Write-NG ("壊れたファイル: {0}" -f $broken.Count)
        foreach ($b in $broken) {
            Write-Host ("    - {0}  ({1} bytes)" -f $b.Name, $b.Length) -ForegroundColor Red
        }
        Write-Info "  削除コマンド:"
        Write-Info ("    Get-ChildItem '{0}' -Recurse -File | Where-Object {{ (ffprobe -v quiet -show_format `$_ 2>`$null) ; `$LASTEXITCODE -ne 0 }} | Remove-Item -Force" -f $TargetDir)
        $script:ProblemCount++
    } else {
        Write-OK "壊れたファイルはありません"
    }
}

# ========================================
# 6. ディスク空き容量
# ========================================
Write-Section "6. ディスク空き容量"

$drive = (Get-Item $PSScriptRoot).PSDrive
$free = [Math]::Round($drive.Free / 1GB, 2)
Write-Info ("{0}: 空き {1} GB" -f $drive.Name, $free)
if ($free -lt 5) {
    Write-Warn "空き容量が少ないです"
} else {
    Write-OK "十分な空き容量があります"
}

# ========================================
# 7. 総合判定
# ========================================
Write-Section "診断結果"

if ($script:ProblemCount -eq 0) {
    Write-Host ""
    Write-Host "  ★ 問題は見つかりませんでした ★" -ForegroundColor Green
    Write-Host ""
    exit 0
} else {
    Write-Host ""
    Write-Host ("  ★ {0} 件の問題が見つかりました ★" -f $script:ProblemCount) -ForegroundColor Red
    Write-Host ""
    Write-Host "  上記の [NG] / [WARN] を確認してください。" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}