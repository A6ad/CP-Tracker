from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = (
        "postgresql+psycopg://cp_tracker:cp_tracker@localhost:5432/cp_tracker"
    )
    secret_key: str = "dev-only-insecure-change-me"
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 30
    refresh_token_expire_days: int = 30
    cors_origins: str = "*"

    # Email verification. The console backend logs the code instead of sending
    # mail, which keeps local development self-contained.
    email_backend: str = "console"
    email_from: str = "no-reply@cptracker.local"
    email_verification_ttl_minutes: int = 30
    email_verification_resend_seconds: int = 60

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]


settings = Settings()
