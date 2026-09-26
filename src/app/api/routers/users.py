from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status

from app.api.deps import get_user_service
from app.schemas.user import UserCreate, UserRead
from app.services.user_service import (
    EmailAlreadyExistsError,
    UserNotFoundError,
    UserService,
)

router = APIRouter(prefix="/users", tags=["users"])
ServiceDep = Annotated[UserService, Depends(get_user_service)]


@router.post("", status_code=status.HTTP_201_CREATED)
def register_user(data: UserCreate, service: ServiceDep) -> UserRead:
    try:
        return service.register(data)
    except EmailAlreadyExistsError:
        raise HTTPException(status_code=409, detail="Email already registered") from None


@router.get("/{user_id}")
def get_user(user_id: int, service: ServiceDep) -> UserRead:
    try:
        return service.get(user_id)
    except UserNotFoundError:
        raise HTTPException(status_code=404, detail="User not found") from None
