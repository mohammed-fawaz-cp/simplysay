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
print("TEST: INITIATE CALL FROM CONTACT LIST (5556 -> 5554)", flush=True)
print("==================================================", flush=True)

# 1. On 5556, tap 'Video Call HostUser' button
nodes_5556 = dump_nodes("emulator-5556")
call_btn_bounds = find_bounds(nodes_5556, "Video Call HostUser")
if not call_btn_bounds:
    call_btn_bounds = "[867,1775][993,1901]"

print(f"5556 tapping 'Video Call HostUser' button at {call_btn_bounds}...", flush=True)
tap_bounds("emulator-5556", call_btn_bounds)

print("Waiting 3 seconds for signaling & incoming alert on 5554...", flush=True)
time.sleep(3)

# 2. Check 5554 for incoming call prompt
nodes_5554 = dump_nodes("emulator-5554")
incoming_prompt = False
accept_bounds = None
for n in nodes_5554:
    desc = n["desc"].lower()
    if any(k in desc for k in ["incoming", "idrees", "call request"]):
        incoming_prompt = True
    if "accept" in desc or "answer" in desc:
        accept_bounds = n["bounds"]

print(f"🔔 5554 Incoming Call Alert Visible: {incoming_prompt}", flush=True)
print(f"🔔 5554 Accept Button Bounds: {accept_bounds}", flush=True)

if not accept_bounds:
    # Print 5554 nodes
    for n in nodes_5554:
        if n["desc"]:
            print(f"  [5554 node] {n['desc']} | {n['bounds']}", flush=True)

if accept_bounds:
    print(f"5554 tapping Accept at {accept_bounds}...", flush=True)
    tap_bounds("emulator-5554", accept_bounds)
else:
    # Tap default accept bounds on 5554 dialog if present
    print("Attempting tap at dialog accept bounds (490, 772)...", flush=True)
    run_adb("emulator-5554", ["shell", "input", "tap", "490", "772"])

print("Waiting 5 seconds for call connection...", flush=True)
time.sleep(5)

# 3. Verify in-call status on both devices
nodes_incall_5554 = dump_nodes("emulator-5554")
nodes_incall_5556 = dump_nodes("emulator-5556")

end_call_5554 = any("end call" in n["desc"].lower() for n in nodes_incall_5554)
end_call_5556 = any("end call" in n["desc"].lower() for n in nodes_incall_5556)

print(f"5554 in-call: {end_call_5554}", flush=True)
print(f"5556 in-call: {end_call_5556}", flush=True)

# Capture screenshots
subprocess.run(["adb", "-s", "emulator-5554", "exec-out", "screencap", "-p"], stdout=open(r"C:\Users\cpmoh\.gemini\antigravity\brain\ba06df15-a443-47ba-9a2e-7e0b1c4b25fb\contact_call_success_5554.png", "wb"))
subprocess.run(["adb", "-s", "emulator-5556", "exec-out", "screencap", "-p"], stdout=open(r"C:\Users\cpmoh\.gemini\antigravity\brain\ba06df15-a443-47ba-9a2e-7e0b1c4b25fb\contact_call_success_5556.png", "wb"))

if end_call_5554 and end_call_5556:
    print("🎉 SUCCESS: Direct Call from Contacts connected smoothly!", flush=True)
    # End the call from 5556
    tap_bounds("emulator-5556", find_bounds(nodes_incall_5556, "End Call") or "[380,2067][537,2224]")
else:
    print("Call check finished.")

