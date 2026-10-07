from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

Category = Literal["GENERAL", "BILLING", "TECHNICAL", "ACCOUNT"]
Priority = Literal["LOW", "MEDIUM", "HIGH", "URGENT"]
Status = Literal["OPEN", "IN_PROGRESS", "RESOLVED", "CLOSED"]


class TicketCreate(BaseModel):
    title: str = Field(min_length=3, max_length=200)
    description: str = Field(default="", max_length=5000)
    requester: str = Field(min_length=1, max_length=120)
    category: Category = "GENERAL"
    priority: Priority = "MEDIUM"


class TicketUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=3, max_length=200)
    description: str | None = Field(default=None, max_length=5000)
    category: Category | None = None
    priority: Priority | None = None
    status: Status | None = None


class TicketOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    title: str
    description: str
    requester: str
    category: Category
    priority: Priority
    status: Status
    created_at: datetime
    updated_at: datetime


class TicketStats(BaseModel):
    total: int
    by_status: dict[str, int]
    by_priority: dict[str, int]
