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
print("TEST: INITIATE CALL FROM RECENT CALLS (5554 -> 5556)", flush=True)
print("==================================================", flush=True)

# 1. On 5554, tap the 'idrees' recent call tile
nodes_5554 = dump_nodes("emulator-5554")
idrees_bounds = find_bounds(nodes_5554, "idrees")
print(f"Found 'idrees' recent tile on 5554: {idrees_bounds}", flush=True)

if not idrees_bounds:
    idrees_bounds = "[16,308][704,452]"

print("5554 tapping 'idrees' recent call tile...", flush=True)
tap_bounds("emulator-5554", idrees_bounds)

print("Waiting 3 seconds for signaling & incoming alert on 5556...", flush=True)
time.sleep(3)

# 2. Check 5556 for incoming call prompt
nodes_5556 = dump_nodes("emulator-5556")
incoming_prompt = False
accept_bounds = None
for n in nodes_5556:
    desc = n["desc"].lower()
    if any(k in desc for k in ["incoming", "hostuser", "call request"]):
        incoming_prompt = True
    if "accept" in desc or "answer" in desc:
        accept_bounds = n["bounds"]

print(f"🔔 5556 Incoming Call Alert Visible: {incoming_prompt}", flush=True)
print(f"🔔 5556 Accept Button Bounds: {accept_bounds}", flush=True)

if accept_bounds:
    print(f"5556 tapping Accept at {accept_bounds}...", flush=True)
    tap_bounds("emulator-5556", accept_bounds)
else:
    # Check notification dumpsys or tap center if dialog appeared
    notif = run_adb("emulator-5556", ["shell", "dumpsys", "notification", "--noredact"])
    print(f"5556 notification present: {'simplysay_incoming_calls' in notif}", flush=True)
    # Check if dialog exists without explicit desc
    for n in nodes_5556:
        if n["desc"]:
            print(f"  [5556 node] {n['desc']} | {n['bounds']}", flush=True)

print("Waiting 5 seconds for call connection...", flush=True)
time.sleep(5)

# 3. Verify in-call status on both devices
nodes_incall_5554 = dump_nodes("emulator-5554")
nodes_incall_5556 = dump_nodes("emulator-5556")

end_call_5554 = any("end call" in n["desc"].lower() for n in nodes_incall_5554)
end_call_5556 = any("end call" in n["desc"].lower() for n in nodes_incall_5556)

print(f"5554 in-call: {end_call_5554}", flush=True)
print(f"5556 in-call: {end_call_5556}", flush=True)

if end_call_5554 and end_call_5556:
    print("🎉 SUCCESS: Direct Call from Recent Calls connected smoothly!", flush=True)
    # End the call
    tap_bounds("emulator-5554", find_bounds(nodes_incall_5554, "End Call") or "[238,1026][358,1146]")
else:
    print("Call check finished.")

