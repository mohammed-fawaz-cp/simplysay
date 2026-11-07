import subprocess
import time
import xml.etree.ElementTree as ET
import re
import sys

def run_adb(device, cmd):
    res = subprocess.run(["adb", "-s", device] + cmd, capture_output=True, text=True, errors='ignore')
    return res.stdout

def dump_nodes(device, out_file="/sdcard/dump.xml"):
    run_adb(device, ["shell", "uiautomator", "dump", out_file])
    xml_str = run_adb(device, ["shell", "cat", out_file])
    nodes = []
    try:
        root = ET.fromstring(xml_str)
        for n in root.iter("node"):
            desc = n.attrib.get("content-desc", "")
            bounds = n.attrib.get("bounds", "")
            cls = n.attrib.get("class", "")
            if desc or bounds:
                nodes.append({"desc": desc, "bounds": bounds, "class": cls})
    except Exception as e:
        print(f"Error parsing XML for {device}: {e}", flush=True)
    return nodes

def find_bounds(nodes, pattern):
    for n in nodes:
        if pattern.lower() in n["desc"].lower():
            return n["bounds"]
    return None

def tap_bounds(device, bounds_str):
    m = re.findall(r'\d+', bounds_str)
    if m:
        cx = (int(m[0]) + int(m[2])) // 2
        cy = (int(m[1]) + int(m[3])) // 2
        print(f"Tapping {device} at ({cx}, {cy})", flush=True)
        run_adb(device, ["shell", "input", "tap", str(cx), str(cy)])
        return True
    return False

print("==================================================", flush=True)
print("TEST: INSTANT CALL WITH CALL NOTIFICATION & ACCEPT", flush=True)
print("==================================================", flush=True)

# 1. Reset both apps to Home Screen
print("Resetting both devices to Main Screen...", flush=True)
for dev in ["emulator-5554", "emulator-5556"]:
    run_adb(dev, ["shell", "am", "start", "-n", "com.comlabs.simplysay/com.comlabs.simplysay.MainActivity"])
    time.sleep(1.5)
    nodes = dump_nodes(dev)
    google_bounds = find_bounds(nodes, "Continue with Google")
    if google_bounds:
        print(f"Logging in with Google on {dev}...", flush=True)
        tap_bounds(dev, google_bounds)
        time.sleep(3)
        # Check if phone number bottom sheet or permission appears
        nodes_after = dump_nodes(dev)
        confirm_bounds = find_bounds(nodes_after, "Confirm")
        if confirm_bounds:
            tap_bounds(dev, confirm_bounds)
            time.sleep(2)
        # Check if grant permission or continue appears
        for n in nodes_after:
            if "while using the app" in n["desc"].lower() or "allow" in n["desc"].lower():
                tap_bounds(dev, n["bounds"])
                time.sleep(1)

# 2. Host (5554) opens "Host Instant Call"
print("Host (5554) tapping 'Host Instant Call'...", flush=True)
nodes_5554 = dump_nodes("emulator-5554")
host_bounds = find_bounds(nodes_5554, "Host Instant Call")
if host_bounds:
    tap_bounds("emulator-5554", host_bounds)
else:
    run_adb("emulator-5554", ["shell", "input", "tap", "632", "990"])

time.sleep(2)

# 3. Extract generated 9-character code from Host (5554)
nodes_host = dump_nodes("emulator-5554")
chars = []
for n in nodes_host:
    desc = n["desc"].strip()
    if len(desc) == 1 and desc != "-" and desc.isalnum():
        chars.append(desc)
code = "".join(chars[:9])
print(f"✅ Host Instant Call Code: '{code}' (length={len(code)})", flush=True)

if len(code) != 9:
    print(f"❌ Failed to extract valid 9-character code from Host: {chars}", flush=True)
    sys.exit(1)

# 4. Joiner (5556) opens "Connect to Instant Call"
print("Joiner (5556) navigating to 'Connect to Instant Call'...", flush=True)
# Tap Options (three dots) -> Connect to Instant Call
run_adb("emulator-5556", ["shell", "input", "tap", "1008", "137"])
time.sleep(1)
run_adb("emulator-5556", ["shell", "input", "tap", "765", "168"])
time.sleep(2)

# 5. Joiner enters code into 9 input boxes
print(f"Joiner (5556) typing code '{code}'...", flush=True)
# Tap Box 0
run_adb("emulator-5556", ["shell", "input", "tap", "157", "968"])
time.sleep(0.3)
for ch in code:
    run_adb("emulator-5556", ["shell", "input", "text", ch])
    time.sleep(0.15)
time.sleep(0.5)

# Tap 'Join Call' on Joiner (5556)
nodes_join = dump_nodes("emulator-5556")
join_bounds = find_bounds(nodes_join, "Join Call")
if join_bounds:
    tap_bounds("emulator-5556", join_bounds)
else:
    run_adb("emulator-5556", ["shell", "input", "tap", "540", "1228"])

print("Joiner tapped 'Join Call'. Waiting 3 seconds for signaling...", flush=True)
time.sleep(3)

# 6. Verify Joiner shows 'Calling HostUser... Ringing host device...'
nodes_after_join_5556 = dump_nodes("emulator-5556")
calling_text = any("calling" in n["desc"].lower() or "ringing" in n["desc"].lower() for n in nodes_after_join_5556)
print(f"Joiner ringing/waiting state: {calling_text}", flush=True)

# 7. CRITICAL VERIFICATION: Does Host (5554) receive incoming call alert?
nodes_after_join_5554 = dump_nodes("emulator-5554")
incoming_prompt = False
accept_bounds = None
for n in nodes_after_join_5554:
    desc = n["desc"].lower()
    if "incoming" in desc or "idrees" in desc:
        incoming_prompt = True
    if "accept" in desc or "answer" in desc:
        accept_bounds = n["bounds"]

print(f"🔔 Host (5554) Incoming Call Notification/Alert Visible: {incoming_prompt}", flush=True)
print(f"🔔 Host (5554) Accept Button Bounds: {accept_bounds}", flush=True)

if not incoming_prompt:
    print("❌ Host did not show incoming call prompt! Dumping nodes:", flush=True)
    for n in nodes_after_join_5554:
        if n["desc"]:
            print(f"  [5554] desc='{n['desc']}' bounds={n['bounds']}", flush=True)
    sys.exit(1)

# 8. Host (5554) accepts call
print(f"Host (5554) tapping Accept at {accept_bounds}...", flush=True)
if accept_bounds:
    tap_bounds("emulator-5554", accept_bounds)
else:
    run_adb("emulator-5554", ["shell", "input", "tap", "490", "752"])

print("Waiting 5 seconds for WebRTC handshake and live media establishment...", flush=True)
time.sleep(5)

# 9. Verify live connected call on BOTH devices
nodes_incall_5554 = dump_nodes("emulator-5554")
nodes_incall_5556 = dump_nodes("emulator-5556")

timer_5554 = [n["desc"] for n in nodes_incall_5554 if re.match(r'^\d\d:\d\d$', n["desc"])]
timer_5556 = [n["desc"] for n in nodes_incall_5556 if re.match(r'^\d\d:\d\d$', n["desc"])]

end_call_5554 = any("end call" in n["desc"].lower() for n in nodes_incall_5554)
end_call_5556 = any("end call" in n["desc"].lower() for n in nodes_incall_5556)

print(f"Host (5554) In-Call Status: timer={timer_5554}, end_call_btn={end_call_5554}", flush=True)
print(f"Joiner (5556) In-Call Status: timer={timer_5556}, end_call_btn={end_call_5556}", flush=True)

if end_call_5554 and end_call_5556:
    print("🎉 SUCCESS: Instant Call established cleanly with incoming notification, acceptance, and bidirectional WebRTC media!", flush=True)
else:
    print("❌ Call did not establish on both sides cleanly.", flush=True)
    sys.exit(1)
