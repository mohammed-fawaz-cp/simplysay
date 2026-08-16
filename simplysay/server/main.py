import sqlite3
import os
from typing import List
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

app = FastAPI(
    title="SimplySay Discovery API",
    description="FastAPI Backend for User Identity Registration and Contact Discovery Matching",
    version="1.0.0"
)

# Enable CORS for Flutter Client / Web testing
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

DB_FILE = "simplysay_server.db"

def init_db():
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS users (
            phone_hash TEXT PRIMARY KEY,
            cit TEXT NOT NULL,
            csit TEXT NOT NULL,
            device_id TEXT NOT NULL,
            registered_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_phone_hash ON users(phone_hash)")
    conn.commit()
    conn.close()

init_db()

# Request Models
class UserRegisterRequest(BaseModel):
    phone_hash: str
    cit: str
    csit: str
    device_id: str

class ContactSyncRequest(BaseModel):
    phone_hashes: List[str]

# Response Models
class MatchedContact(BaseModel):
    phone_hash: str
    cit: str
    csit: str

class ContactSyncResponse(BaseModel):
    matches: List[MatchedContact]

@app.get("/")
def read_root():
    return {"status": "ok", "message": "SimplySay Discovery Server is running"}

@app.post("/api/v1/users/register", status_code=201)
def register_user(req: UserRegisterRequest):
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    try:
        cursor.execute(
            """
            INSERT INTO users (phone_hash, cit, csit, device_id)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(phone_hash) DO UPDATE SET
                cit=excluded.cit,
                csit=excluded.csit,
                device_id=excluded.device_id
            """,
            (req.phone_hash, req.cit, req.csit, req.device_id)
        )
        conn.commit()
        return {"status": "success", "message": "User registered successfully", "phone_hash": req.phone_hash}
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        conn.close()

@app.post("/api/v1/contacts/sync", response_model=ContactSyncResponse)
def sync_contacts(req: ContactSyncRequest):
    if not req.phone_hashes:
        return ContactSyncResponse(matches=[])

    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    try:
        placeholders = ",".join(["?"] * len(req.phone_hashes))
        query = f"SELECT phone_hash, cit, csit FROM users WHERE phone_hash IN ({placeholders})"
        cursor.execute(query, req.phone_hashes)
        rows = cursor.fetchall()

        matches = [
            MatchedContact(phone_hash=row[0], cit=row[1], csit=row[2])
            for row in rows
        ]
        return ContactSyncResponse(matches=matches)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        conn.close()

@app.get("/api/v1/users")
def list_users():
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    cursor.execute("SELECT phone_hash, cit, csit, device_id, registered_at FROM users")
    rows = cursor.fetchall()
    conn.close()
    return [
        {"phone_hash": r[0], "cit": r[1], "csit": r[2], "device_id": r[3], "registered_at": r[4]}
        for r in rows
    ]

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
