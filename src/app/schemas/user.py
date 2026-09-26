from pydantic import BaseModel, EmailStr


class UserCreate(BaseModel):
    email: EmailStr
    full_name: str


class UserRead(UserCreate):
    id: int
    is_active: bool = True
