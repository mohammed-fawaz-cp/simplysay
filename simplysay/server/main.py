import os
from fastapi import FastAPI, Depends, Request, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel
from typing import Optional, Dict

from config import settings
from security import get_current_admin
from fcm_admin import fcm_service

app = FastAPI(
    title=settings.APP_NAME,
    description="Simple, secure backend for Simply Say (Zero-Server-Storage)",
    version="1.0.0"
)

# CORS Middleware Setup
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

templates = Jinja2Templates(directory=os.path.join(os.path.dirname(__file__), "templates"))

class NotificationRequest(BaseModel):
    token: str
    title: str
    body: str
    data: Optional[Dict[str, str]] = None

@app.get("/", summary="Health Check")
def health_check():
    return {
        "status": "online",
        "app": settings.APP_NAME,
        "storage": "zero_server_storage (all data on user devices)"
    }

@app.get("/admin", response_class=HTMLResponse, summary="Secure Admin Dashboard")
def admin_dashboard(request: Request, admin_user: str = Depends(get_current_admin)):
    return templates.TemplateResponse(
        "admin.html",
        {
            "request": request,
            "admin_user": admin_user,
            "fcm_active": fcm_service.is_initialized
        }
    )

# In-Memory Instant Call Store (Cleaned automatically after 10 mins or upon joining)
import time

instant_call_store: Dict[str, dict] = {}

class CreateInstantCallRequest(BaseModel):
    code: str
    host_id: str
    host_name: str

class JoinInstantCallRequest(BaseModel):
    code: str
    joiner_id: str
    joiner_name: str

@app.post("/api/v1/instant-call/create", summary="Register Instant Call Code")
def create_instant_call(payload: CreateInstantCallRequest):
    clean_code = payload.code.replace("-", "").replace(" ", "").upper()
    now = time.time()
    
    # Clean expired entries
    expired = [c for c, data in instant_call_store.items() if data["expires_at"] < now]
    for c in expired:
        instant_call_store.pop(c, None)
        
    instant_call_store[clean_code] = {
        "status": "waiting",
        "host_id": payload.host_id,
        "host_name": payload.host_name,
        "created_at": now,
        "expires_at": now + 600 # 10 minutes
    }
    return {"status": "success", "code": clean_code, "expires_in": 600}

@app.post("/api/v1/instant-call/join", summary="Join Instant Call Code")
def join_instant_call(payload: JoinInstantCallRequest):
    clean_code = payload.code.replace("-", "").replace(" ", "").upper()
    now = time.time()
    
    call_data = instant_call_store.get(clean_code)
    if not call_data:
        raise HTTPException(status_code=404, detail="Invalid or expired Instant Call code.")
        
    if call_data["expires_at"] < now:
        instant_call_store.pop(clean_code, None)
        raise HTTPException(status_code=410, detail="Instant Call code has expired.")
        
    # Mark as joined with joiner info (preserve full 600s TTL from creation or extend to 600s)
    call_data["status"] = "joined"
    call_data["joiner_id"] = payload.joiner_id
    call_data["joiner_name"] = payload.joiner_name
    call_data["joined_at"] = now
    call_data["expires_at"] = max(call_data.get("expires_at", now + 600), now + 600)

    return {
        "status": "success",
        "host_id": call_data["host_id"],
        "host_name": call_data["host_name"]
    }

@app.get("/api/v1/instant-call/status/{code}", summary="Check Instant Call Code Status")
def get_instant_call_status(code: str):
    clean_code = code.replace("-", "").replace(" ", "").upper()
    call_data = instant_call_store.get(clean_code)
    if not call_data:
        return {"status": "not_found"}
    return {
        "status": call_data.get("status", "waiting"),
        "host_id": call_data.get("host_id"),
        "host_name": call_data.get("host_name"),
        "joiner_id": call_data.get("joiner_id"),
        "joiner_name": call_data.get("joiner_name")
    }

@app.delete("/api/v1/instant-call/clear-all", summary="Clear All Instant Call Sessions")
@app.post("/api/v1/instant-call/clear-all", summary="Clear All Instant Call Sessions (POST variant)")
def clear_all_instant_calls():
    count = len(instant_call_store)
    instant_call_store.clear()
    return {
        "status": "success",
        "message": f"Cleared {count} instant call session(s). Database is now empty.",
        "cleared_count": count
    }

@app.delete("/api/v1/instant-call/cancel/{code}", summary="Cancel Instant Call Code")
def cancel_instant_call(code: str):
    clean_code = code.replace("-", "").replace(" ", "").upper()
    existed = clean_code in instant_call_store
    instant_call_store.pop(clean_code, None)
    return {
        "status": "success",
        "message": f"Session {clean_code} removed." if existed else "Session not found."
    }

@app.post("/admin/clear-data", summary="Admin Clear All Server Data")
@app.delete("/admin/clear-data", summary="Admin Clear All Server Data (DELETE variant)")
def admin_clear_data(admin_user: str = Depends(get_current_admin)):
    count = len(instant_call_store)
    instant_call_store.clear()
    return {
        "status": "success",
        "admin": admin_user,
        "message": f"All data cleared by {admin_user}.",
        "cleared_count": count
    }

# In-Memory & Ephemeral User Registry for Private Contact Discovery (Zero Persistent Server Storage)
import sqlite3

DB_PATH = os.path.join(os.path.dirname(__file__), "server_ephemeral.db")

def init_server_db():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS users (
            phone_hash TEXT PRIMARY KEY,
            cit TEXT NOT NULL,
            csit TEXT NOT NULL,
            device_id TEXT NOT NULL,
            fcm_token TEXT,
            registered_at INTEGER
        )
    """)
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_users_cit ON users(cit)")
    conn.commit()
    conn.close()

init_server_db()

# In-Memory FCM Device Token Registry (Fast cache)
fcm_token_registry: Dict[str, str] = {}

class RegisterUserRequest(BaseModel):
    phone_hash: str
    cit: str
    csit: str
    device_id: str
    fcm_token: Optional[str] = None

class ContactSyncRequest(BaseModel):
    phone_hashes: list[str]

class RegisterFCMTokenRequest(BaseModel):
    cit: str
    fcm_token: str

class SendDataCallPushRequest(BaseModel):
    target_token: Optional[str] = None
    target_cit: Optional[str] = None
    target_phone_hash: Optional[str] = None
    caller_cit: str
    caller_name: str
    caller_avatar: Optional[str] = None
    call_code: str
    sdp_offer: Optional[str] = None
    call_type: str = "video"
    ttl_seconds: Optional[int] = 35
    timestamp: Optional[str] = None

class SendCancelCallPushRequest(BaseModel):
    target_token: Optional[str] = None
    target_cit: Optional[str] = None
    caller_cit: str
    caller_name: str
    caller_avatar: Optional[str] = None
    call_code: str
    was_answered: Optional[str] = "false"
    timestamp: Optional[str] = None

@app.post("/api/v1/users/register", summary="Register Ephemeral User Profile with FCM Token")
@app.post("/api/v1/user/register", summary="Register Ephemeral User Profile (alias)")
def register_user(payload: RegisterUserRequest):
    now = int(time.time())
    if payload.fcm_token:
        fcm_token_registry[payload.cit] = payload.fcm_token

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("""
        INSERT INTO users (phone_hash, cit, csit, device_id, fcm_token, registered_at)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(phone_hash) DO UPDATE SET
            cit=excluded.cit,
            csit=excluded.csit,
            device_id=excluded.device_id,
            fcm_token=COALESCE(excluded.fcm_token, users.fcm_token),
            registered_at=excluded.registered_at
    """, (payload.phone_hash, payload.cit, payload.csit, payload.device_id, payload.fcm_token, now))
    conn.commit()
    conn.close()

    return {
        "status": "success",
        "message": "User registered successfully",
        "phone_hash": payload.phone_hash,
        "cit": payload.cit
    }

@app.post("/api/v1/contacts/sync", summary="Privacy-Preserving Contact Discovery")
def sync_contacts(payload: ContactSyncRequest):
    if not payload.phone_hashes:
        return {"status": "success", "matches": []}

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    placeholders = ",".join(["?"] * len(payload.phone_hashes))
    cursor.execute(f"""
        SELECT phone_hash, cit, csit, fcm_token FROM users
        WHERE phone_hash IN ({placeholders})
    """, payload.phone_hashes)
    rows = cursor.fetchall()
    conn.close()

    matches = []
    for r in rows:
        matches.append({
            "phone_hash": r[0],
            "cit": r[1],
            "csit": r[2],
            "fcm_token": r[3] or fcm_token_registry.get(r[1], "")
        })

    return {"status": "success", "matches": matches}

@app.post("/api/v1/fcm/register-token", summary="Register Ephemeral Device FCM Token")
def register_fcm_token(payload: RegisterFCMTokenRequest):
    fcm_token_registry[payload.cit] = payload.fcm_token
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("UPDATE users SET fcm_token = ? WHERE cit = ?", (payload.fcm_token, payload.cit))
        conn.commit()
        conn.close()
    except Exception:
        pass

    return {
        "status": "success",
        "cit": payload.cit,
        "message": "FCM token registered successfully."
    }

@app.get("/api/v1/fcm/token/{cit}", summary="Get FCM Token by CIT")
def get_fcm_token(cit: str):
    token = fcm_token_registry.get(cit)
    if not token:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("SELECT fcm_token FROM users WHERE cit = ? LIMIT 1", (cit,))
        row = cursor.fetchone()
        conn.close()
        if row and row[0]:
            token = row[0]
            fcm_token_registry[cit] = token

    if not token:
        raise HTTPException(status_code=404, detail="Token not found for CIT")
    return {"cit": cit, "fcm_token": token}

@app.post("/api/v1/fcm/send-call-push", summary="Send High-Priority Data-Only Call Push")
def send_data_call_push(payload: SendDataCallPushRequest):
    token = payload.target_token or fcm_token_registry.get(payload.target_cit or "")
    if not token and (payload.target_cit or payload.target_phone_hash):
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        if payload.target_cit:
            cursor.execute("SELECT fcm_token FROM users WHERE cit = ? LIMIT 1", (payload.target_cit,))
        elif payload.target_phone_hash:
            cursor.execute("SELECT fcm_token FROM users WHERE phone_hash = ? LIMIT 1", (payload.target_phone_hash,))
        row = cursor.fetchone()
        conn.close()
        if row and row[0]:
            token = row[0]

    if not token:
        raise HTTPException(status_code=404, detail="Recipient FCM token not available.")

    data_payload = {
        "type": "incoming_call",
        "caller_cit": payload.caller_cit,
        "caller_name": payload.caller_name,
        "call_code": payload.call_code,
        "call_type": payload.call_type,
        "ttl_seconds": str(payload.ttl_seconds or 35),
        "timestamp": payload.timestamp or str(int(time.time() * 1000)),
    }

    result = fcm_service.send_data_call_push(
        target_token=token,
        data=data_payload
    )
    result["timestamp"] = int(time.time() * 1000)
    return result

@app.post("/api/v1/fcm/send-cancel-push", summary="Send High-Priority Data-Only Call Cancellation Push")
def send_cancel_call_push(payload: SendCancelCallPushRequest):
    token = payload.target_token or fcm_token_registry.get(payload.target_cit or "")
    if not token and payload.target_cit:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("SELECT fcm_token FROM users WHERE cit = ? LIMIT 1", (payload.target_cit,))
        row = cursor.fetchone()
        conn.close()
        if row and row[0]:
            token = row[0]

    if not token:
        raise HTTPException(status_code=404, detail="Recipient FCM token not available.")

    data_payload = {
        "type": "call_cancelled",
        "caller_cit": payload.caller_cit,
        "caller_name": payload.caller_name,
        "caller_avatar": payload.caller_avatar or "",
        "call_code": payload.call_code,
        "was_answered": payload.was_answered or "false",
        "ttl_seconds": "10",
        "timestamp": payload.timestamp or str(int(time.time() * 1000)),
    }

    result = fcm_service.send_data_call_push(
        target_token=token,
        data=data_payload
    )
    result["timestamp"] = int(time.time() * 1000)
    return result

@app.get("/debug-tokens")
def debug_tokens():
    return fcm_token_registry

if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", 8000))
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=True)

