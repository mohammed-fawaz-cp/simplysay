import subprocess
import time
import json
import sys
import os

MAESTRO_BAT = os.path.expanduser(r"~\.maestro\maestro\bin\maestro.bat")
DEV_CALLER = "emulator-5554"
DEV_CALLEE = "emulator-5556"

def run_cmd(cmd, check=False):
    res = subprocess.run(cmd, capture_output=True, text=True, errors='ignore')
    return res.stdout.strip(), res.stderr.strip(), res.returncode

def run_adb(device, adb_args):
    stdout, stderr, code = run_cmd(["adb", "-s", device] + adb_args)
    return stdout

print("=" * 60)
print("TEST: APP CLOSED STATE - FCM NOTIFICATION DELIVERY")
print("Caller (Device A):", DEV_CALLER)
print("Callee (Device B):", DEV_CALLEE)
print("=" * 60)

# Step 1: Query Device B's FCM token from SQLite DB
print("\n[Step 1] Extracting Device B (Callee) FCM Token from local database...")
run_adb(DEV_CALLEE, ["exec-out", "run-as", "com.comlabs.simplysay", "cat", "databases/simplysay_local.db"])
import sqlite3
with open("db5556_temp.db", "wb") as f:
    subprocess.run(["adb", "-s", DEV_CALLEE, "exec-out", "run-as", "com.comlabs.simplysay", "cat", "databases/simplysay_local.db"], stdout=f)

callee_token = None
try:
    conn = sqlite3.connect("db5556_temp.db")
    rows = conn.execute("SELECT value FROM local_settings WHERE key='fcm_token'").fetchall()
    if rows:
        callee_token = rows[0][0]
    conn.close()
except Exception as e:
    print(f"Error reading DB: {e}")

if not callee_token:
    print("Warning: No FCM token in DB! Using known token for 5556...")
    callee_token = "dJfI7x1TTn-rTqrRKYkBD_:APA91bGg7D1Ojsx8RBpx3ZK6cXDWTtOq1wNLfLqhqFGkZrufZwc3-mpA7APxxr_YTHJ7jRqn7A1RiG7ZLujSudJGW7HXZgtg9aMz3RVDZaFMI0pJYZt0U-k"

print(f"Callee FCM Token: {callee_token[:25]}...{callee_token[-15:]}")

# Step 2: Ensure Callee screen is on and unlocked
print("\n[Step 2] Waking Callee screen & unlocking...")
run_adb(DEV_CALLEE, ["shell", "input", "keyevent", "26"]) # power toggle if asleep
run_adb(DEV_CALLEE, ["shell", "svc", "power", "stayon", "true"])
run_adb(DEV_CALLEE, ["shell", "wm", "dismiss-keyguard"])
run_adb(DEV_CALLEE, ["shell", "input", "keyevent", "82"])

# Step 3: Ensure Callee app is closed (terminate process without OS freeze)
print("\n[Step 3] Terminating Callee App process to put it in CLOSED / KILLED state...")
# First launch to ensure it's not in stopped state, then kill process
run_adb(DEV_CALLEE, ["shell", "am", "start", "-n", "com.comlabs.simplysay/.MainActivity"])
time.sleep(2)
pid = run_adb(DEV_CALLEE, ["shell", "pidof", "com.comlabs.simplysay"]).strip()
if pid:
    print(f"Killing running process PID={pid} to enter closed state...")
    run_adb(DEV_CALLEE, ["shell", "run-as", "com.comlabs.simplysay", "kill", "-9", pid])
    time.sleep(1)

check_pid = run_adb(DEV_CALLEE, ["shell", "pidof", "com.comlabs.simplysay"]).strip()
print(f"Callee Process status after termination: {'DEAD (Closed)' if not check_pid else f'Alive ({check_pid})'}")

# Clear logcat
run_adb(DEV_CALLEE, ["logcat", "-c"])

# Step 4: Dispatch High-Priority Data FCM Call Push from Caller (Device A) to Callee (Device B)
print("\n[Step 4] Dispatching High-Priority Data FCM Call Push...")
sys.path.insert(0, 'server')
try:
    from fcm_admin import fcm_service
    call_payload = {
        "type": "incoming_call",
        "caller_cit": "56bbebf9-d4cb-51be-be1d-d992092512e5",
        "caller_name": "HostUser",
        "call_code": f"CLOSED-TEST-{int(time.time())%10000}",
        "call_type": "video",
        "ttl_seconds": "35",
        "timestamp": str(int(time.time() * 1000))
    }
    push_res = fcm_service.send_data_call_push(target_token=callee_token, data=call_payload)
    print("FCM Push Dispatch Result:", push_res)
except Exception as e:
    print("Error sending FCM push:", e)

# Step 5: Run Maestro on Callee Device to inspect notification and UI
print("\n[Step 5] Running Maestro flow on Callee (Device B) to verify notification shade...")
flow_path = os.path.abspath(r".maestro\flows\06_app_closed_fcm_notification.yaml")

# Run maestro test
maestro_cmd = [MAESTRO_BAT, "--device", DEV_CALLEE, "test", flow_path]
print(f"Executing: {' '.join(maestro_cmd)}")
m_stdout, m_stderr, m_code = run_cmd(maestro_cmd)
print("Maestro Return Code:", m_code)
print("Maestro Output:\n", m_stdout)

# Step 6: Verify Android notification system dumpsys
print("\n[Step 6] Verifying Android Notification System Telemetry...")
dumpsys_out = run_adb(DEV_CALLEE, ["shell", "dumpsys", "notification", "--noredact"])
has_call_style = "Notification(channel=simplysay_incoming_calls" in dumpsys_out
has_answer = "[1] \"Answer\"" in dumpsys_out or "android.answerIntent" in dumpsys_out
has_decline = "[0] \"Decline\"" in dumpsys_out or "android.declineIntent" in dumpsys_out
has_fullscreen = "fullscreenIntent" in dumpsys_out

print(f"-> Call Notification Record present: {has_call_style}")
print(f"-> Fullscreen Intent configured: {has_fullscreen}")
print(f"-> Answer action intent present: {has_answer}")
print(f"-> Decline action intent present: {has_decline}")

# Step 7: Inspect Logcat for Background Lifecycle
print("\n[Step 7] Checking Callee Logcat for FCM Background Execution...")
logcat_out = run_adb(DEV_CALLEE, ["logcat", "-d"])
for line in logcat_out.splitlines():
    if any(k in line for k in ["FLTFireMsgService", "FCM Background", "showIncomingCall", "CallNotificationManager", "GCM"]):
        print("  |", line)

print("\n" + "=" * 60)
print("TEST COMPLETED")
print("=" * 60)

