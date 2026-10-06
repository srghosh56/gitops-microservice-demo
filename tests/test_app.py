import pytest

from app.main import create_app


@pytest.fixture
def client():
    app = create_app({"TESTING": True, "ERROR_RATE": 0.0, "APP_VERSION": "test"})
    return app.test_client()


def test_index_returns_service_info(client):
    response = client.get("/")
    assert response.status_code == 200
    body = response.get_json()
    assert body["service"] == "demo-service"
    assert body["version"] == "test"


def test_health_and_readiness(client):
    assert client.get("/healthz").status_code == 200
    assert client.get("/readyz").status_code == 200


def test_metrics_count_requests(client):
    client.get("/")
    metrics = client.get("/metrics").get_data(as_text=True)
    assert 'http_requests_total{endpoint="/",method="GET",status="200"}' in metrics
    assert "http_request_duration_seconds_bucket" in metrics


def test_probes_are_not_counted(client):
    client.get("/healthz")
    metrics = client.get("/metrics").get_data(as_text=True)
    assert 'endpoint="/healthz"' not in metrics


def test_simulated_errors():
    app = create_app({"TESTING": True, "ERROR_RATE": 1.0})
    assert app.test_client().get("/").status_code == 500


def test_unknown_route_returns_404(client):
    assert client.get("/does-not-exist").status_code == 404


def test_invalid_error_rate_env_falls_back_to_zero(monkeypatch):
    monkeypatch.setenv("ERROR_RATE", "not-a-number")
    app = create_app({"TESTING": True})
    assert app.config["ERROR_RATE"] == 0.0
