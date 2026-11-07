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
            cls = n.attrib.get("class", "")
            if desc or bounds:
                nodes.append({"desc": desc, "bounds": bounds, "class": cls})
    except Exception as e:
        print(f"Error parsing XML for {device}: {e}")
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
        print(f"Tapping {device} at ({cx}, {cy})")
        run_adb(device, ["shell", "input", "tap", str(cx), str(cy)])
        return True
    return False

print("==================================================")
print("TEST 1: CALL FROM RECENTS (5554 -> 5556)")
print("==================================================")

# 1. On 5554, find recent call tile with 'idrees'
nodes_5554 = dump_nodes("emulator-5554", "/sdcard/h5554.xml")
bounds_idrees = find_bounds(nodes_5554, "idrees")
print(f"Found idrees recent tile on 5554 at: {bounds_idrees}")

if not bounds_idrees:
    print("No recent tile for idrees found! Checking all descs on 5554:")
    for n in nodes_5554:
        if n["desc"]:
            print(f"  desc='{n['desc']}' bounds={n['bounds']}")
    # Fallback tap around where recent tiles appear
    bounds_idrees = "[16,420][704,560]"

print("Tapping on idrees recent call tile on 5554...")
tap_bounds("emulator-5554", bounds_idrees)

print("Waiting 4 seconds for MQTT direct signaling & incoming notification...")
time.sleep(4)

# 2. On 5556, check for incoming call notification / overlay
nodes_5556 = dump_nodes("emulator-5556", "/sdcard/in5556.xml")
print("Nodes on 5556 after call placed:")
for n in nodes_5556:
    if any(k in n["desc"].lower() for k in ["incoming", "hostuser", "accept", "decline", "call", "answer"]):
        print(f"  [5556] desc='{n['desc']}' bounds={n['bounds']}")

# Let's check system notification on 5556
notif_output = run_adb("emulator-5556", ["shell", "dumpsys", "notification", "--noredact"])
if "simplysay_incoming_calls" in notif_output:
    print("SUCCESS: System incoming call notification is ACTIVE on emulator-5556!")
else:
    print("Warning: simplysay_incoming_calls notification not found in dumpsys.")

# Let's accept on 5556: either by tapping Accept in UI or launching the acceptPendingIntent
bounds_accept = find_bounds(nodes_5556, "Accept")
if not bounds_accept:
    bounds_accept = find_bounds(nodes_5556, "Answer")

if bounds_accept:
    print(f"Accept button found on 5556 at {bounds_accept}, tapping...")
    tap_bounds("emulator-5556", bounds_accept)
else:
    print("Triggering notification accept via intent on 5556...")
    # Send accept intent directly to 5556
    run_adb("emulator-5556", ["shell", "am", "broadcast", "-a", "com.comlabs.simplysay.ACTION_ACCEPT"])

print("Waiting 3 seconds for call to establish...")
time.sleep(3)

# 3. Verify in-call status on both devices
nodes_call_5554 = dump_nodes("emulator-5554", "/sdcard/call5554.xml")
nodes_call_5556 = dump_nodes("emulator-5556", "/sdcard/call5556.xml")

timer_5554 = [n["desc"] for n in nodes_call_5554 if re.match(r'^\d\d:\d\d$', n["desc"])]
timer_5556 = [n["desc"] for n in nodes_call_5556 if re.match(r'^\d\d:\d\d$', n["desc"])]

print(f"Device 5554 in-call timer: {timer_5554}")
print(f"Device 5556 in-call timer: {timer_5556}")

# Capture screenshots
run_adb("emulator-5554", ["shell", "screencap", "-p", "/sdcard/recent_call_5554.png"])
run_adb("emulator-5554", ["pull", "/sdcard/recent_call_5554.png", "C:\\Users\\cpmoh\\.gemini\\antigravity\\brain\\ba06df15-a443-47ba-9a2e-7e0b1c4b25fb\\recent_call_5554.png"])
run_adb("emulator-5556", ["shell", "screencap", "-p", "/sdcard/recent_call_5556.png"])
run_adb("emulator-5556", ["pull", "/sdcard/recent_call_5556.png", "C:\\Users\\cpmoh\\.gemini\\antigravity\\brain\\ba06df15-a443-47ba-9a2e-7e0b1c4b25fb\\recent_call_5556.png"])

# End call on 5554
bounds_end = find_bounds(nodes_call_5554, "End Call")
if bounds_end:
    tap_bounds("emulator-5554", bounds_end)
else:
    run_adb("emulator-5554", ["shell", "input", "tap", "298", "1086"])
time.sleep(2)

print("Recent call test complete!")

