from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_register_user() -> None:
    res = client.post("/users", json={"email": "bruno@test.cl", "full_name": "Bruno"})
    assert res.status_code == 201
    assert res.json()["is_active"] is True


def test_duplicate_email_returns_409() -> None:
    payload = {"email": "dup@test.cl", "full_name": "Dup"}
    assert client.post("/users", json=payload).status_code == 201
    assert client.post("/users", json=payload).status_code == 409


def test_invalid_email_returns_422() -> None:
    res = client.post("/users", json={"email": "no-es-email", "full_name": "X"})
    assert res.status_code == 422


def test_missing_user_returns_404() -> None:
    assert client.get("/users/99999").status_code == 404
