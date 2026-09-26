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
