import os
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    APP_NAME: str = "Simply Say Server"
    ADMIN_USERNAME: str = os.getenv("ADMIN_USERNAME", "admin")
    ADMIN_PASSWORD: str = os.getenv("ADMIN_PASSWORD", "simplysay_secure_2026")
    SECRET_KEY: str = os.getenv("SECRET_KEY", "simplysay_jwt_secret_key_change_in_production")
    FCM_CREDENTIALS_PATH: str = os.getenv("FCM_CREDENTIALS_PATH", "firebase_service_account.json")

    class Config:
        env_file = ".env"

settings = Settings()
