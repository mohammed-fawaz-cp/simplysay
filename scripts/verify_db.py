import sqlite3
import subprocess

for dev, fname in [('emulator-5554', 'db_a_check.db'), ('emulator-5556', 'db_b_check.db')]:
    with open(fname, 'wb') as f:
        subprocess.run(['adb', '-s', dev, 'exec-out', 'run-as', 'com.comlabs.simplysay', 'cat', 'databases/simplysay_local.db'], stdout=f)

    try:
        conn = sqlite3.connect(fname)
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
        tables = [t[0] for t in cursor.fetchall()]
        print(f'{dev} tables: {tables}')
        cursor.execute("PRAGMA table_info(call_history);")
        print(f'{dev} call_history columns: {[c[1] for c in cursor.fetchall()]}')
        conn.close()
    except Exception as e:
        print(f'Error reading {dev} db:', e)
