import subprocess
import time
import xml.etree.ElementTree as ET

def run_adb(device, cmd):
    res = subprocess.run(["adb", "-s", device] + cmd, capture_output=True, text=True)
    return res.stdout

print("=== 1. Host (5554) opens Host Instant Call ===")
# Tap "Host Instant Call" on 5554
# Let's find coordinates of "Host Instant Call"
run_adb("emulator-5554", ["shell", "uiautomator", "dump", "/sdcard/home5554.xml"])
xml_str = run_adb("emulator-5554", ["shell", "cat", "/sdcard/home5554.xml"])
root = ET.fromstring(xml_str)
host_btn_bounds = None
for node in root.iter("node"):
    if "Host Instant Call" in node.attrib.get("content-desc", ""):
        host_btn_bounds = node.attrib.get("bounds")
        break

print(f"Host Instant Call button bounds: {host_btn_bounds}")
if host_btn_bounds:
    # bounds is [x1,y1][x2,y2]
    import re
    m = re.findall(r'\d+', host_btn_bounds)
    if m:
        cx = (int(m[0]) + int(m[2])) // 2
        cy = (int(m[1]) + int(m[3])) // 2
        run_adb("emulator-5554", ["shell", "input", "tap", str(cx), str(cy)])
else:
    # fallback tap
    run_adb("emulator-5554", ["shell", "input", "tap", "632", "990"])

time.sleep(2)

print("=== 2. Extract code from Host (5554) ===")
run_adb("emulator-5554", ["shell", "uiautomator", "dump", "/sdcard/host_screen.xml"])
xml_host = run_adb("emulator-5554", ["shell", "cat", "/sdcard/host_screen.xml"])
root_host = ET.fromstring(xml_host)
chars = []
for node in root_host.iter("node"):
    desc = node.attrib.get("content-desc", "")
    if len(desc) == 1 and desc != "-":
        chars.append(desc)
code = "".join(chars)
print(f"Generated Host Code: '{code}' (length: {len(code)})")

print("=== 3. Joiner (5556) opens Connect to Instant Call ===")
# On 5556, tap Options (three dots top right) -> Connect to Instant Call
run_adb("emulator-5556", ["shell", "uiautomator", "dump", "/sdcard/home5556.xml"])
xml_5556 = run_adb("emulator-5556", ["shell", "cat", "/sdcard/home5556.xml"])
root_5556 = ET.fromstring(xml_5556)
opt_bounds = None
for node in root_5556.iter("node"):
    desc = node.attrib.get("content-desc", "")
    if "Options" in desc or node.attrib.get("class") == "android.widget.Button":
        opt_bounds = node.attrib.get("bounds")
        # usually top right
print(f"Options button bounds: {opt_bounds}")
run_adb("emulator-5556", ["shell", "input", "tap", "1008", "137"])
time.sleep(1)
run_adb("emulator-5556", ["shell", "input", "tap", "765", "168"])
time.sleep(1.5)

print("=== 4. Joiner (5556) enters code and joins ===")
# Tap Box 0
run_adb("emulator-5556", ["shell", "input", "tap", "157", "968"])
time.sleep(0.3)
for ch in code:
    run_adb("emulator-5556", ["shell", "input", "text", ch])
    time.sleep(0.2)
time.sleep(0.5)

# Tap Join Call
run_adb("emulator-5556", ["shell", "uiautomator", "dump", "/sdcard/join_screen.xml"])
xml_join = run_adb("emulator-5556", ["shell", "cat", "/sdcard/join_screen.xml"])
root_join = ET.fromstring(xml_join)
join_btn_bounds = None
for node in root_join.iter("node"):
    if "Join Call" in node.attrib.get("content-desc", ""):
        join_btn_bounds = node.attrib.get("bounds")
        break
print(f"Join Call button bounds: {join_btn_bounds}")
if join_btn_bounds:
    import re
    m = re.findall(r'\d+', join_btn_bounds)
    cx = (int(m[0]) + int(m[2])) // 2
    cy = (int(m[1]) + int(m[3])) // 2
    run_adb("emulator-5556", ["shell", "input", "tap", str(cx), str(cy)])
else:
    run_adb("emulator-5556", ["shell", "input", "tap", "540", "1228"])

print("Waiting 3 seconds for signaling...")
time.sleep(3)

print("=== 5. Inspect UI State of Both Devices ===")
run_adb("emulator-5554", ["shell", "uiautomator", "dump", "/sdcard/dump_after_join_5554.xml"])
run_adb("emulator-5556", ["shell", "uiautomator", "dump", "/sdcard/dump_after_join_5556.xml"])

xml_res_5554 = run_adb("emulator-5554", ["shell", "cat", "/sdcard/dump_after_join_5554.xml"])
xml_res_5556 = run_adb("emulator-5556", ["shell", "cat", "/sdcard/dump_after_join_5556.xml"])

print("--- Device 5554 (Host) Nodes ---")
root_res_5554 = ET.fromstring(xml_res_5554)
for node in root_res_5554.iter("node"):
    desc = node.attrib.get("content-desc", "")
    if desc:
        print(f"  [5554] desc='{desc}' bounds={node.attrib.get('bounds')}")

print("--- Device 5556 (Joiner) Nodes ---")
root_res_5556 = ET.fromstring(xml_res_5556)
for node in root_res_5556.iter("node"):
    desc = node.attrib.get("content-desc", "")
    if desc:
        print(f"  [5556] desc='{desc}' bounds={node.attrib.get('bounds')}")

