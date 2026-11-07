import subprocess
import time
import xml.etree.ElementTree as ET
import re

DEV_A = "emulator-5554"
DEV_B = "emulator-5556"

def dump_and_get_texts(dev):
    subprocess.run(['adb', '-s', dev, 'shell', 'uiautomator', 'dump', '/sdcard/dump.xml'], capture_output=True)
    res = subprocess.run(['adb', '-s', dev, 'shell', 'cat', '/sdcard/dump.xml'], capture_output=True, text=True)
    try:
        root = ET.fromstring(res.stdout)
        return [n.attrib.get('text') or n.attrib.get('content-desc') for n in root.iter('node') if n.attrib.get('text') or n.attrib.get('content-desc')]
    except Exception as e:
        return []

# Step 1: Device B taps Host Instant Call
print("Step 1: Device B hosting instant call...")
subprocess.run(['adb', '-s', DEV_B, 'shell', 'input', 'tap', '964', '2019'])
time.sleep(2)

# Extract code from Device B
subprocess.run(['adb', '-s', DEV_B, 'shell', 'uiautomator', 'dump', '/sdcard/dump.xml'], capture_output=True)
res_b = subprocess.run(['adb', '-s', DEV_B, 'shell', 'cat', '/sdcard/dump.xml'], capture_output=True, text=True)
root_b = ET.fromstring(res_b.stdout)
letters = [n.attrib.get('content-desc') for n in root_b.iter('node') if n.attrib.get('content-desc') and len(n.attrib.get('content-desc')) == 1 and n.attrib.get('content-desc').isalnum()]
code = ''.join(letters[:9])
print(f"Device B generated Instant Call Code: {code}")

# Step 2: Device A opens Connect to Instant Call
print("Step 2: Device A connecting with code...")
subprocess.run(['adb', '-s', DEV_A, 'shell', 'input', 'tap', '672', '104']) # Options
time.sleep(1)

# Tap Connect to Instant Call on Dev A
subprocess.run(['adb', '-s', DEV_A, 'shell', 'input', 'tap', '480', '128'])
time.sleep(2)

# Find boxes on Dev A
subprocess.run(['adb', '-s', DEV_A, 'shell', 'uiautomator', 'dump', '/sdcard/dump.xml'], capture_output=True)
res_a = subprocess.run(['adb', '-s', DEV_A, 'shell', 'cat', '/sdcard/dump.xml'], capture_output=True, text=True)
root_a = ET.fromstring(res_a.stdout)
boxes = []
for n in root_a.iter('node'):
    if n.attrib.get('class') == 'android.widget.EditText':
        b = n.attrib.get('bounds')
        m = re.findall(r'\d+', b)
        if len(m) >= 4:
            boxes.append(((int(m[0])+int(m[2]))//2, (int(m[1])+int(m[3]))//2))

print(f"Found {len(boxes)} boxes on Device A, entering {code}...")
for i in range(min(9, len(boxes))):
    cx, cy = boxes[i]
    subprocess.run(['adb', '-s', DEV_A, 'shell', 'input', 'tap', str(cx), str(cy)])
    time.sleep(0.05)
    subprocess.run(['adb', '-s', DEV_A, 'shell', 'input', 'text', code[i]])
    time.sleep(0.05)

# Dismiss keyboard on Dev A
subprocess.run(['adb', '-s', DEV_A, 'shell', 'input', 'keyevent', '111'])
time.sleep(1)

# Step 3: Check Device B screen to verify NO IN-APP NOTIFICATION CARD
time.sleep(2)
dev_b_texts = dump_and_get_texts(DEV_B)
print(f"Device B screen elements while ringing: {dev_b_texts[:8]}")
has_in_app_card = any("incoming call request" in str(t).lower() for t in dev_b_texts)
print(f"--> In-app notification card present on Device B: {has_in_app_card} (MUST BE False!)")

# Step 4: Take screenshot of Device B while ringing
subprocess.run(['adb', '-s', DEV_B, 'exec-out', 'screencap', '-p'], stdout=open('dev_b_ringing_native_only.png', 'wb'))
print("Captured screenshot: dev_b_ringing_native_only.png")

