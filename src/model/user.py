# src/model/user.py
from dataclasses import dataclass


@dataclass
class User:
    id: int
    device_id: str
    created_at: str


@dataclass
class UserProfile:
    user_id: int
    age: int | None
    gender: str | None
    updated_at: str
