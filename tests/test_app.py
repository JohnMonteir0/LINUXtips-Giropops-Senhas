# tests/test_app.py
import importlib.util
import pathlib

# Load app.py as a module so we can import "app" without changing your code
_spec = importlib.util.spec_from_file_location("app_module", pathlib.Path("app.py"))
_appmod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_appmod)

app = _appmod.app
app.testing = True
client = app.test_client()

def test_healthz():
    resp = client.get("/healthz")
    assert resp.status_code == 200
    assert resp.get_json()["status"] == "ok"

def test_metrics():
    resp = client.get("/metrics")
    assert resp.status_code == 200
    # prometheus exposition format is text; just sanity-check non-empty
    assert len(resp.data) > 0
