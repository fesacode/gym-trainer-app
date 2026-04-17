from sqlalchemy import text
from sqlalchemy.engine import Connection

from app.models.exercise import Exercise


_EXERCISE_QUERY = text(
    """
    SELECT id, name, muscle_group, difficulty, equipment
    FROM exercises
    ORDER BY created_at ASC, name ASC
    """
)


def list_exercises(connection: Connection) -> list[Exercise]:
    rows = connection.execute(_EXERCISE_QUERY).mappings().all()
    return [Exercise(**row) for row in rows]
