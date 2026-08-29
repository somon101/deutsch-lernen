from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Mirrors server/src/env.ts: DATABASE_URL and JWT_SECRET are required
    (app fails to start without them, same as the Node server throwing at
    import time); PORT and CORS_ORIGINS have the same defaults."""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str
    jwt_secret: str
    port: int = 4000
    cors_origins: str = "http://localhost:5173"
    # Minimum percent of correctly-answered questions for a lesson/level to
    # count as "passed" — a single named setting rather than a literal "75"
    # scattered through the code, so it can change without touching every
    # call site (per the approved content-taxonomy plan, 2026-08-26).
    pass_threshold_percent: int = 75

    # Optional: when both are set, uploads go to a public Supabase Storage
    # bucket instead of the local disk (needed once the API no longer runs
    # on a host with a persistent volume).
    supabase_url: str = ""
    supabase_service_role_key: str = ""
    supabase_storage_bucket: str = "uploads"

    # Optional: when both are set, push notifications (app/services/push.py)
    # actually call Firebase Cloud Messaging. Left unset, every push call is
    # a safe no-op — Notification rows still get written (so the admin UI
    # and "manual send" history keep working), nothing is ever delivered.
    # The service-account key is base64'd (firebase_service_account_json_b64)
    # rather than pasted raw: the raw JSON's commas collide with Cloud Run's
    # own comma-delimited env-var syntax and get corrupted in transit — see
    # the deploy workflow's comment on this same variable.
    firebase_project_id: str = ""
    firebase_service_account_json_b64: str = ""

    @property
    def cors_origins_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]

    @property
    def supabase_storage_enabled(self) -> bool:
        return bool(self.supabase_url.strip() and self.supabase_service_role_key.strip())

    @property
    def push_enabled(self) -> bool:
        return bool(self.firebase_project_id.strip() and self.firebase_service_account_json_b64.strip())

    @property
    def firebase_service_account_json(self) -> str:
        import base64

        if not self.firebase_service_account_json_b64.strip():
            return ""
        return base64.b64decode(self.firebase_service_account_json_b64).decode("utf-8")


settings = Settings()
