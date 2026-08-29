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

    @property
    def cors_origins_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]

    @property
    def supabase_storage_enabled(self) -> bool:
        return bool(self.supabase_url.strip() and self.supabase_service_role_key.strip())


settings = Settings()
