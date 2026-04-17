from pydantic import BaseModel


class Exercise(BaseModel):
    id: str
    name: str
    muscle_group: str
    difficulty: str
    equipment: str


class ExerciseListResponse(BaseModel):
    ok: bool = True
    data: list[Exercise]
