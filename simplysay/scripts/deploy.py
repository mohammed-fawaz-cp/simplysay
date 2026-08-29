import os
import re
import sys
import subprocess
from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload

# ==============================================================================
# CONFIGURATION
# ==============================================================================
PACKAGE_NAME = "com.yourcompany.simplysay"  # Change to your Android package name
JSON_KEY_FILE = "android/pc-api-key.json"   # Path to Google Play Service Account JSON key
TRACK = "internal"                          # 'internal', 'alpha', 'beta', or 'production'
PUBSPEC_PATH = "pubspec.yaml"
AAB_PATH = "build/app/outputs/bundle/release/app-release.aab"

# ==============================================================================
# 1. AUTO-INCREMENT VERSION IN PUBSPEC.YAML
# ==============================================================================
def increment_version():
    print("🔢 [1/3] Updating pubspec.yaml version...")
    if not os.path.exists(PUBSPEC_PATH):
        print(f"❌ Error: {PUBSPEC_PATH} not found!")
        sys.exit(1)

    with open(PUBSPEC_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    # Match version string like version: 1.0.0+1
    pattern = r"version:\s*(\d+\.\d+\.\d+)\+(\d+)"
    match = re.search(pattern, content)

    if not match:
        print("❌ Error: Could not find version pattern 'X.Y.Z+N' in pubspec.yaml")
        sys.exit(1)

    version_name = match.group(1)
    old_build_number = int(match.group(2))
    new_build_number = old_build_number + 1
    new_version_str = f"version: {version_name}+{new_build_number}"

    new_content = re.sub(pattern, new_version_str, content)

    with open(PUBSPEC_PATH, "w", encoding="utf-8") as f:
        f.write(new_content)

    print(f"✅ Version updated from {version_name}+{old_build_number} ➔ {version_name}+{new_build_number}")
    return version_name, new_build_number

# ==============================================================================
# 2. BUILD APP BUNDLE (.AAB)
# ==============================================================================
def build_aab():
    print("\n🔨 [2/3] Building Release App Bundle (AAB)...")
    cmd = ["flutter", "build", "appbundle", "--release"]
    
    result = subprocess.run(cmd, shell=True)
    if result.returncode != 0:
        print("❌ Error: Flutter build failed!")
        sys.exit(1)

    if not os.path.exists(AAB_PATH):
        print(f"❌ Error: Compiled bundle not found at {AAB_PATH}")
        sys.exit(1)

    print(f"✅ Built AAB successfully: {AAB_PATH}")

# ==============================================================================
# 3. UPLOAD TO GOOGLE PLAY STORE API
# ==============================================================================
def upload_to_play_store(build_number):
    print(f"\n🚀 [3/3] Uploading AAB to Google Play Store ({TRACK.upper()} track)...")

    if not os.path.exists(JSON_KEY_FILE):
        print(f"❌ Error: Service Account Key file '{JSON_KEY_FILE}' not found!")
        print("   Please place your pc-api-key.json inside the android/ folder.")
        sys.exit(1)

    credentials = service_account.Credentials.from_service_account_file(
        JSON_KEY_FILE,
        scopes=["https://www.googleapis.com/auth/androidpublisher"]
    )

    service = build("androidpublisher", "v3", credentials=credentials)

    # Step 3a: Create an Edit Session
    edit_request = service.edits().insert(packageName=PACKAGE_NAME, body={})
    edit = edit_request.execute()
    edit_id = edit["id"]
    print(f"   Created Edit Session ID: {edit_id}")

    # Step 3b: Upload the App Bundle
    media = MediaFileUpload(AAB_PATH, mimetype="application/octet-stream", resumable=True)
    bundle_upload = service.edits().bundles().upload(
        packageName=PACKAGE_NAME,
        editId=edit_id,
        media_body=media
    )
    bundle_response = bundle_upload.execute()
    version_code = bundle_response["versionCode"]
    print(f"   Uploaded AAB Version Code: {version_code}")

    # Step 3c: Assign Bundle to Track (Internal/Alpha/Beta/Production)
    track_body = {
        "releases": [
            {
                "versionCodes": [str(version_code)],
                "status": "completed"
            }
        ]
    }
    service.edits().tracks().update(
        packageName=PACKAGE_NAME,
        editId=edit_id,
        track=TRACK,
        body=track_body
    ).execute()
    print(f"   Assigned Version Code {version_code} to track '{TRACK}'")

    # Step 3d: Commit the Edit Session
    service.edits().commit(packageName=PACKAGE_NAME, editId=edit_id).execute()
    print(f"✅ Successfully published to Google Play {TRACK.upper()} track!")

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================
if __name__ == "__main__":
    print("=" * 60)
    print("🚀 AUTOMATED FLUTTER PLAY STORE DEPLOYMENT")
    print("=" * 60)

    _, new_build_no = increment_version()
    build_aab()
    upload_to_play_store(new_build_no)

    print("=" * 60)
    print("🎉 DEPLOYMENT COMPLETE! Testers will receive the update shortly.")
    print("=" * 60)
