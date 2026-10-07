"""Test setup.

Locally the tests use a throw-away SQLite file. In CI, DATABASE_URL points at a
PostgreSQL service container instead, so the same tests run against the real
database engine (the CI job runs "alembic upgrade head" first).
"""

import os
import tempfile

import pytest

if not os.environ.get("DATABASE_URL"):
    _tmp = tempfile.mkdtemp(prefix="ticketdesk-tests-")
    os.environ["DATABASE_URL"] = f"sqlite:///{_tmp}/test.db"

from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import delete  # noqa: E402

from app.db import Base, SessionLocal, engine  # noqa: E402
from app.main import app  # noqa: E402
from app.models import Ticket  # noqa: E402


@pytest.fixture(scope="session", autouse=True)
def _create_schema():
    # No-op on PostgreSQL in CI (Alembic already created the table).
    Base.metadata.create_all(bind=engine)
    yield


@pytest.fixture(autouse=True)
def _clean_tickets():
    yield
    with SessionLocal() as db:
        db.execute(delete(Ticket))
        db.commit()


@pytest.fixture
def client():
    with TestClient(app) as c:
        yield c


@pytest.fixture
def make_ticket(client):
    def _make(**overrides):
        payload = {
            "title": "Cannot log in",
            "description": "Password reset mail never arrives",
            "requester": "asha@example.com",
            "category": "ACCOUNT",
            "priority": "HIGH",
        }
        payload.update(overrides)
        response = client.post("/api/tickets", json=payload)
        assert response.status_code == 201, response.text
        return response.json()

    return _make
