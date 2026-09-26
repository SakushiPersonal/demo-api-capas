from app.repositories.item_repository import InMemoryItemRepository
from app.repositories.user_repository import InMemoryUserRepository
from app.services.item_service import ItemService
from app.services.user_service import UserService

_item_repo = InMemoryItemRepository()
_user_repo = InMemoryUserRepository()


def get_item_service() -> ItemService:
    return ItemService(_item_repo)


def get_user_service() -> UserService:
    return UserService(_user_repo)
