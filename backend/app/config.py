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

    @property
    def cors_origins_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]


settings = Settings()
