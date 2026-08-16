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
        cred_path = settings.FCM_CREDENTIALS_PATH
        if os.path.exists(cred_path):
            try:
                cred = credentials.Certificate(cred_path)
                firebase_admin.initialize_app(cred)
                self.is_initialized = True
                logger.info("Firebase Admin SDK initialized successfully.")
            except Exception as e:
                logger.error(f"Failed to initialize Firebase Admin SDK: {e}")
        else:
            logger.warning(
                f"FCM credentials file not found at '{cred_path}'. "
                "FCM messaging will be disabled until credentials are provided."
            )

    def send_notification(
        self,
        target_token: str,
        title: str,
        body: str,
        data: Optional[Dict[str, str]] = None
    ) -> Dict[str, Any]:
        if not self.is_initialized:
            return {
                "success": False,
                "error": "Firebase Admin SDK is not initialized. Add valid firebase_service_account.json"
            }

        try:
            message = messaging.Message(
                notification=messaging.Notification(
                    title=title,
                    body=body,
                ),
                data=data or {},
                token=target_token,
            )
            response = messaging.send(message)
            return {"success": True, "message_id": response}
        except Exception as e:
            logger.error(f"Error sending FCM message: {e}")
            return {"success": False, "error": str(e)}

fcm_service = FCMAdminService()
