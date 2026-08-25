from pydantic import BaseModel, Field


class LoginRequest(BaseModel):
    login: str = Field(min_length=1)  # username OR email
    password: str = Field(min_length=1)
