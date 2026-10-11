# ========================================
# YoutubeDownload Web申請フォーム (v3)
# ========================================
# 変更点 (v3):
#   - PowerShell の出力を job.log にリダイレクトし、
#     Python はそれを tail する方式に変更
#     → パイプのバッファリング問題を回避
#     → スマホ画面で進捗がリアルタイムに見える
# ========================================
from flask import Flask, render_template, request, jsonify
import subprocess
import csv
import io
import threading
import socket
import sys
import time
from datetime import datetime
from pathlib import Path
from collections import deque

# ----------------------------------------
# パス定義
# ----------------------------------------
BASE_DIR      = Path(__file__).resolve().parent.parent
CSV_FILE      = BASE_DIR / "songlist.csv"
PLAYLIST_FILE = BASE_DIR / "playlist.txt"
RUN_ALL       = BASE_DIR / "run_all.ps1"
LOG_FILE      = Path(__file__).resolve().parent / "job.log"

for p in (CSV_FILE, PLAYLIST_FILE, RUN_ALL):
    if not p.exists():
        print(f"[ERROR] {p} が見つかりません", file=sys.stderr)
        sys.exit(1)

# ----------------------------------------
# グローバル状態
# ----------------------------------------
state_lock = threading.Lock()
current_job = {
    "id": None,
    "mode": None,           # "csv" | "playlist"
    "status": "idle",       # idle | running | done | failed
    "started_at": None,
    "finished_at": None,
    "count": 0,
    "log_tail": [],
    "return_code": None,
}
LOG_TAIL_MAX = 40

app = Flask(__name__)

# ----------------------------------------
# ローカルIP
# ----------------------------------------
def get_local_ip() -> str:
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"


# ----------------------------------------
# プレイリストURL判定
# ----------------------------------------
def is_playlist_url(url: str) -> bool:
    """プレイリストURLかどうか判定"""
    if not url:
        return False
    u = url.lower()
    if "youtube.com/playlist" in u:
        return True
    if "music.youtube.com/playlist" in u:
        return True
    # list= パラメータがあり、watch?v= が無い場合はプレイリスト
    if "list=" in u and "watch?v=" not in u:
        return True
    return False

# ----------------------------------------
# パーサ: 楽曲リスト（CSV モード）
# ----------------------------------------
def parse_bulk_csv(text: str) -> tuple:
    """
    (songs, playlist_urls) のタプルを返す。
    songs: (artist, title, url) のリスト
    playlist_urls: 検出されたプレイリストURLのリスト（CSVモードでは拒否）
    """
    songs = []
    playlist_urls = []

    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        try:
            parts = next(csv.reader(io.StringIO(line)))
        except Exception:
            parts = [line]
        parts = [p.strip() for p in parts]

        if len(parts) == 1:
            v = parts[0]
            if v.startswith(("http://", "https://")):
                if is_playlist_url(v):
                    playlist_urls.append(v)
                else:
                    songs.append(("", "", v))
            else:
                songs.append(("", v, ""))
        elif len(parts) == 2:
            songs.append((parts[0], parts[1], ""))
        else:
            artist, title, url = parts[0], parts[1], parts[2]
            if url and is_playlist_url(url):
                playlist_urls.append(url)
            else:
                songs.append((artist, title, url))

    songs = [r for r in songs if r[1] or r[2]]
    return songs, playlist_urls
# ----------------------------------------
# パーサ: プレイリスト（URL モード）
# ----------------------------------------
def parse_bulk_playlist(text: str) -> list:
    urls = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith(("http://", "https://")):
            urls.append(line)
    return urls

# ----------------------------------------
# 追記処理
# ----------------------------------------
def append_songs(rows: list) -> None:
    with open(CSV_FILE, "a", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        for artist, title, url in rows:
            w.writerow([artist, title, url])

def append_playlists(urls: list) -> None:
    # BOM 重複を避けるため、追記時は utf-8（BOMなし）を使う
    with open(PLAYLIST_FILE, "a", encoding="utf-8", newline="") as f:
        for u in urls:
            f.write(u + "\n")

# ----------------------------------------
# job.log tail スレッド
# ----------------------------------------
def tail_log_loop(stop_event: threading.Event):
    """job.log の新着行を読み続ける"""
    last_pos = 0
    tail = deque(maxlen=LOG_TAIL_MAX)

    while not stop_event.is_set():
        if LOG_FILE.exists():
            try:
                with open(LOG_FILE, "r", encoding="utf-8", errors="replace") as f:
                    f.seek(last_pos)
                    new_lines = f.readlines()
                    last_pos = f.tell()

                if new_lines:
                    for line in new_lines:
                        tail.append(line.rstrip())
                    with state_lock:
                        current_job["log_tail"] = list(tail)
            except Exception:
                pass

        time.sleep(0.5)

# ----------------------------------------
# パイプライン実行
# ----------------------------------------
def run_pipeline(mode: str):
    global current_job
    try:
        args = [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", str(RUN_ALL),
            "-NoPause",
        ]
        if mode == "playlist":
            args += ["-Source", "playlist"]

        # ログファイルを初期化
        with open(LOG_FILE, "w", encoding="utf-8"):
            pass

        # tail スレッド開始
        stop_event = threading.Event()
        tail_thread = threading.Thread(
            target=tail_log_loop, args=(stop_event,), daemon=True
        )
        tail_thread.start()

        # 出力をログファイルに直接リダイレクト
        with open(LOG_FILE, "a", encoding="utf-8", errors="replace") as log_fp:
            proc = subprocess.Popen(
                args,
                cwd=str(BASE_DIR),
                stdout=log_fp,
                stderr=subprocess.STDOUT,
            )
            proc.wait()
            rc = proc.returncode

        # tail 停止
        stop_event.set()
        tail_thread.join(timeout=2)

        # 最終行を読み込む
        try:
            with open(LOG_FILE, "r", encoding="utf-8", errors="replace") as f:
                lines = f.readlines()[-LOG_TAIL_MAX:]
            with state_lock:
                current_job["log_tail"] = [l.rstrip() for l in lines]
        except Exception:
            pass

        with state_lock:
            current_job["return_code"] = rc
            current_job["status"] = "done" if rc == 0 else "failed"
            current_job["finished_at"] = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    except Exception as e:
        with state_lock:
            current_job["status"] = "failed"
            current_job["log_tail"].append(f"[EXCEPTION] {e}")
            current_job["finished_at"] = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

# ----------------------------------------
# ルーティング
# ----------------------------------------
@app.route("/")
def index():
    return render_template("index.html", local_ip=get_local_ip())

@app.route("/submit", methods=["POST"])
def submit():
    global current_job

    mode = (request.form.get("mode") or "csv").strip().lower()
    body = request.form.get("body") or ""

    if mode not in ("csv", "playlist"):
        return jsonify({"ok": False, "msg": "不正なモードです"}), 400

    if mode == "csv":
        items, bad_playlists = parse_bulk_csv(body)
        if bad_playlists:
            return jsonify({
                "ok": False,
                "msg": f"プレイリストURLが {len(bad_playlists)} 件含まれています。"
                       f"『🎵 プレイリスト』タブから申請してください。"
            }), 400
        if not items:
            return jsonify({"ok": False, "msg": "有効な楽曲がありません"}), 400
    else:
        items = parse_bulk_playlist(body)
        if not items:
            return jsonify({"ok": False, "msg": "有効なURLがありません"}), 400


    with state_lock:
        if current_job["status"] == "running":
            return jsonify({
                "ok": False,
                "msg": "別の処理が実行中です。完了後にもう一度お試しください。"
            }), 409

        try:
            if mode == "csv":
                append_songs(items)
            else:
                append_playlists(items)
        except Exception as e:
            return jsonify({"ok": False, "msg": f"書き込み失敗: {e}"}), 500

        job_id = datetime.now().strftime("%Y%m%d%H%M%S")
        current_job = {
            "id": job_id,
            "mode": mode,
            "status": "running",
            "started_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "finished_at": None,
            "count": len(items),
            "log_tail": [],
            "return_code": None,
        }

    t = threading.Thread(target=run_pipeline, args=(mode,), daemon=True)
    t.start()

    unit = "曲" if mode == "csv" else "URL"
    return jsonify({
        "ok": True,
        "msg": f"{len(items)} {unit}を申請しました",
        "job_id": job_id,
        "count": len(items),
    })

@app.route("/status")
def status():
    with state_lock:
        return jsonify(current_job)

# ----------------------------------------
# 起動
# ----------------------------------------
if __name__ == "__main__":
    ip = get_local_ip()
    print("=" * 60)
    print("  🎵 YoutubeDownload Web申請フォーム v3")
    print("=" * 60)
    print(f"  ローカル: http://127.0.0.1:5000")
    print(f"  スマホ  : http://{ip}:5000")
    print("=" * 60)
    print("  終了: Ctrl + C")
    print()
    app.run(host="0.0.0.0", port=5000, debug=False, threaded=True)