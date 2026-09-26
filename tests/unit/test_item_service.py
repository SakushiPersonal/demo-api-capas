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
