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
        
    # Mark as joined with joiner info
    call_data["status"] = "joined"
    call_data["joiner_id"] = payload.joiner_id
    call_data["joiner_name"] = payload.joiner_name
    call_data["joined_at"] = now
    call_data["expires_at"] = now + 120 # Keep for 2 minutes for host retrieval

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

@app.post("/admin/send-notification", summary="Send Push Notification via FCM Admin")
def send_fcm_notification(
    payload: NotificationRequest,
    admin_user: str = Depends(get_current_admin)
):
    result = fcm_service.send_notification(
        target_token=payload.token,
        title=payload.title,
        body=payload.body,
        data=payload.data
    )
    return result

if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", 8000))
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=True)

