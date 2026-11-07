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
print("TEST: CLEAN SINGLE INCOMING CALL NOTIFICATION", flush=True)
print("==================================================", flush=True)

# 1. 5554 initiates call to idrees from Recents
nodes_5554 = dump_nodes("emulator-5554")
idrees_bounds = find_bounds(nodes_5554, "idrees") or "[16,308][704,452]"
print(f"5554 tapping 'idrees' at {idrees_bounds}...", flush=True)
tap_bounds("emulator-5554", idrees_bounds)

time.sleep(3)

# 2. Check 5556 notification state
# A. Check if Android posted a heads-up system notification
notif_output = run_adb("emulator-5556", ["shell", "dumpsys", "notification", "--noredact"])
has_system_heads_up = "NotificationRecord" in notif_output and "simplysay_incoming_calls" in notif_output
print(f"Android System Heads-Up Notification Posted: {has_system_heads_up}", flush=True)

# B. Check 5556 UI nodes for in-app dialog
nodes_5556 = dump_nodes("emulator-5556")
in_app_dialog = any("incoming" in n["desc"].lower() for n in nodes_5556)
accept_bounds = find_bounds(nodes_5556, "Accept")

print(f"In-App Call Prompt Visible: {in_app_dialog}", flush=True)
print(f"Accept Button Bounds: {accept_bounds}", flush=True)

# Capture screenshot showing clean single prompt
subprocess.run(["adb", "-s", "emulator-5556", "exec-out", "screencap", "-p"], stdout=open(r"C:\Users\cpmoh\.gemini\antigravity\brain\ba06df15-a443-47ba-9a2e-7e0b1c4b25fb\clean_single_prompt_5556.png", "wb"))

if not has_system_heads_up and in_app_dialog:
    print("✅ VERIFIED: Exactly ONE clean incoming call prompt (no double system banner)!", flush=True)
elif has_system_heads_up and in_app_dialog:
    print("⚠️ WARNING: Both system notification and in-app dialog appeared.", flush=True)

# 3. 5556 Accepts call
if accept_bounds:
    print(f"5556 accepting call at {accept_bounds}...", flush=True)
    tap_bounds("emulator-5556", accept_bounds)

time.sleep(4)

# 4. Verify in-call status on both devices
nodes_call_5554 = dump_nodes("emulator-5554")
nodes_call_5556 = dump_nodes("emulator-5556")

in_call_5554 = any("end call" in n["desc"].lower() for n in nodes_call_5554)
in_call_5556 = any("end call" in n["desc"].lower() for n in nodes_call_5556)

print(f"5554 in-call: {in_call_5554}", flush=True)
print(f"5556 in-call: {in_call_5556}", flush=True)

# 5. Cleanly end call
end_bounds_5556 = find_bounds(nodes_call_5556, "End Call") or "[380,2067][537,2224]"
print(f"5556 ending call at {end_bounds_5556}...", flush=True)
tap_bounds("emulator-5556", end_bounds_5556)

print("Test complete!")

