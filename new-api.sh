#!/usr/bin/env bash
# Uso: ./new-api.sh <nombre-repo> [--no-remote]
# Requiere: git, uv (https://docs.astral.sh/uv), gh (autenticado con `gh auth login`)
set -euo pipefail

NAME="${1:?Uso: ./new-api.sh <nombre-repo> [--no-remote]}"
NO_REMOTE="${2:-}"

mkdir "$NAME" && cd "$NAME"
mkdir -p src/app/{core,api/routers,services,repositories,schemas} tests/{unit,integration} .github/workflows
touch src/app/__init__.py src/app/{core,api,api/routers,services,repositories,schemas}/__init__.py
touch tests/__init__.py tests/{unit,integration}/__init__.py

# ---------- pyproject ----------
cat > pyproject.toml <<EOF
[project]
name = "$NAME"
version = "0.1.0"
requires-python = ">=3.12"
dependencies = []

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.hatch.build.targets.wheel]
packages = ["src/app"]

[tool.ruff]
line-length = 100
target-version = "py312"

[tool.ruff.lint]
select = ["E", "F", "I", "B", "UP", "SIM", "N"]

[tool.mypy]
strict = true
mypy_path = "src"

[tool.pytest.ini_options]
testpaths = ["tests"]
EOF

uv add fastapi "uvicorn[standard]" pydantic-settings
uv add --dev ruff mypy pytest pytest-cov httpx pre-commit

# ---------- core ----------
cat > src/app/core/config.py <<'EOF'
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "api"
    debug: bool = False


settings = Settings()
EOF

# ---------- schemas ----------
cat > src/app/schemas/item.py <<'EOF'
from pydantic import BaseModel


class ItemCreate(BaseModel):
    name: str
    price: float


class ItemRead(ItemCreate):
    id: int
EOF

# ---------- repositories (acceso a datos) ----------
cat > src/app/repositories/item_repository.py <<'EOF'
from typing import Protocol

from app.schemas.item import ItemCreate, ItemRead


class ItemRepository(Protocol):
    def add(self, data: ItemCreate) -> ItemRead: ...
    def get(self, item_id: int) -> ItemRead | None: ...


class InMemoryItemRepository:
    """Implementación de ejemplo. Reemplázala por una con SQLAlchemy/Postgres."""

    def __init__(self) -> None:
        self._items: dict[int, ItemRead] = {}
        self._next_id = 1

    def add(self, data: ItemCreate) -> ItemRead:
        item = ItemRead(id=self._next_id, **data.model_dump())
        self._items[item.id] = item
        self._next_id += 1
        return item

    def get(self, item_id: int) -> ItemRead | None:
        return self._items.get(item_id)
EOF

# ---------- services (lógica de negocio) ----------
cat > src/app/services/item_service.py <<'EOF'
from app.repositories.item_repository import ItemRepository
from app.schemas.item import ItemCreate, ItemRead


class ItemNotFoundError(Exception):
    pass


class ItemService:
    def __init__(self, repo: ItemRepository) -> None:
        self._repo = repo

    def create(self, data: ItemCreate) -> ItemRead:
        return self._repo.add(data)

    def get(self, item_id: int) -> ItemRead:
        item = self._repo.get(item_id)
        if item is None:
            raise ItemNotFoundError(item_id)
        return item
EOF

# ---------- api (routers + inyección de dependencias) ----------
cat > src/app/api/deps.py <<'EOF'
from app.repositories.item_repository import InMemoryItemRepository
from app.services.item_service import ItemService

_item_repo = InMemoryItemRepository()


def get_item_service() -> ItemService:
    return ItemService(_item_repo)
EOF

cat > src/app/api/routers/health.py <<'EOF'
from fastapi import APIRouter

router = APIRouter(tags=["health"])


@router.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
EOF

cat > src/app/api/routers/items.py <<'EOF'
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status

from app.api.deps import get_item_service
from app.schemas.item import ItemCreate, ItemRead
from app.services.item_service import ItemNotFoundError, ItemService

router = APIRouter(prefix="/items", tags=["items"])
ServiceDep = Annotated[ItemService, Depends(get_item_service)]


@router.post("", status_code=status.HTTP_201_CREATED)
def create_item(data: ItemCreate, service: ServiceDep) -> ItemRead:
    return service.create(data)


@router.get("/{item_id}")
def get_item(item_id: int, service: ServiceDep) -> ItemRead:
    try:
        return service.get(item_id)
    except ItemNotFoundError:
        raise HTTPException(status_code=404, detail="Item not found") from None
EOF

cat > src/app/main.py <<'EOF'
from fastapi import FastAPI

from app.api.routers import health, items
from app.core.config import settings


def create_app() -> FastAPI:
    app = FastAPI(title=settings.app_name, debug=settings.debug)
    app.include_router(health.router)
    app.include_router(items.router)
    return app


app = create_app()
EOF

# ---------- tests ----------
cat > tests/unit/test_item_service.py <<'EOF'
import pytest

from app.repositories.item_repository import InMemoryItemRepository
from app.schemas.item import ItemCreate
from app.services.item_service import ItemNotFoundError, ItemService


def test_create_and_get() -> None:
    service = ItemService(InMemoryItemRepository())
    created = service.create(ItemCreate(name="café", price=2.5))
    assert service.get(created.id) == created


def test_get_missing_raises() -> None:
    with pytest.raises(ItemNotFoundError):
        ItemService(InMemoryItemRepository()).get(999)
EOF

cat > tests/integration/test_items_api.py <<'EOF'
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health() -> None:
    assert client.get("/health").json() == {"status": "ok"}


def test_create_then_get_item() -> None:
    res = client.post("/items", json={"name": "té", "price": 1.0})
    assert res.status_code == 201
    assert client.get(f"/items/{res.json()['id']}").status_code == 200


def test_missing_item_404() -> None:
    assert client.get("/items/99999").status_code == 404
EOF

# ---------- CI ----------
cat > .github/workflows/ci.yml <<'EOF'
name: CI

on:
  push:
    branches: [main]
  pull_request:

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v6
        with:
          enable-cache: true
      - run: uv sync --locked
      - run: uv run ruff check .
      - run: uv run ruff format --check .
      - run: uv run mypy src
      - run: uv run pytest --cov=app --cov-report=term-missing

  docker:
    needs: quality
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: docker build -t app:${{ github.sha }} .
EOF

cat > .github/dependabot.yml <<'EOF'
version: 2
updates:
  - package-ecosystem: "uv"
    directory: "/"
    schedule:
      interval: "weekly"
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
EOF

# ---------- pre-commit ----------
cat > .pre-commit-config.yaml <<'EOF'
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.6.9
    hooks:
      - id: ruff
        args: [--fix]
      - id: ruff-format
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.6.0
    hooks:
      - id: end-of-file-fixer
      - id: trailing-whitespace
      - id: check-yaml
      - id: detect-private-key
EOF

# ---------- Docker ----------
cat > Dockerfile <<'EOF'
FROM python:3.12-slim
COPY --from=ghcr.io/astral-sh/uv:latest /uv /bin/uv
WORKDIR /app
ENV UV_COMPILE_BYTECODE=1 PATH="/app/.venv/bin:$PATH"
COPY pyproject.toml uv.lock ./
RUN uv sync --locked --no-dev --no-install-project
COPY src ./src
RUN uv sync --locked --no-dev
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF

cat > .dockerignore <<'EOF'
.venv
.git
tests
__pycache__
.env
EOF

# ---------- varios ----------
cat > .gitignore <<'EOF'
.venv/
__pycache__/
*.pyc
.env
.mypy_cache/
.pytest_cache/
.ruff_cache/
.coverage
htmlcov/
dist/
EOF

cat > .env.example <<'EOF'
APP_NAME=api
DEBUG=false
EOF

printf "# %s\n\n\`\`\`bash\nuv sync\nuv run uvicorn app.main:app --reload\nuv run pytest\n\`\`\`\n" "$NAME" > README.md

# ---------- verificación local + git ----------
uv run ruff format .
uv run ruff check --fix .
uv run mypy src
uv run pytest -q

git init -b main -q
uv run pre-commit autoupdate || true
uv run pre-commit install
git add .
git commit -qm "chore: initial scaffold (layered FastAPI + CI)"

if [[ "$NO_REMOTE" != "--no-remote" ]]; then
  gh repo create "$NAME" --private --source=. --remote=origin --push
fi

echo "✅ Listo: $NAME"
