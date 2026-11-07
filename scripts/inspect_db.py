import sqlite3
import subprocess

with open("db5554.db", "wb") as f:
    subprocess.run(["adb", "-s", "emulator-5554", "exec-out", "run-as", "com.comlabs.simplysay", "cat", "databases/simplysay_local.db"], stdout=f)

with open("db5556.db", "wb") as f:
    subprocess.run(["adb", "-s", "emulator-5556", "exec-out", "run-as", "com.comlabs.simplysay", "cat", "databases/simplysay_local.db"], stdout=f)

for name, db in [("5554", "db5554.db"), ("5556", "db5556.db")]:
    print(f"=== DB {name} ===")
    conn = sqlite3.connect(db)
    print("Tables:", conn.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall())
    print("Identity:", conn.execute("SELECT * FROM client_identity").fetchall())
    print("Peers:", conn.execute("SELECT * FROM peers").fetchall())
    print("Call Sessions:", conn.execute("SELECT * FROM call_sessions").fetchall())
    print("Contacts:", conn.execute("SELECT * FROM contacts").fetchall())
