from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.engine import Connection

from app.core.config import settings
from app.db import get_db_connection
from app.repositories import list_exercises as list_exercises_from_db

router = APIRouter(prefix="/api/v1")


@router.get("/health")
def healthcheck(connection: Connection = Depends(get_db_connection)) -> dict:
    db_ok = connection.execute(text("SELECT 1")).scalar_one() == 1
    return {
        "ok": True,
        "service": "gym-trainer-api",
        "env": settings.app_env,
        "database": "ok" if db_ok else "error",
    }


@router.get("/exercises")
def list_exercises(connection: Connection = Depends(get_db_connection)) -> dict:
    exercises = list_exercises_from_db(connection)
    return {"ok": True, "data": [exercise.model_dump() for exercise in exercises]}
