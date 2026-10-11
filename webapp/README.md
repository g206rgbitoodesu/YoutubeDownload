# 🎵 Web申請フォーム

スマホのブラウザから楽曲を申請し、PC上で自動的にダウンロード → タグ付け → Navidrome配置まで実行するWeb UI。

## セットアップ

```powershell
cd C:\Users\<ユーザー名>\Documents\YoutubeDownload\webapp
python -m pip install -r requirements.txt
```

## 起動

`start.bat` をダブルクリック。

起動後、コンソールに表示される **スマホ用URL** にアクセス:

```
http://192.168.x.x:5000
```

## 使い方

1. ブラウザでフォームを開く
2. アーティスト / 曲名 / (任意)YouTube URL を入力
3. 「申請する」をクリック
4. 処理状況がリアルタイムで表示される
5. 「done」になったら、Navidrome で Quick scan

## 仕組み

```
[スマホ] ──WiFi──→ Flask (/submit)
                        │
                        ├─ songlist.csv に追記
                        └─ run_all.ps1 をバックグラウンド起動
                              │
                              ├─ make_todo.ps1 で未DL曲のみ抽出
                              ├─ yt-dlp でダウンロード
                              ├─ Picard で タグ付け
                              └─ Navidrome へ移動
```

`make_todo.ps1` が **既DL曲を自動スキップ** するため、何度申請しても安全です。

## セキュリティ

- **家庭内LAN専用**。ルーターのポートフォワード設定は **絶対にしない** でください。
- 初回起動時に Windows Firewall の警告が出たら、**「プライベートネットワーク」のみ許可**、パブリックはブロック。
- 家族外に使わせたくない場合は Basic 認証を追加できます。

## トラブルシューティング

### スマホからアクセスできない

- PC とスマホが **同じWiFi** に接続されているか確認
- Windows Firewall で Python の通信が許可されているか確認
- ルーターの **AP アイソレーション**（クライアント間通信の遮断）が無効か確認

### Flask のインストールに失敗する

```powershell
python -m pip install --upgrade pip
python -m pip install flask
```

### ポート 5000 が使用中

`app.py` の最後の `app.run(..., port=5000)` を `port=5001` などに変更。

## アンインストール

`webapp/` フォルダごと削除するだけ。既存のスクリプトには一切影響ありません。