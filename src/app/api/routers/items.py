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
