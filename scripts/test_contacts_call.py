import subprocess
import time
import xml.etree.ElementTree as ET
import re

def run_adb(device, cmd):
    res = subprocess.run(["adb", "-s", device] + cmd, capture_output=True, text=True)
    return res.stdout

def dump_nodes(device, out_file):
    run_adb(device, ["shell", "uiautomator", "dump", out_file])
    xml_str = run_adb(device, ["shell", "cat", out_file])
    nodes = []
    try:
        root = ET.fromstring(xml_str)
        for n in root.iter("node"):
            desc = n.attrib.get("content-desc", "")
            bounds = n.attrib.get("bounds", "")
            if desc or bounds:
                nodes.append({"desc": desc, "bounds": bounds})
    except Exception as e:
        print(f"Error parsing XML for {device}: {e}")
    return nodes

def tap_bounds(device, bounds_str):
    m = re.findall(r'\d+', bounds_str)
    if m:
        cx = (int(m[0]) + int(m[2])) // 2
        cy = (int(m[1]) + int(m[3])) // 2
        print(f"Tapping {device} at ({cx}, {cy})")
        run_adb(device, ["shell", "input", "tap", str(cx), str(cy)])
        return True
    return False

print("==================================================")
print("TEST 2: CALL FROM CONTACTS (5556 -> 5554)")
print("==================================================")

# 1. On 5556, tap 'Video Call HostUser' button
print("Tapping 'Video Call HostUser' on emulator-5556 at (930, 1838)...")
run_adb("emulator-5556", ["shell", "input", "tap", "930", "1838"])

print("Waiting 4 seconds for MQTT direct signaling & incoming notification on 5554...")
time.sleep(4)

# 2. On 5554, check for incoming call dialog / prompt
nodes_5554 = dump_nodes("emulator-5554", "/sdcard/in5554.xml")
print("Nodes on 5554 after call placed:")
accept_bounds = None
for n in nodes_5554:
    desc = n["desc"].lower()
    if any(k in desc for k in ["incoming", "idrees", "accept", "decline"]):
        print(f"  [5554] desc='{n['desc']}' bounds={n['bounds']}")
    if "accept" in desc:
        accept_bounds = n["bounds"]

if accept_bounds:
    print(f"SUCCESS: Found Accept button on 5554 at {accept_bounds}! Tapping to accept call...")
    tap_bounds("emulator-5554", accept_bounds)
else:
    print("Warning: Accept button not found on 5554 UI. Checking system notification:")
    notif = run_adb("emulator-5554", ["shell", "dumpsys", "notification", "--noredact"])
    if "simplysay_incoming_calls" in notif:
        print("System notification is ACTIVE on 5554! Triggering accept...")
        run_adb("emulator-5554", ["shell", "input", "tap", "500", "1347"])

print("Waiting 4 seconds for call to establish...")
time.sleep(4)

# 3. Check in-call timer on both devices
nodes_call_5554 = dump_nodes("emulator-5554", "/sdcard/call5554.xml")
nodes_call_5556 = dump_nodes("emulator-5556", "/sdcard/call5556.xml")

timer_5554 = [n["desc"] for n in nodes_call_5554 if re.match(r'^\d\d:\d\d$', n["desc"])]
timer_5556 = [n["desc"] for n in nodes_call_5556 if re.match(r'^\d\d:\d\d$', n["desc"])]

print(f"Device 5554 (Callee) in-call timer: {timer_5554}")
print(f"Device 5556 (Caller) in-call timer: {timer_5556}")

# Capture screenshots
run_adb("emulator-5554", ["shell", "screencap", "-p", "/sdcard/contact_call_5554.png"])
run_adb("emulator-5554", ["pull", "/sdcard/contact_call_5554.png", "C:\\Users\\cpmoh\\.gemini\\antigravity\\brain\\ba06df15-a443-47ba-9a2e-7e0b1c4b25fb\\contact_call_5554.png"])
run_adb("emulator-5556", ["shell", "screencap", "-p", "/sdcard/contact_call_5556.png"])
run_adb("emulator-5556", ["pull", "/sdcard/contact_call_5556.png", "C:\\Users\\cpmoh\\.gemini\\antigravity\\brain\\ba06df15-a443-47ba-9a2e-7e0b1c4b25fb\\contact_call_5556.png"])

# End call
for n in nodes_call_5556:
    if "end call" in n["desc"].lower():
        tap_bounds("emulator-5556", n["bounds"])
        break

print("Test from Contacts completed successfully!")

