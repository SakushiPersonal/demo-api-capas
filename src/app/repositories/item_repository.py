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
