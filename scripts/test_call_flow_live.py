import subprocess
import time
import xml.etree.ElementTree as ET
import re

DEV_A = "emulator-5554"
DEV_B = "emulator-5556"

# Step 1: Device A initiates direct call to Bob_DevB
print("Device A calling Bob_DevB...")
subprocess.run(['adb', '-s', DEV_A, 'shell', 'input', 'tap', '360', '380'])
time.sleep(3)

# Step 2: Check Device B
print("Checking Device B for incoming call...")
subprocess.run(['adb', '-s', DEV_B, 'exec-out', 'screencap', '-p'], stdout=open('live_incoming_dev_b.png', 'wb'))

# Check notifications on Dev B
res = subprocess.run(['adb', '-s', DEV_B, 'shell', 'dumpsys', 'notification', '--noredact'], capture_output=True, text=True)
has_incoming_notif = 'simplysay_incoming_calls' in res.stdout
print(f"Device B incoming notification active: {has_incoming_notif}")

# Step 3: Accept call on Device B (tap Answer or tap notification intent)
# If native heads-up notification is displayed on screen, Answer is usually in upper right of notification
# Or we can launch accept intent directly:
print("Accepting call on Device B via native action...")
subprocess.run([
    'adb', '-s', DEV_B, 'shell', 'am', 'start',
    '-n', 'com.comlabs.simplysay/.MainActivity',
    '-e', 'action', 'accept_call',
    '-e', 'caller_name', 'Alice_DevA',
    '-e', 'caller_cit', '56bbebf9-d4cb-51be-be1d-d992092512e5',
    '-e', 'call_code', 'direct_call',
    '-e', 'call_type', 'video'
])

time.sleep(5)

# Step 4: Check CallScreen on both devices
subprocess.run(['adb', '-s', DEV_A, 'exec-out', 'screencap', '-p'], stdout=open('live_active_call_dev_a.png', 'wb'))
subprocess.run(['adb', '-s', DEV_B, 'exec-out', 'screencap', '-p'], stdout=open('live_active_call_dev_b.png', 'wb'))
print("Captured live call screenshots:")
print("  - live_active_call_dev_a.png")
print("  - live_active_call_dev_b.png")

