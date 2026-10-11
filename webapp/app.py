# ========================================
# YoutubeDownload Web申請フォーム
# ========================================
# スマホのブラウザから楽曲を申請し、
# バックグラウンドで run_all.ps1 を実行する。
# ========================================
from flask import Flask, render_template, request, jsonify
import subprocess
import csv
import threading
import socket
import os
import sys
from datetime import datetime
from pathlib import Path
from collections import deque

# ----------------------------------------
# パス定義
# ----------------------------------------
BASE_DIR = Path(__file__).resolve().parent.parent   # YoutubeDownload/
CSV_FILE = BASE_DIR / "songlist.csv"
RUN_ALL  = BASE_DIR / "run_all.ps1"

if not CSV_FILE.exists():
    print(f"[ERROR] {CSV_FILE} が見つかりません", file=sys.stderr)
    sys.exit(1)
if not RUN_ALL.exists():
    print(f"[ERROR] {RUN_ALL} が見つかりません", file=sys.stderr)
    sys.exit(1)

# ----------------------------------------
# グローバル状態（1ジョブずつ実行）
# ----------------------------------------
state_lock = threading.Lock()
current_job = {
    "id": None,
    "status": "idle",       # idle | running | done | failed
    "started_at": None,
    "finished_at": None,
    "songs": [],
    "log_tail": [],
    "return_code": None,
}
LOG_TAIL_MAX = 30           # 保持するログ行数

app = Flask(__name__)

# ----------------------------------------
# ローカルIP取得
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
# CSV 追記（既存形式を維持: UTF-8 BOM）
# ----------------------------------------
def append_song(artist: str, title: str, url: str) -> None:
    with open(CSV_FILE, "a", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow([artist, title, url])

# ----------------------------------------
# run_all.ps1 を別スレッドで実行
# ----------------------------------------
def run_pipeline(songs: list):
    global current_job
    try:
        proc = subprocess.Popen(
            [
                "powershell",
                "-NoProfile",
                "-ExecutionPolicy", "Bypass",
                "-File", str(RUN_ALL),
                "-NoPause",
            ],
            cwd=str(BASE_DIR),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
        )

        tail = deque(maxlen=LOG_TAIL_MAX)
        for line in proc.stdout:
            line = line.rstrip()
            tail.append(line)
            with state_lock:
                current_job["log_tail"] = list(tail)

        proc.wait()
        rc = proc.returncode

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
    artist = (request.form.get("artist") or "").strip()
    title  = (request.form.get("title")  or "").strip()
    url    = (request.form.get("url")    or "").strip()

    if not title:
        return jsonify({"ok": False, "msg": "曲名は必須です"}), 400

    with state_lock:
        if current_job["status"] == "running":
            return jsonify({
                "ok": False,
                "msg": "別の処理が実行中です。完了後にもう一度お試しください。"
            }), 409

        # CSV に追記
        try:
            append_song(artist, title, url)
        except Exception as e:
            return jsonify({"ok": False, "msg": f"CSV書き込み失敗: {e}"}), 500

        # ジョブ開始
        job_id = datetime.now().strftime("%Y%m%d%H%M%S")
        current_job = {
            "id": job_id,
            "status": "running",
            "started_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "finished_at": None,
            "songs": [{"artist": artist, "title": title, "url": url}],
            "log_tail": [],
            "return_code": None,
        }

    t = threading.Thread(target=run_pipeline, args=(current_job["songs"],), daemon=True)
    t.start()

    return jsonify({
        "ok": True,
        "msg": f"{artist} - {title} を申請しました",
        "job_id": job_id,
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
    print("  🎵 YoutubeDownload Web申請フォーム")
    print("=" * 60)
    print(f"  ローカル: http://127.0.0.1:5000")
    print(f"  スマホ  : http://{ip}:5000")
    print("=" * 60)
    print("  終了: Ctrl + C")
    print()
    app.run(host="0.0.0.0", port=5000, debug=False, threaded=True)