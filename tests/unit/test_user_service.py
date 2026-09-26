import pytest

from app.repositories.user_repository import InMemoryUserRepository
from app.schemas.user import UserCreate
from app.services.user_service import (
    EmailAlreadyExistsError,
    UserNotFoundError,
    UserService,
)


def make_service() -> UserService:
    return UserService(InMemoryUserRepository())


def test_register_and_get() -> None:
    service = make_service()
    created = service.register(UserCreate(email="ana@test.cl", full_name="Ana"))
    assert service.get(created.id) == created


def test_duplicate_email_raises() -> None:
    service = make_service()
    service.register(UserCreate(email="ana@test.cl", full_name="Ana"))
    with pytest.raises(EmailAlreadyExistsError):
        service.register(UserCreate(email="ana@test.cl", full_name="Otra Ana"))


def test_get_missing_raises() -> None:
    with pytest.raises(UserNotFoundError):
        make_service().get(999)
