from fastapi import FastAPI

from app.api.routers import health, items, users
from app.core.config import settings


def create_app() -> FastAPI:
    app = FastAPI(title=settings.app_name, debug=settings.debug)
    app.include_router(health.router)
    app.include_router(items.router)
    app.include_router(users.router)
    return app


app = create_app()
