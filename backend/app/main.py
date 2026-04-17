from fastapi import FastAPI

from app.api.routes import router
from app.core.config import settings

app = FastAPI(title=settings.app_name, version="0.2.0")
app.include_router(router)


@app.get("/")
def root() -> dict:
    return {
        "ok": True,
        "message": "Gym Trainer API running",
        "docs": "/docs",
        "api_base": "/api/v1",
    }
