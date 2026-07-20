# src/model/rating.py
from dataclasses import dataclass


@dataclass
class Rating:
    id: int
    user_id: int
    item_id: int
    domain_code: str
    status: str
    source: str
    created_at: str
    updated_at: str
