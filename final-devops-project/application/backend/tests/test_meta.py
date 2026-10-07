from sqlalchemy.exc import OperationalError

from app.db import get_db
from app.main import app


def test_root_reports_service_name(client):
    body = client.get("/").json()
    assert body["service"] == "TicketDesk API"
    assert body["docs"] == "/api/docs"


def test_health_is_ok_without_database(client):
    assert client.get("/health").json() == {"status": "ok"}
    assert client.get("/api/health").json() == {"status": "ok"}


def test_ready_when_database_answers(client):
    response = client.get("/ready")
    assert response.status_code == 200
    assert response.json()["database"] == "up"


def test_ready_returns_503_when_database_is_down(client):
    class BrokenSession:
        def execute(self, *args, **kwargs):
            raise OperationalError("SELECT 1", {}, Exception("connection refused"))

    app.dependency_overrides[get_db] = lambda: BrokenSession()
    try:
        response = client.get("/ready")
    finally:
        app.dependency_overrides.clear()
    assert response.status_code == 503
    assert response.json() == {"status": "unavailable", "database": "down"}


def test_openapi_docs_are_served_under_api_prefix(client):
    assert client.get("/api/docs").status_code == 200
    spec = client.get("/api/openapi.json").json()
    assert "/api/tickets" in spec["paths"]


def test_metrics_expose_http_and_business_counters(client, make_ticket):
    make_ticket(priority="URGENT")
    client.get("/api/tickets")
    text = client.get("/metrics").text
    assert "http_requests_total" in text
    assert 'ticketdesk_tickets_created_total{priority="URGENT"}' in text
