import os
import random
from datetime import datetime, timedelta, timezone
from typing import Optional

import requests
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, EmailStr

import firebase_admin
from firebase_admin import credentials, firestore


app = FastAPI(title="Login OTP API (Firestore)", version="1.0.0")
# allow_private_network: Chrome may send Access-Control-Request-Private-Network on localhost fetches.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
    allow_private_network=True,
)


def _load_local_env() -> None:
    env_path = os.path.join(os.path.dirname(__file__), ".env")
    if not os.path.exists(env_path):
        return

    with open(env_path, "r", encoding="utf-8") as env_file:
        for raw_line in env_file:
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            key = key.strip()
            value = value.strip().strip('"').strip("'")
            if key and (key not in os.environ or not os.environ.get(key)):
                os.environ[key] = value


_load_local_env()


def _init_firestore():
    if not firebase_admin._apps:
        service_account_path = (
            os.getenv("FIREBASE_SERVICE_ACCOUNT_PATH")
            or os.getenv("GOOGLE_APPLICATION_CREDENTIALS")
            or os.path.join(os.path.dirname(__file__), "serviceAccountKey.json")
        )
        if not service_account_path:
            raise RuntimeError("Missing FIREBASE_SERVICE_ACCOUNT_PATH environment variable.")
        if not os.path.exists(service_account_path):
            raise RuntimeError(
                "Firebase service account file not found. Set FIREBASE_SERVICE_ACCOUNT_PATH "
                "or place serviceAccountKey.json in the backend folder."
            )
        cred = credentials.Certificate(service_account_path)
        firebase_admin.initialize_app(cred)
    return firestore.client()


db = None


def _get_db():
    global db
    if db is None:
        db = _init_firestore()
    return db


RESEND_API_URL = "https://api.resend.com/emails"
OTP_TTL_MINUTES = int(os.getenv("OTP_TTL_MINUTES", "5"))


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class VerifyRequest(BaseModel):
    email: EmailStr
    otp_code: str


def _generate_otp() -> str:
    return f"{random.randint(0, 999999):06d}"


def _send_otp_email(to_email: str, otp_code: str) -> None:
    resend_api_key = os.getenv("RESEND_API_KEY") or os.getenv("RESEND_KEY")
    resend_from_email = os.getenv("RESEND_FROM_EMAIL", "onboarding@resend.dev")

    if not resend_api_key:
        raise HTTPException(
            status_code=500,
            detail="Missing RESEND_API_KEY. Add it to backend/.env (see .env.example).",
        )

    payload = {
        "from": resend_from_email,
        "to": [to_email],
        "subject": "Your Login OTP Code",
        "html": (
            "<p>Your OTP code is:</p>"
            f"<h2>{otp_code}</h2>"
            f"<p>This code expires in {OTP_TTL_MINUTES} minutes.</p>"
        ),
    }
    headers = {
        "Authorization": f"Bearer {resend_api_key}",
        "Content-Type": "application/json",
    }

    response = requests.post(RESEND_API_URL, json=payload, headers=headers, timeout=20)
    if response.status_code >= 400:
        raise HTTPException(
            status_code=502,
            detail=f"Resend failed: {response.status_code} {response.text}",
        )


@app.get("/")
def root():
    return {
        "status": "Server is running",
        "documentation": "Visit /docs to test the API",
    }


@app.get("/health")
def health():
    """Lightweight check for load balancers; does not touch Firestore."""
    return {"ok": True}


@app.post("/login")
def login(body: LoginRequest):
    email = body.email.lower().strip()
    password = body.password
    try:
        firestore_db = _get_db()
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    user_doc = firestore_db.collection("users").document(email)
    user_snapshot = user_doc.get()
    if not user_snapshot.exists:
        raise HTTPException(status_code=401, detail="Invalid email or password")

    user_data = user_snapshot.to_dict() or {}
    if user_data.get("password") != password:
        raise HTTPException(status_code=401, detail="Invalid email or password")

    otp_code = _generate_otp()
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=OTP_TTL_MINUTES)

    firestore_db.collection("otp_codes").document(email).set(
        {
            "email": email,
            "otp": otp_code,
            "expires_at": expires_at,
            "used": False,
            "created_at": datetime.now(timezone.utc),
        }
    )

    _send_otp_email(email, otp_code)
    return {"message": "User found. OTP sent to your email."}


@app.post("/verify-otp")
def verify_otp(body: VerifyRequest):
    email = body.email.lower().strip()
    provided_otp = body.otp_code.strip()
    try:
        firestore_db = _get_db()
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    otp_doc = firestore_db.collection("otp_codes").document(email).get()
    if not otp_doc.exists:
        raise HTTPException(status_code=400, detail="No OTP request found.")

    otp_data = otp_doc.to_dict()
    if otp_data.get("used"):
        raise HTTPException(status_code=400, detail="OTP already used.")

    expires_at: Optional[datetime] = otp_data.get("expires_at")
    if not expires_at or datetime.now(timezone.utc) > expires_at:
        raise HTTPException(status_code=400, detail="OTP expired.")

    if otp_data.get("otp") != provided_otp:
        raise HTTPException(status_code=401, detail="Invalid OTP.")

    firestore_db.collection("otp_codes").document(email).update(
        {"used": True, "verified_at": datetime.now(timezone.utc)}
    )
    return {"message": "Login Successful!", "status": "success"}


if __name__ == "__main__":
    import uvicorn

    port = int(os.getenv("PORT", "8000"))
    # 0.0.0.0: reliable on Windows (127.0.0.1, localhost, Android emulator 10.0.2.2).
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=True)
