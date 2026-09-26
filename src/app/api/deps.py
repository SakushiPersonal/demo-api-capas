from app.repositories.item_repository import InMemoryItemRepository
from app.services.item_service import ItemService

_item_repo = InMemoryItemRepository()


def get_item_service() -> ItemService:
    return ItemService(_item_repo)
