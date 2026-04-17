from collections.abc import Generator

from sqlalchemy import create_engine
from sqlalchemy.engine import Connection

from app.core.config import settings

engine = create_engine(settings.database_url, future=True, pool_pre_ping=True)


def get_db_connection() -> Generator[Connection, None, None]:
    with engine.connect() as connection:
        yield connection
