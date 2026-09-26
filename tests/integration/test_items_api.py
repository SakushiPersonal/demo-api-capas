from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health() -> None:
    assert client.get("/health").json() == {"status": "ok"}


def test_create_then_get_item() -> None:
    res = client.post("/items", json={"name": "té", "price": 1.0})
    assert res.status_code == 201
    assert client.get(f"/items/{res.json()['id']}").status_code == 200


def test_missing_item_404() -> None:
    assert client.get("/items/99999").status_code == 404
