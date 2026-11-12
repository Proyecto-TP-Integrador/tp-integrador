import pytest
import json
import sys, os
from datetime import datetime
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

# Mock de psycopg2 para no necesitar Postgres en los tests unitarios
from unittest.mock import patch, MagicMock

@pytest.fixture
def client():
    with patch('app.get_conn') as mock_conn:
        mock_cursor = MagicMock()
        mock_conn.return_value.cursor.return_value = mock_cursor
        # La app usa conexión y cursor como context managers.
        mock_conn.return_value.__enter__.return_value.cursor.return_value.__enter__.return_value = mock_cursor
        mock_cursor.fetchall.return_value = [
            (1, "Nota test", "Contenido test", datetime(2026, 5, 13))
        ]
        mock_cursor.fetchone.return_value = (1,)
        import app as flask_app
        flask_app.app.config['TESTING'] = True
        with flask_app.app.test_client() as client:
            yield client

def test_health(client):
    with patch('app.get_conn') as mock_conn:
        mock_conn.return_value  # simula conexión exitosa
        r = client.get('/health')
        assert r.status_code == 200
        data = json.loads(r.data)
        assert 'status' in data

def test_get_notes(client):
    r = client.get('/api/notes')
    assert r.status_code == 200
    data = json.loads(r.data)
    assert isinstance(data, list)

def test_create_note(client):
    r = client.post(
        '/api/notes',
        data=json.dumps({'title': 'Test', 'content': 'Contenido'}),
        content_type='application/json'
    )
    assert r.status_code == 201

def test_create_note_sin_titulo(client):
    r = client.post(
        '/api/notes',
        data=json.dumps({'content': 'Sin título'}),
        content_type='application/json'
    )
    # Debe fallar con 400 o 500 si no hay título
    assert r.status_code in [400, 500]

def test_delete_note(client):
    r = client.delete('/api/notes/1')
    assert r.status_code == 200


def test_cors_no_autoriza_otros_origenes(client):
    """SS-17 (CWE-942): un sitio externo no recibe permiso para leer la API."""
    r = client.get('/api/notes', headers={'Origin': 'https://sitio-atacante.example'})
    assert r.status_code == 200
    assert 'Access-Control-Allow-Origin' not in r.headers


def test_cabeceras_de_seguridad(client):
    """SS-18 (CWE-693): la API envía nosniff y el resto de las cabeceras defensivas."""
    for ruta in ('/api/notes', '/health', '/ruta-inexistente'):
        r = client.get(ruta)
        assert r.headers['X-Content-Type-Options'] == 'nosniff'
        assert r.headers['Cache-Control'] == 'no-store'
        assert r.headers['Cross-Origin-Resource-Policy'] == 'same-origin'
        assert "frame-ancestors 'none'" in r.headers['Content-Security-Policy']


def test_password_db_desde_archivo(tmp_path, monkeypatch):
    """SS-16 (CKV_K8S_35): la contraseña se toma del archivo del Secret montado."""
    import app as flask_app
    archivo = tmp_path / "password"
    archivo.write_text("clave-de-prueba\n")
    monkeypatch.setenv("DB_PASSWORD_FILE", str(archivo))
    monkeypatch.setenv("DB_PASSWORD", "no-debe-usarse")
    assert flask_app.leer_password_db() == "clave-de-prueba"


def test_metrics_registra_errores_4xx(client):
    """Anexo B §5.2: http_requests_total cuenta los 4xx por ruta y código."""
    from prometheus_client import REGISTRY
    etiquetas = {"method": "POST", "endpoint": "/api/notes", "status": "400"}
    antes = REGISTRY.get_sample_value("http_requests_total", etiquetas) or 0
    client.post('/api/notes', json={})
    assert REGISTRY.get_sample_value("http_requests_total", etiquetas) == antes + 1
    r = client.get('/metrics')
    assert r.status_code == 200
    assert b'http_request_duration_seconds_bucket' in r.data


def test_metrics_no_crea_series_por_url_inventada(client):
    client.get('/no-existe-123')
    r = client.get('/metrics')
    assert b'endpoint="sin_ruta"' in r.data
    assert b'no-existe-123' not in r.data


def test_error_de_base_cuenta_y_responde_503(client):
    """TP12C: app_db_errors_total sube y el cliente no ve el detalle del error."""
    import psycopg2
    from prometheus_client import REGISTRY
    antes = REGISTRY.get_sample_value("app_db_errors_total") or 0
    with patch('app.get_conn', side_effect=psycopg2.OperationalError("password authentication failed")):
        r = client.get('/api/notes')
    assert r.status_code == 503
    assert b'password' not in r.data
    assert REGISTRY.get_sample_value("app_db_errors_total") == antes + 1
