import pytest

from app.main import MAX_NOTE_LENGTH, create_app


@pytest.fixture
def client():
    app = create_app()
    app.config["TESTING"] = True
    with app.test_client() as client:
        yield client


def test_index_page(client):
    response = client.get("/")
    assert response.status_code == 200
    assert b"Session 17" in response.data


def test_health_and_ready(client):
    assert client.get("/health").get_json() == {"status": "ok"}
    assert client.get("/ready").get_json() == {"status": "ready"}


def test_security_headers_on_every_response(client):
    for path in ("/", "/health", "/does-not-exist"):
        headers = client.get(path).headers
        assert headers["X-Content-Type-Options"] == "nosniff"
        assert headers["X-Frame-Options"] == "DENY"
        assert "default-src 'self'" in headers["Content-Security-Policy"]


def test_info_reports_api_key_presence_but_never_the_value(client, monkeypatch):
    monkeypatch.setenv("DEMO_API_KEY", "fake-value-for-tests")
    response = client.get("/api/info")
    assert response.get_json()["api_key_configured"] is True
    assert b"fake-value-for-tests" not in response.data


def test_create_list_and_get_note(client):
    created = client.post("/api/notes", json={"text": "  scan before you ship  "})
    assert created.status_code == 201
    assert created.get_json() == {"id": 1, "text": "scan before you ship"}
    assert client.get("/api/notes").get_json() == {"notes": [{"id": 1, "text": "scan before you ship"}]}
    assert client.get("/api/notes/1").get_json()["text"] == "scan before you ship"


@pytest.mark.parametrize(
    "body",
    [None, [], {"text": ""}, {"text": "   "}, {"text": 42}, {"text": "x" * (MAX_NOTE_LENGTH + 1)}],
    ids=["no-body", "json-list", "empty", "blank", "not-a-string", "too-long"],
)
def test_invalid_notes_are_rejected(client, body):
    response = client.post("/api/notes", json=body)
    assert response.status_code == 400
    assert "error" in response.get_json()


def test_unknown_note_and_route_return_json_404(client):
    assert client.get("/api/notes/999").status_code == 404
    response = client.get("/nope")
    assert response.status_code == 404
    assert response.get_json() == {"error": "not found"}


def test_wrong_method_returns_405(client):
    assert client.delete("/api/notes").status_code == 405


def test_oversized_body_returns_413(client):
    response = client.post("/api/notes", data="x" * (32 * 1024), content_type="application/json")
    assert response.status_code == 413
