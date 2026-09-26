from fastapi import FastAPI

from app.api.routers import health, items
from app.core.config import settings


def create_app() -> FastAPI:
    app = FastAPI(title=settings.app_name, debug=settings.debug)
    app.include_router(health.router)
    app.include_router(items.router)
    return app


app = create_app()
