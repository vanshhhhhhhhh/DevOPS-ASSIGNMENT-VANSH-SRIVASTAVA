import pytest

from app.main import create_app


@pytest.fixture
def client():
    app = create_app()
    app.config["TESTING"] = True
    with app.test_client() as client:
        yield client


def test_index_page(client):
    response = client.get("/")
    assert response.status_code == 200
    assert b"Session 16" in response.data


def test_health(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.get_json() == {"status": "ok"}


def test_info_uses_build_env(client, monkeypatch):
    monkeypatch.setenv("APP_VERSION", "9.9.9")
    monkeypatch.setenv("GIT_SHA", "abc1234")
    data = client.get("/api/info").get_json()
    assert data["version"] == "9.9.9"
    assert data["git_sha"] == "abc1234"


def test_calc_add(client):
    response = client.get("/api/calc?op=add&a=10&b=5")
    assert response.status_code == 200
    assert response.get_json()["result"] == 15


def test_calc_divide_by_zero_is_400(client):
    response = client.get("/api/calc?op=divide&a=1&b=0")
    assert response.status_code == 400
    assert "zero" in response.get_json()["error"]


def test_calc_rejects_unknown_op_and_bad_numbers(client):
    assert client.get("/api/calc?op=power&a=2&b=3").status_code == 400
    assert client.get("/api/calc?op=add&a=two&b=3").status_code == 400
