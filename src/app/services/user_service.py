from app.repositories.user_repository import UserRepository
from app.schemas.user import UserCreate, UserRead


class UserNotFoundError(Exception):
    pass


class EmailAlreadyExistsError(Exception):
    pass


class UserService:
    def __init__(self, repo: UserRepository) -> None:
        self._repo = repo

    def register(self, data: UserCreate) -> UserRead:
        if self._repo.get_by_email(data.email) is not None:
            raise EmailAlreadyExistsError(data.email)
        return self._repo.add(data)

    def get(self, user_id: int) -> UserRead:
        user = self._repo.get(user_id)
        if user is None:
            raise UserNotFoundError(user_id)
        return user
