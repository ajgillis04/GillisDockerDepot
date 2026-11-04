#!/usr/bin/env python3
"""Nightly OpenWebUI backup: a consistent copy of the database, plus any new uploads.

Run once right now with: docker exec llm-backup.$HOST_NAME python3 /backup.py --now
"""
import datetime
import glob
import os
import shutil
import sqlite3
import sys
import time

DATA = "/data"
OUT = "/backup"
HOUR = int(os.environ.get("BACKUP_HOUR", "4"))
KEEP = int(os.environ.get("KEEP_COPIES", "14"))


def run_backup():
    stamp = datetime.datetime.now().strftime("%Y-%m-%d_%H%M")
    final = f"{OUT}/webui-{stamp}.db"
    partial = final + ".partial"

    # The sqlite backup API is safe while OpenWebUI is writing; a file copy isn't.
    source = sqlite3.connect(f"file:{DATA}/webui.db?mode=ro", uri=True, timeout=60)
    target = sqlite3.connect(partial)
    with target:
        source.backup(target)
    result = target.execute("PRAGMA integrity_check").fetchone()[0]
    chats = target.execute("SELECT count(*) FROM chat").fetchone()[0]
    target.close()
    source.close()
    if result != "ok":
        os.remove(partial)
        raise RuntimeError(f"backup failed the integrity check: {result}")
    os.replace(partial, final)

    # Uploads never change once written, so only new files need copying.
    copied = 0
    for folder, _, files in os.walk(f"{DATA}/uploads"):
        dest_folder = os.path.join(f"{OUT}/uploads", os.path.relpath(folder, f"{DATA}/uploads"))
        os.makedirs(dest_folder, exist_ok=True)
        for name in files:
            dest = os.path.join(dest_folder, name)
            if not os.path.exists(dest):
                shutil.copy2(os.path.join(folder, name), dest)
                copied += 1

    for old in sorted(glob.glob(f"{OUT}/webui-*.db"))[:-KEEP]:
        os.remove(old)

    print(f"{stamp} ok: {os.path.getsize(final) // 1048576} MB, {chats} chats, {copied} new uploads", flush=True)


if "--now" in sys.argv:
    run_backup()
    sys.exit(0)

print(f"waiting for {HOUR}:00 each day", flush=True)
while True:
    now = datetime.datetime.now()
    next_run = now.replace(hour=HOUR, minute=0, second=0, microsecond=0)
    if next_run <= now:
        next_run += datetime.timedelta(days=1)
    time.sleep((next_run - now).total_seconds())
    try:
        run_backup()
    except Exception as error:  # Try again tomorrow rather than crash-looping.
        print(f"BACKUP FAILED: {error}", flush=True)
    time.sleep(61)
