import subprocess
import time
import sys
import xml.etree.ElementTree as ET

def run_adb(device, cmd):
    full_cmd = ["adb", "-s", device] + cmd
    res = subprocess.run(full_cmd, capture_output=True, text=True)
    return res.stdout

print("1. Opening Host Instant Call on emulator-5554...")
run_adb("emulator-5554", ["shell", "input", "tap", "632", "990"])
time.sleep(2)

print("2. Extracting code from emulator-5554...")
run_adb("emulator-5554", ["shell", "uiautomator", "dump", "/sdcard/d5554.xml"])
xml_str = run_adb("emulator-5554", ["shell", "cat", "/sdcard/d5554.xml"])
root = ET.fromstring(xml_str)
chars = []
for node in root.iter("node"):
    desc = node.attrib.get("content-desc", "")
    if len(desc) == 1 and desc != "-":
        chars.append(desc)
code = "".join(chars)
print(f"Generated Code: {code}")

if len(code) != 9:
    print(f"Failed to get 9-char code, got '{code}'")
    sys.exit(1)

print("3. Opening Connect to Instant Call on emulator-5556...")
run_adb("emulator-5556", ["shell", "input", "tap", "1008", "137"])
time.sleep(1)
run_adb("emulator-5556", ["shell", "input", "tap", "765", "168"])
time.sleep(1.5)

print("4. Focusing Box 0 on Joiner...")
run_adb("emulator-5556", ["shell", "input", "tap", "157", "968"])
time.sleep(0.3)

print(f"5. Typing code {code} into Joiner...")
for ch in code:
    run_adb("emulator-5556", ["shell", "input", "text", ch])
    time.sleep(0.2)

time.sleep(0.5)

print("6. Tapping 'Join Call' button on emulator-5556...")
run_adb("emulator-5556", ["shell", "input", "tap", "540", "1228"])

print("7. Waiting 3 seconds for signaling...")
time.sleep(3)

print("8. Capturing live screens of both devices...")
run_adb("emulator-5554", ["shell", "screencap", "-p", "/sdcard/host_prompt.png"])
run_adb("emulator-5554", ["pull", "/sdcard/host_prompt.png", "c:\\Users\\cpmoh\\.gemini\\antigravity\\brain\\ba06df15-a443-47ba-9a2e-7e0b1c4b25fb\\host_prompt.png"])

run_adb("emulator-5556", ["shell", "screencap", "-p", "/sdcard/joiner_waiting.png"])
run_adb("emulator-5556", ["pull", "/sdcard/joiner_waiting.png", "c:\\Users\\cpmoh\\.gemini\\antigravity\\brain\\ba06df15-a443-47ba-9a2e-7e0b1c4b25fb\\joiner_waiting.png"])

print("Done! Screenshots saved to artifacts directory.")
