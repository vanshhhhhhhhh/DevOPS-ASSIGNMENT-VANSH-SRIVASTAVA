"""Application settings, read from environment variables.

The database URL can be given in one piece (DATABASE_URL, used by tests and
docker compose) or built from parts (DB_HOST, DB_PORT, DB_NAME, DB_USER,
DB_PASSWORD), which is how Kubernetes passes it: the parts come from a
ConfigMap and the password from a Secret.
"""

from functools import lru_cache
from urllib.parse import quote_plus

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "TicketDesk API"
    app_version: str = "1.0.0"
    environment: str = "local"
    log_level: str = "INFO"

    database_url: str | None = None
    db_host: str = "localhost"
    db_port: int = 5432
    db_name: str = "ticketdesk"
    db_user: str = "ticketdesk"
    db_password: str = ""

    @property
    def sqlalchemy_url(self) -> str:
        if self.database_url:
            return self.database_url
        return (
            f"postgresql+psycopg://{quote_plus(self.db_user)}:{quote_plus(self.db_password)}"
            f"@{self.db_host}:{self.db_port}/{self.db_name}"
        )


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
