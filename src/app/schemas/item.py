from pydantic import BaseModel


class ItemCreate(BaseModel):
    name: str
    price: float


class ItemRead(ItemCreate):
    id: int
