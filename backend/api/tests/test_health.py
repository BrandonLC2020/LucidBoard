def test_health_endpoint_returns_ok(client):
    res = client.get("/api/health")
    assert res.status_code == 200
    assert res.json() == {"status": "ok"}


def test_404_returns_json(client):
    res = client.get("/api/nonexistent")
    assert res.status_code == 404
    assert res.headers["content-type"].startswith("application/json")
