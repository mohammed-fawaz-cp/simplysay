import subprocess
import time
import re
import sys

def run_adb(device, cmd):
    full_cmd = ["C:\\Users\\cpmoh\\.android\\sdk\\platform-tools\\adb.exe", "-s", device] + cmd
    res = subprocess.run(full_cmd, capture_output=True, text=True, errors='ignore')
    return res.stdout

def get_host_code(caller_device):
    print(f"[Bridge] Extracting Instant Call code from Host ({caller_device})...", flush=True)
    for _ in range(15):
        xml = run_adb(caller_device, ["shell", "uiautomator dump /sdcard/dump.xml && cat /sdcard/dump.xml"])
        letters = re.findall(r'content-desc="([A-Z0-9])"', xml)
        if len(letters) >= 9:
            code = "".join(letters[:9])
            print(f"✅ [Bridge] Captured 9-character code: {code}", flush=True)
            return code
        time.sleep(1)
    return None

def join_call_on_callee(callee_device, code):
    print(f"[Bridge] Joining call on Callee ({callee_device}) with code {code}...", flush=True)
    xml = run_adb(callee_device, ["shell", "uiautomator dump /sdcard/dump.xml && cat /sdcard/dump.xml"])
    
    # Extract all 9 EditText boxes bounds
    boxes = re.findall(r'class="android\.widget\.EditText"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', xml)
    print(f"[Bridge] Found {len(boxes)} input boxes.", flush=True)

    if len(boxes) >= 9:
        for i in range(9):
            x1, y1, x2, y2 = map(int, boxes[i])
            cx, cy = (x1 + x2) // 2, (y1 + y2) // 2
            ch = code[i]
            # Tap box
            run_adb(callee_device, ["shell", f"input tap {cx} {cy}"])
            time.sleep(0.15)
            # Clear existing if any
            run_adb(callee_device, ["shell", "input keyevent 67"])
            # Type char
            run_adb(callee_device, ["shell", f"input text {ch}"])
            time.sleep(0.15)
    else:
        # Fallback coordinate map for 1080p
        coords = [
            (157, 968), (246, 968), (335, 968),
            (451, 968), (540, 968), (629, 968),
            (745, 968), (834, 968), (923, 968)
        ]
        for i, (cx, cy) in enumerate(coords):
            ch = code[i]
            run_adb(callee_device, ["shell", f"input tap {cx} {cy}"])
            time.sleep(0.15)
            run_adb(callee_device, ["shell", f"input text {ch}"])
            time.sleep(0.15)

    time.sleep(0.5)

    # Tap 'Join Call' button
    xml_after = run_adb(callee_device, ["shell", "uiautomator dump /sdcard/dump.xml && cat /sdcard/dump.xml"])
    join_match = re.search(r'content-desc="Join Call"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', xml_after)
    if join_match:
        x1, y1, x2, y2 = map(int, join_match.groups())
        join_x = (x1 + x2) // 2
        join_y = (y1 + y2) // 2
        print(f"[Bridge] Tapping 'Join Call' at ({join_x}, {join_y})...", flush=True)
        run_adb(callee_device, ["shell", f"input tap {join_x} {join_y}"])
    else:
        print("[Bridge] Fallback tapping Join Call at (540, 1300)...", flush=True)
        run_adb(callee_device, ["shell", "input tap 540 1300"])

def verify_call_connected(caller_device, callee_device):
    print("[Bridge] Verifying bidirectional WebRTC call connection...", flush=True)
    caller_connected = False
    callee_connected = False

    for i in range(25):
        time.sleep(1)
        xml_caller = run_adb(caller_device, ["shell", "uiautomator dump /sdcard/dump.xml && cat /sdcard/dump.xml"])
        xml_callee = run_adb(callee_device, ["shell", "uiautomator dump /sdcard/dump.xml && cat /sdcard/dump.xml"])

        caller_connected = "End Call" in xml_caller or bool(re.search(r'content-desc="\d\d:\d\d"', xml_caller))
        callee_connected = "End Call" in xml_callee or bool(re.search(r'content-desc="\d\d:\d\d"', xml_callee))

        if caller_connected and callee_connected:
            print(f"🎉 [Bridge] SUCCESS: Bidirectional Call Connected! (Verified at t={i+1}s)", flush=True)
            return True
        elif caller_connected or callee_connected:
            print(f"[Bridge] (t={i+1}s) Establishing media: caller={caller_connected}, callee={callee_connected}", flush=True)

    print(f"❌ [Bridge] Timeout waiting for call connection: caller_connected={caller_connected}, callee_connected={callee_connected}", flush=True)
    return False

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python bridge_instant_call.py <caller_device> <callee_device>")
        sys.exit(1)

    caller = sys.argv[1]
    callee = sys.argv[2]

    code = get_host_code(caller)
    if not code:
        print("❌ Could not extract host code.")
        sys.exit(1)

    join_call_on_callee(callee, code)
    success = verify_call_connected(caller, callee)
    if not success:
        sys.exit(1)
    sys.exit(0)
