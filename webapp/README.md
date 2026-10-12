# 🎵 Web申請フォーム

スマホのブラウザから楽曲・プレイリストをまとめて申請し、PC上で自動的にダウンロード → タグ付け → Navidrome配置まで実行するWeb UI。

## セットアップ

```powershell
cd C:\Users\<ユーザー名>\Documents\YoutubeDownload\webapp
python -m pip install -r requirements.txt
```

## 起動

`start.bat` をダブルクリック。起動後、スマホで `http://192.168.x.x:5000` にアクセス。

## 2つのモード

### 📝 楽曲リスト（CSVモード）

1行1曲を `songlist.csv` に追記して `run_all.ps1` を実行。

| 書式 | 例 |
|---|---|
| `アーティスト,曲名` | `Queen,Bohemian Rhapsody` |
| `アーティスト,曲名,URL` | `Queen,Don't Stop Me Now,https://youtu.be/HgzGwKwLmgM` |
| `URL のみ` | `https://youtu.be/fJ9rUzIMcZQ` |
| `曲名のみ` | `Some Song Title` |
| コメント | `# この行は無視される` |

曲名にカンマを含む場合は `"All Dead, All Dead"` のように `"` で囲む。

### 🎵 プレイリスト（URLモード）

1行1URLを `playlist.txt` に追記して `run_all.ps1 -Source playlist` を実行。

```
https://www.youtube.com/playlist?list=PLxxxxxxxx
https://music.youtube.com/playlist?list=OLAK5uy_xxxxxxxx
```

## 一括入力の例

### 楽曲リスト

```
Queen,Bohemian Rhapsody
Queen,Don't Stop Me Now
サカナクション,新宝島
サカナクション,セプテンバー
# 以下はURL指定
Queen,Under Pressure,https://youtu.be/a01QQZyl-_I
# URLだけでもOK
https://youtu.be/fJ9rUzIMcZQ
```

### プレイリスト

```
https://www.youtube.com/playlist?list=PLxxxxxxxx
https://www.youtube.com/playlist?list=PLyyyyyyyy
```

## 仕組み

```
[スマホ] ──WiFi──→ Flask (/submit)
                        │
                        ├─ songlist.csv または playlist.txt に追記
                        └─ run_all.ps1 をバックグラウンド起動
                              │
                              ├─ make_todo.ps1 で未DL曲のみ抽出 (CSVモード)
                              ├─ yt-dlp でダウンロード
                              ├─ Picard で タグ付け
                              └─ Navidrome へ移動
```

`make_todo.ps1` が **既DL曲を自動スキップ**、プレイリストモードは **アーカイブ** で重複DLを防ぐため、何度申請しても安全。

## セキュリティ

- **家庭内LAN専用**。ルーターのポートフォワード設定は **絶対にしない**。
- 初回起動時の Windows Firewall 警告は **「プライベートネットワーク」のみ許可**。

## トラブルシューティング

### スマホからアクセスできない

- PC とスマホが同じWiFiか確認
- Windows Firewall で Python が許可されているか
- ルーターの **APアイソレーション** を無効化

### 送信しても何も起きない

- ブラウザで「処理状況」が出ているか確認
- PC側のコンソールにエラーが出ていないか確認
- `run_all.ps1` 単体で動くかテスト

### 曲が追加されない

- 曲名が空欄になっていないか（`#` コメント行として扱われる）
- カンマ入りの曲名を `"..."` で囲んでいるか