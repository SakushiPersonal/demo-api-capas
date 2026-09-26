from typing import Protocol

from app.schemas.user import UserCreate, UserRead


class UserRepository(Protocol):
    def add(self, data: UserCreate) -> UserRead: ...
    def get(self, user_id: int) -> UserRead | None: ...
    def get_by_email(self, email: str) -> UserRead | None: ...


class InMemoryUserRepository:
    def __init__(self) -> None:
        self._users: dict[int, UserRead] = {}
        self._next_id = 1

    def add(self, data: UserCreate) -> UserRead:
        user = UserRead(id=self._next_id, **data.model_dump())
        self._users[user.id] = user
        self._next_id += 1
        return user

    def get(self, user_id: int) -> UserRead | None:
        return self._users.get(user_id)

    def get_by_email(self, email: str) -> UserRead | None:
        return next((u for u in self._users.values() if u.email == email), None)
