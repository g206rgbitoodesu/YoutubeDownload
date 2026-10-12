# YoutubeDownload

YouTube から音楽をダウンロードし、MusicBrainz Picard で高精度なタグ付けを行い、Navidrome サーバーの音楽フォルダへ自動配置する PowerShell スクリプト群。

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://docs.microsoft.com/powershell/)
[![Platform](https://img.shields.io/badge/platform-Windows%2010%2F11-lightgrey.svg)]()
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

---

##  目次

1. [システム概要](#1-システム概要)
2. [動作環境](#2-動作環境)
3. [クイックスタート](#3-クイックスタート)
4. [手動セットアップ](#4-手動セットアップ)
5. [使い方](#5-使い方)
6. [ディレクトリ構造](#6-ディレクトリ構造)
7. [スクリプト一覧](#7-スクリプト一覧)
8. [各スクリプトの詳細](#8-各スクリプトの詳細)
9. [ワークフロー例](#9-ワークフロー例)
10. [トラブルシューティング](#10-トラブルシューティング)
11. [既知の制約](#11-既知の制約)
12. [ライセンス](#12-ライセンス)

---

#  Web申請フォーム

> ** v2 新機能**: 一括入力（複数曲・プレイリストURL同時対応）とリアルタイム進捗表示に対応しました。

スマホのブラウザから楽曲・プレイリストをまとめて申請し、PC上で自動的にダウンロード → タグ付け → Navidrome配置まで実行するWeb UI。

...

## 1. システム概要

### 全体フロー

```
songlist.csv / playlist.txt
    │
    ▼
[1] download_pc.ps1 / download_playlist.ps1   ← yt-dlp ダウンロード
    │
    ▼
music_download/                                ← 一時保存
    │
    ▼
[2] verify_downloads.ps1                       ← ffprobe 整合性検査
    │  NG があれば
    ▼
[3] redownload_failed.ps1                      ← 再ダウンロード
    │
    ▼
[4] run_picard.ps1                             ← Picard タグ付け・移動
    │
    ▼
[5] clean_music_download.ps1                   ← 残った曲のファイル名整形
    │
    ▼
[6] run_picard.ps1 (再)                        ← 再マッチング
    │
    ▼
[7] move_leftovers.ps1                         ← 残りを Navidrome へ直接移動
    │
    ▼
Navidrome music フォルダ → Quick scan
```

---

## 2. 動作環境

### 必須ツール

| ツール | 用途 | 入手先 |
|---|---|---|
| **yt-dlp** | YouTube ダウンロード | https://github.com/yt-dlp/yt-dlp |
| **ffmpeg / ffprobe** | 音声変換・整合性検査 | https://ffmpeg.org/ |
| **MusicBrainz Picard** | タグ付け | https://picard.musicbrainz.org/ |
| **Chromaprint (fpcalc)** | 音声指紋 | https://acoustid.org/chromaprint |
| **AcoustID API キー** | Picard の音声指紋認証 | https://acoustid.org/new-application |

### 推奨環境

- Windows 10 / 11
- PowerShell 5.1 以上（Windows 標準）
- Navidrome サーバー（既に稼働中を想定）

---

## 3. クイックスタート

### 3-1. リポジトリを配置

任意のフォルダに配置します。例:

```
C:\Users\<ユーザー名>\Documents\YoutubeDownload
```

### 3-2. `setup.bat` をダブルクリック

**これだけ** で以下が自動実行されます:

1. yt-dlp / ffmpeg / ffprobe / fpcalc / Picard の存在確認
2. PATH 未登録のツールを一般的な場所から自動探索
3. 見つかったツールをユーザー PATH に永続追加
4. 未検出ツールがあれば `winget` で自動インストール提案
5. 最後に `diagnose.ps1` による環境診断

### 3-3. PowerShell を再起動

PATH 反映のため、一度 PowerShell を閉じて開き直します。

### 3-4. 一括実行

```powershell
cd C:\Users\<ユーザー名>\Documents\YoutubeDownload
.\run_all.ps1
```

完了後、Navidrome 管理画面で **Quick scan** を実行してください。

---

## 4. 手動セットアップ

`setup.bat` が使えない環境向け。上級者向けの手順です。

### 4-1. 作業フォルダ作成

```powershell
mkdir C:\Users\<ユーザー名>\Documents\YoutubeDownload
cd C:\Users\<ユーザー名>\Documents\YoutubeDownload
```

### 4-2. スクリプト群を配置

本リポジトリの全ファイルを上記フォルダに配置。

### 4-3. 環境診断

```powershell
.\diagnose.ps1
```

すべて `[OK]` になることを確認。`[NG]` があれば該当ツールをインストール。

### 4-4. fpcalc の個別セットアップ（PATH 未設定の場合）

```powershell
.\fix_fpcalc.ps1 -DryRun    # まず確認
.\fix_fpcalc.ps1            # 本実行（PATH 永続化）
```

PowerShell を再起動して反映。

### 4-5. Picard GUI 設定（手動）

Picard を起動し、以下を設定してください。

1. **オプション → ファイル名設定**
   - 「Move files to a folder structure based on tags」を **ON**
   - 移動先を Navidrome music フォルダに指定
2. **オプション → 指紋**
   - `fpcalc の場所` に `fpcalc.exe` のフルパスを指定
   - AcoustID API キーを入力
3. 設定を保存して Picard を終了

---

## 5. 使い方

### 5-1. 入力ファイルの準備

**songlist.csv**（CSV モード）

```csv
アーティスト,曲名,URL
サカナクション,新宝島,
Queen,Bohemian Rhapsody,https://youtu.be/fJ9rUzIMcZQ
```

- URL を空にすると `ytsearch1:アーティスト 曲名` で自動検索
- カンマを含む曲名は `"..."` で囲む

**playlist.txt**（プレイリストモード）

```
https://www.youtube.com/playlist?list=XXXXXXXX
```

- 1行1URL
- `#` で始まる行はコメント

### 5-2. 一括実行（推奨）

```powershell
.\run_all.ps1
```

### 5-3. よく使うオプション

```powershell
# DryRun（書き込みせず計画だけ確認）
.\run_all.ps1 -DryRun

# 途中から（既にDL済みのとき）
.\run_all.ps1 -StartFrom 6

# 特定ステップをスキップ
.\run_all.ps1 -SkipSteps 3,4

# 確認プロンプトなしで一気に
.\run_all.ps1 -NoPause

# プレイリストモード
.\run_all.ps1 -Source playlist
```

---

## 6. ディレクトリ構造

```
YoutubeDownload/
├── setup.bat                    # ★ 初回セットアップ（ダブルクリック）
├── setup_env.ps1                #   環境自動探索・PATH追加
├── check_syntax.ps1             #   全 .ps1 構文チェック
├── sanitize_for_release.ps1     #   公開用サニタイズ
│
├── run_all.ps1                  # ★ 統合フロー（推奨エントリ）
├── pipeline.ps1                 #   旧版オーケストレーター
│
├── download_pc.ps1              #   CSV一括DL
├── download_playlist.ps1        #   プレイリスト一括DL
├── verify_downloads.ps1         #   整合性検査
├── redownload_failed.ps1        #   NG曲の再DL
├── run_picard.ps1               #   Picard 起動
├── clean_music_download.ps1     #   ファイル名整形
├── move_leftovers.ps1           #   残りを Navidrome へ移動
├── dedup_music.ps1              #   重複統合
├── enrich_tags.ps1              #   NA タグ補完
├── clean_songlist.ps1           #   CSV 整形
├── make_todo.ps1                #   未DL曲抽出
├── diagnose.ps1                 #   環境診断
├── fix_fpcalc.ps1               #   fpcalc 個別セットアップ
│
├── picard_commands.txt          #   Picard コマンド列
├── songlist.csv                 #   入力データ
├── playlist.txt                 #   入力データ（プレイリスト）
│
├── music_download/              #   一時保存（自動生成）
├── downloaded.txt               #   DL済みアーカイブ（自動生成）
├── downloaded_playlist.txt      #   プレイリスト用アーカイブ
├── success.log / failed.log     #   CSVログ
├── success_playlist.log / failed_playlist.log
├── verify_ok.txt / verify_ng.txt
├── duplicates_backup/           #   重複退避
│
├── _sanitize_backup/            #   サニタイズ時の自動バックアップ
├── backup/                      #   clean_songlist のバックアップ
│
├── README.md                    #   本ファイル
├── LICENSE
└── .gitignore
```

---

## 7. スクリプト一覧

### セットアップ系

| ファイル | 役割 |
|---|---|
| `setup.bat` | **初回セットアップ（ダブルクリック用）** |
| `setup_env.ps1` | 環境自動探索・PATH追加 |
| `diagnose.ps1` | 環境診断 |
| `fix_fpcalc.ps1` | fpcalc 個別セットアップ |
| `check_syntax.ps1` | 全 .ps1 構文チェック |
| `sanitize_for_release.ps1` | 公開用サニタイズ |

### 実行系

| ファイル | 役割 |
|---|---|
| `run_all.ps1` | **統合フロー（推奨）** |
| `pipeline.ps1` | 旧版オーケストレーター（非推奨） |
| `clean_songlist.ps1` | CSV 整形（重複除去・クォート正規化） |
| `make_todo.ps1` | 未DL曲を抽出 |
| `download_pc.ps1` | CSV 一括ダウンロード |
| `download_playlist.ps1` | プレイリスト一括ダウンロード |
| `verify_downloads.ps1` | 整合性検査（ffprobe） |
| `redownload_failed.ps1` | NG 曲を再ダウンロード |
| `run_picard.ps1` | Picard 起動 |
| `clean_music_download.ps1` | ファイル名整形 |
| `move_leftovers.ps1` | 残った曲を Navidrome へ移動 |
| `dedup_music.ps1` | 重複ファイル統合 |
| `enrich_tags.ps1` | NA タグを CSV で補完 |

### 入力ファイル

| ファイル | 説明 |
|---|---|
| `songlist.csv` | アーティスト, 曲名, URL の CSV |
| `playlist.txt` | プレイリスト URL（1行1URL、`#` でコメント） |

---

## 8. 各スクリプトの詳細

### 8-1. `setup.bat` / `setup_env.ps1`

初回セットアップ。`setup.bat` をダブルクリックするだけ。

- 5つのツールを3段階で探索（PATH → 固定パス → 14ルート再帰検索）
- 見つかったものをユーザー PATH に永続追加（管理者不要）
- 未検出ならダウンロードURLと `winget` コマンドを提示
- 最後に `diagnose.ps1` を呼び出して確認

`setup_env.ps1` のオプション:

| 引数 | 説明 |
|---|---|
| `-DryRun` | PATH 書き込みせず確認のみ |
| `-AutoInstall` | winget インストール提案をスキップして自動実行 |
| `-SkipDiagnose` | 完了後の diagnose 呼び出しをスキップ |

### 8-2. `run_all.ps1`（統合フロー・推奨）

9ステップを一括実行します。

```powershell
.\run_all.ps1                   # 通常実行（CSV）
.\run_all.ps1 -Source playlist  # プレイリストモード
.\run_all.ps1 -DryRun           # 計画確認
.\run_all.ps1 -StartFrom 6      # ステップ6から開始
.\run_all.ps1 -SkipSteps 3,4    # 3,4をスキップ
.\run_all.ps1 -NoPause          # プロンプトなし
```

**ステップ一覧:**

| # | スクリプト | 内容 |
|---|---|---|
| 1 | clean_songlist | CSV 整形 |
| 2 | make_todo | 未DL抽出 |
| 3 | download_pc | ダウンロード |
| 4 | verify_downloads | 検査 |
| 5 | redownload_failed | 再DL（NG時のみ） |
| 6 | run_picard | Picard |
| 7 | clean_music_download | ファイル名整形 |
| 8 | run_picard（再） | 再マッチング |
| 9 | move_leftovers | 残り移動 |

### 8-3. `clean_songlist.ps1`

CSV の重複除去・クォート正規化。

```powershell
.\clean_songlist.ps1            # 確認用出力
.\clean_songlist.ps1 -InPlace   # 元ファイルを上書き（バックアップ自動作成）
```

| 引数 | デフォルト | 説明 |
|---|---|---|
| `-CsvFile` | songlist.csv | 入力 |
| `-OutFile` | songlist_clean.csv | 出力 |
| `-BackupDir` | backup | バックアップ先 |
| `-InPlace` | off | 元ファイル上書き |

### 8-4. `make_todo.ps1`

未ダウンロード曲のみ抽出。

```powershell
.\make_todo.ps1
.\make_todo.ps1 -ShowDone   # DL済みも表示
```

| 引数 | デフォルト |
|---|---|
| `-CsvFile` | songlist.csv |
| `-DoneLogs` | @("success.log") |
| `-ScanFolders` | music_download, Navidrome |
| `-OutFile` | songlist_todo.csv |
| `-TitleOnly` | off |
| `-ShowDone` | off |

### 8-5. `download_pc.ps1`

CSV 一括ダウンロード。

```powershell
.\download_pc.ps1                  # 通常
.\download_pc.ps1 -StartIndex 88   # 88行目から再開
.\download_pc.ps1 -Force           # 強制再DL
.\download_pc.ps1 -SkipPicard      # Picard スキップ
```

| 引数 | デフォルト | 説明 |
|---|---|---|
| `-CsvFile` | songlist.csv | 入力 |
| `-OutputDir` | music_download | 出力 |
| `-ArchiveFile` | downloaded.txt | アーカイブ |
| `-SleepTime` | 5 | 曲間ウェイト（秒） |
| `-MaxRetries` | 2 | リトライ回数 |
| `-StartIndex` | 1 | 開始行 |
| `-Force` | off | アーカイブ無視 |
| `-SkipPicard` | off | Picard スキップ |

### 8-6. `download_playlist.ps1`

プレイリスト一括ダウンロード。

```powershell
.\download_playlist.ps1
.\download_playlist.ps1 -StartIndex 2
```

| 引数 | デフォルト |
|---|---|
| `-PlaylistFile` | playlist.txt |
| `-OutputDir` | music_download |
| `-ArchiveFile` | downloaded_playlist.txt |
| `-SleepTime` | 5 |
| `-MaxRetries` | 2 |

### 8-7. `verify_downloads.ps1`

ffprobe で整合性検査。

```powershell
.\verify_downloads.ps1
.\verify_downloads.ps1 -MinDuration 60 -MinBitrate 128   # 厳しめ
```

| 引数 | デフォルト |
|---|---|
| `-TargetDir` | music_download |
| `-MinDuration` | 30 秒 |
| `-MinBitrate` | 64 kbps |
| `-MinSizeKB` | 100 KB |

**終了コード**: `0`=OK / `10`=NGあり / `1`=エラー

### 8-8. `redownload_failed.ps1`

NG ファイルを再DL（`download_pc.ps1 -Force` の薄いラッパー）。

```powershell
.\redownload_failed.ps1
```

| 引数 | デフォルト |
|---|---|
| `-NgFile` | verify_ng.txt |
| `-NgCsv` | songlist_ng.csv |

### 8-9. `run_picard.ps1`

Picard を起動し、`picard_commands.txt` を実行。

```powershell
.\run_picard.ps1
```

- Picard 二重起動チェックあり（起動中なら exit=2）

### 8-10. `clean_music_download.ps1`

ファイル名から装飾を除去。

```powershell
.\clean_music_download.ps1 -DryRun   # 確認
.\clean_music_download.ps1           # 本実行
```

例:

```
Queen - Queen - A Kind of Magic (Official Video Remastered).mp3
   → Queen - A Kind of Magic.mp3
```

### 8-11. `move_leftovers.ps1`

Picard で処理しきれなかった曲を、タグ情報から Navidrome フォルダへ直接移動。

```powershell
.\move_leftovers.ps1 -DryRun   # 計画確認
.\move_leftovers.ps1           # 本実行
```

| 引数 | デフォルト |
|---|---|
| `-SourceDir` | music_download |
| `-DestDir` | Navidrome music フォルダ |
| `-DryRun` | off |
| `-Force` | off |

### 8-12. `dedup_music.ps1`

Navidrome フォルダの重複ファイル（`(1)`, `(2)` 付き）を統合。

```powershell
.\dedup_music.ps1 -DryRun   # 確認
.\dedup_music.ps1           # 本実行（y を入力）
.\dedup_music.ps1 -Force    # プロンプトなし
```

退避先: `duplicates_backup/`

### 8-13. `enrich_tags.ps1`

`artist` / `title` が `NA` の曲を CSV 情報で補完。

```powershell
.\enrich_tags.ps1 -DryRun   # 確認
.\enrich_tags.ps1           # 本実行
```

### 8-14. `diagnose.ps1`

環境診断。7セクション構成。

```powershell
.\diagnose.ps1
```

チェック項目:

- 依存ツール（yt-dlp, ffmpeg, ffprobe, fpcalc, python）
- fpcalc の実行テスト
- Picard の場所・プロセス
- Picard 設定ファイル（`fpcalc_path` / `acoustid_api_key`）
- 壊れたファイル検出（ffprobe）
- ディスク空き容量
- 総合判定

### 8-15. `fix_fpcalc.ps1`

fpcalc を探索して PATH に永続追加。

```powershell
.\fix_fpcalc.ps1 -DryRun   # 確認
.\fix_fpcalc.ps1           # 本実行
```

### 8-16. `check_syntax.ps1`

全 `.ps1` の構文を一括チェック。バックアップフォルダは自動除外。

```powershell
.\check_syntax.ps1
```

### 8-17. `sanitize_for_release.ps1`

公開用に個人情報（ユーザー名・バージョン付きパス）を除去。

```powershell
.\sanitize_for_release.ps1 -DryRun   # 確認
.\sanitize_for_release.ps1           # 本実行（自動バックアップ）
```

---

## 9. ワークフロー例

### 例1: 新規曲を10曲追加

```powershell
# 1. songlist.csv に追記

# 2. 一括実行
cd C:\Users\<ユーザー名>\Documents\YoutubeDownload
.\run_all.ps1

# 3. Navidrome で Quick scan（ブラウザ）
```

### 例2: 途中でネット切断 → 再開

```powershell
# 88行目から再開
.\download_pc.ps1 -StartIndex 88

# 以降を手動で
.\verify_downloads.ps1
.\run_picard.ps1
.\clean_music_download.ps1
.\run_picard.ps1
.\move_leftovers.ps1
```

### 例3: ダウンロードだけして後で整理

```powershell
.\download_pc.ps1 -SkipPicard
# 次に
.\run_picard.ps1
```

### 例4: 重複が発生したら

```powershell
# 1. 退避（確認）
.\dedup_music.ps1 -DryRun

# 2. 本実行
.\dedup_music.ps1

# 3. 問題なければ退避フォルダ削除
Remove-Item .\duplicates_backup -Recurse -Force
```

---

## 10. トラブルシューティング

### ❌ ツールが見つからない / PATH が通っていない

```powershell
.\setup_env.ps1 -DryRun    # 探索のみ
.\setup_env.ps1            # PATH 追加
# PowerShell 再起動
.\diagnose.ps1             # 再確認
```

### ❌ `fpcalc` が見つからない

```powershell
.\diagnose.ps1
.\fix_fpcalc.ps1
# PowerShell 再起動
.\diagnose.ps1
```

### ❌ Picard が `Unknown command: LOOKUP_CLUSTERED`

`picard_commands.txt` の `LOOKUP_CLUSTERED` を `LOOKUP` に修正。

### ❌ Picard が動かない（二重起動）

```powershell
Get-Process picard | Stop-Process -Force
.\run_picard.ps1
```

### ❌ `artist=NA` になる

`download_pc.ps1` の `--parse-metadata` 引数を確認。

```powershell
# ❌ 悪い例
--parse-metadata "Queen:%(meta_artist)s"

# ✅ 良い例
--parse-metadata "%(artist,uploader,channel,creator)s:%(meta_artist)s"
```

### ❌ ヘッダー行を処理してしまう

CSV 読み込みで `$RawLines = @(...)` と配列化してあるか確認。

### ❌ Navidrome に曲が反映されない

Navidrome 管理画面 → **Quick scan** を実行。

### ❌ ファイルが `(1)` `(2)` で重複

```powershell
.\dedup_music.ps1 -DryRun
.\dedup_music.ps1
```

### ❌ 構文エラーが出る

```powershell
.\check_syntax.ps1
```

バックアップフォルダは自動除外されます。

---


---

## 10.5. Web 申請フォーム（ローカルサーバー）

v2 から、**スマホのブラウザから楽曲を申請**できるようになりました。PCの前でコマンドを打つ必要はありません。

### クイックスタート

```powershell
cd C:\Users\<ユーザー名>\Documents\YoutubeDownload\webapp
python -m pip install -r requirements.txt
.\start.bat
```

起動後、スマホで `http://<PCのIP>:5000` にアクセス（同じWi-Fi内）。

### できること

- **一括入力**: 複数曲・複数プレイリストURLをまとめて貼り付け
- **2つのモード**: 楽曲リスト（CSV）/ プレイリストURL
- **リアルタイム進捗**: ダウンロード・タグ付けの進行状況をスマホで確認
- **完全自動**: 申請からNavidrome配置まで `run_all.ps1` が処理

### 仕組み

```
[スマホ] ──WiFi──→ Flask (port 5000)
                       │
                       ├─ songlist.csv / playlist.txt に追記
                       └─ run_all.ps1 をバックグラウンド起動
                             │
                             ├─ make_todo.ps1 (DL済み自動スキップ)
                             ├─ yt-dlp ダウンロード
                             ├─ Picard タグ付け
                             └─ Navidrome へ移動
```

### セキュリティ

- **家庭内LAN専用**: ポート5000をインターネットに公開しない
- **Firewall**: 初回起動時は「プライベートネットワーク」のみ許可
- 詳細は `webapp/README.md` 参照

---

## 11. 既知の制約

| 項目 | 内容 |
|---|---|
| **Picard 移動先** | GUI 設定依存（スクリプトから制御不可） |
| **アーカイブ分離** | CSV 用とプレイリスト用が別管理 |
| **AcoustID** | API キー未設定だと FINGERPRINT/SCAN が無言で失敗 |
| **`:`, `%` を含むアーティスト名** | `--parse-metadata` で注意が必要 |
| **プレイリストの MV** | 公式 MV が多く Picard がマッチしにくい |
| **`(N)` 重複** | 同曲を複数回 DL すると発生 → `dedup_music.ps1` で対処 |

---

## 12. ライセンス

MIT License. 詳細は [LICENSE](LICENSE) を参照してください。

本ツールは個人利用を想定しています。
ダウンロードするコンテンツの著作権は各権利者に帰属します。
利用者は自身の責任で使用してください。

---

---

## ⚠️ 免責事項

### 本プロジェクトは「技術デモ」です

本リポジトリは、**複数のオープンソースツール（yt-dlp / ffmpeg / MusicBrainz Picard / Navidrome）を PowerShell + Python で連携させる自動化技術のデモンストレーション** です。著作権侵害を助長・推奨・幇助する意図は一切ありません。

### 想定用途

主な想定用途は以下のとおりです:

- **自分自身がアップロードした YouTube 動画** のダウンロード
- **明示的にダウンロード許可を得ているコンテンツ** のダウンロード
- **自由にダウンロード可能なライセンス**（Creative Commons、パブリックドメイン等）のコンテンツ
- 本リポジトリで示されている **自動化技術の学習**

### 禁止事項

以下の用途には **使用しないでください**:

- 権利者の許諾なく著作権で保護された楽曲・動画をダウンロードする行為
- DRM・ペイウォール・アクセス制限を回避する行為
- ダウンロードしたコンテンツの再配布
- YouTube 利用規約やその他適用法令への違反

### デフォルト設定: 自分の動画のみ

責任ある利用を徹底するため、**デフォルトでは「自分のチャンネルの動画のみ」ダウンロード可能** に設定されています（`config.ps1` の `$OwnChannelUrls` 参照）。他のソースからダウンロードするには、**明示的にオプトイン** し、自身が適法な権利を有していることを確認する必要があります。

### 無保証

本ソフトウェアは「現状有姿」で提供され、いかなる保証も行いません。作者は以下について **一切の責任を負いません**:

- 誤用によって生じたいかなる法的結果
- システム・データ・ネットワークへの損害
- 本ツールを用いてダウンロードされたあらゆるコンテンツ
- 第三者の利用規約違反

### 著作権表示

本ツールでダウンロードしたコンテンツの著作権は、それぞれの権利者に帰属します。利用者は、自身の利用が以下に準拠していることを **自らの責任で** 確認してください:

- 居住国の著作権法
- YouTube 利用規約
- MusicBrainz / AcoustID の利用ポリシー
- その他適用される法規制

### 法的根拠について

YouTube からのダウンロードは、国によって法的扱いが異なります。**私的利用** が認められている国もあれば、**厳格に禁止** されている国もあります。自国の法律を理解し、遵守するのは利用者の責任です。

### 通報

本リポジトリが違法行為を助長する内容を含むと判断された場合、Issue を作成してください。速やかに対応します。

### 推奨される代替手段

**合法的な音楽ライブラリ構築** には、以下を検討してください:

- **Bandcamp** — アーティストへの直接支援、DRM フリー
- **Jamendo** — Creative Commons ライセンス楽曲
- **Free Music Archive** — パブリックドメイン / CC 楽曲
- **Internet Archive** — パブリックドメイン音源
- **正規購入** — デジタル音楽・フィジカルメディア

---

## 📜 ライセンス

MIT License. 詳細は [LICENSE](LICENSE) を参照してください。

**最終更新**: 2026-10-13

