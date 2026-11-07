import os
import logging
from typing import Dict, Any, Optional
import firebase_admin
from firebase_admin import credentials, messaging
from config import settings

logger = logging.getLogger("simplysay.fcm")

class FCMAdminService:
    def __init__(self):
        self.is_initialized = False
        self._initialize()

    def _initialize(self):
        import json
        # 1. First check environment variables (ideal for Vercel, Render, Heroku)
        env_credentials = os.getenv("FIREBASE_CREDENTIALS") or os.getenv("FCM_CREDENTIALS_JSON")
        if env_credentials:
            try:
                cred_dict = json.loads(env_credentials)
                if "private_key" in cred_dict and "\\n" in cred_dict["private_key"]:
                    cred_dict["private_key"] = cred_dict["private_key"].replace("\\n", "\n")
                cred = credentials.Certificate(cred_dict)
                firebase_admin.initialize_app(cred)
                self.is_initialized = True
                logger.info("Firebase Admin SDK initialized successfully via environment variable.")
                return
            except Exception as e:
                logger.error(f"Failed to initialize Firebase Admin SDK from environment variable: {e}")

        # 2. Check credentials file path
        cred_path = settings.FCM_CREDENTIALS_PATH
        if os.path.exists(cred_path):
            try:
                with open(cred_path, 'r', encoding='utf-8') as f:
                    cred_dict = json.load(f)

                # Ensure newlines in PEM private key are properly unescaped
                if "private_key" in cred_dict and "\\n" in cred_dict["private_key"]:
                    cred_dict["private_key"] = cred_dict["private_key"].replace("\\n", "\n")

                cred = credentials.Certificate(cred_dict)
                firebase_admin.initialize_app(cred)
                self.is_initialized = True
                logger.info("Firebase Admin SDK initialized successfully from file.")
            except Exception as e:
                logger.error(f"Failed to initialize Firebase Admin SDK: {e}")
        else:
            logger.warning(
                f"FCM credentials file not found at '{cred_path}' and no FIREBASE_CREDENTIALS env var provided. "
                "FCM messaging will be disabled until credentials are provided."
            )

    def send_data_call_push(
        self,
        target_token: str,
        data: Dict[str, str]
    ) -> Dict[str, Any]:
        """
        Sends a pure DATA-ONLY FCM message with high priority.
        Crucial: No 'notification' block is included, ensuring Android routes
        the raw payload straight to background/native receivers for custom call overlays.
        """
        if not self.is_initialized:
            return {
                "success": False,
                "error": "Firebase Admin SDK is not initialized. Check firebase-service-account.json"
            }

        try:
            # Stringify all data values for FCM strict string dictionary contract
            sanitized_data = {str(k): str(v) for k, v in data.items()}
            ttl_seconds = int(data.get("ttl_seconds", 35))
            message = messaging.Message(
                data=sanitized_data,
                token=target_token,
                android=messaging.AndroidConfig(
                    priority="high",
                    ttl=ttl_seconds,  # 35 seconds for live VoIP call invitations
                ),
            )
            response = messaging.send(message)
            logger.info(f"✅ Data-only FCM call push sent successfully: {response}")
            return {"success": True, "message_id": response}
        except Exception as e:
            logger.error(f"⚠️ Error sending data-only FCM push: {e}")
            return {"success": False, "error": str(e)}

fcm_service = FCMAdminService()
