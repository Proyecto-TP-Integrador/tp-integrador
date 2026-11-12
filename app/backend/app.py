from flask import Flask, jsonify, request
import datetime
import os

import psycopg2

# SS-17 (CWE-942): sin CORS. El frontend y la API se publican en el mismo
# origen (Ingress: "/" al frontend y "/api" al backend), así que el navegador
# no necesita permisos de origen cruzado. Antes, CORS(app) respondía
# Access-Control-Allow-Origin: * (o reflejaba cualquier Origin) y cualquier
# sitio externo podía leer las notas desde el navegador de la víctima.
app = Flask(__name__)

# SS-18 (CWE-693): cabeceras de seguridad en todas las respuestas de la API.
# OWASP ZAP reportaba "X-Content-Type-Options Header Missing": sin nosniff el
# navegador puede interpretar una respuesta JSON como HTML o script.
CABECERAS_SEGURIDAD = {
    "X-Content-Type-Options": "nosniff",
    # La API solo devuelve datos: no carga recursos ni se muestra en un iframe
    "Content-Security-Policy": "default-src 'none'; frame-ancestors 'none'",
    "X-Frame-Options": "DENY",
    # Las notas no quedan guardadas en cachés del navegador ni de proxies
    "Cache-Control": "no-store",
    # Aislamiento frente a lecturas de otros orígenes (Spectre)
    "Cross-Origin-Resource-Policy": "same-origin",
    "Referrer-Policy": "no-referrer",
}


@app.after_request
def agregar_cabeceras_seguridad(response):
    for cabecera, valor in CABECERAS_SEGURIDAD.items():
        response.headers.setdefault(cabecera, valor)
    return response

def leer_password_db():
    """SS-16 (CKV_K8S_35): la contraseña se lee de un archivo montado desde el
    Secret de Kubernetes (DB_PASSWORD_FILE), no de una variable de entorno.
    Una variable de entorno queda visible en `kubectl describe`, en /proc del
    proceso, en volcados de error y en todos los procesos hijos. DB_PASSWORD se
    mantiene solo para el contenedor efímero del DAST en el pipeline."""
    ruta = os.getenv("DB_PASSWORD_FILE")
    if ruta:
        with open(ruta, encoding="utf-8") as archivo:
            return archivo.read().strip()
    return os.getenv("DB_PASSWORD", "")


def get_conn():
    return psycopg2.connect(
        host=os.getenv("DB_HOST", "db"),
        port=os.getenv("DB_PORT", "5432"),
        dbname=os.getenv("DB_NAME", "notesdb"),
        user=os.getenv("DB_USER", "postgres"),
        password=leer_password_db()
    )

def init_db():
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("""
        CREATE TABLE IF NOT EXISTS notes (
            id SERIAL PRIMARY KEY,
            title VARCHAR(200) NOT NULL,
            content TEXT,
            created_at TIMESTAMP DEFAULT NOW()
        )
    """)
    conn.commit()
    cur.close()
    conn.close()

@app.route("/health")
def health():
    try:
        conn = get_conn()
        conn.close()
        db_status = "connected"
    except Exception as e:
        db_status = f"error: {e}"
    return jsonify({
        "status": "ok",
        "db": db_status,
        "time": datetime.datetime.utcnow().isoformat()
    })

@app.route("/api/notes", methods=["GET"])
def get_notes():
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("SELECT id, title, content, created_at FROM notes ORDER BY created_at DESC")
    rows = cur.fetchall()
    cur.close(); conn.close()
    return jsonify([
        {"id": r[0], "title": r[1], "content": r[2], "created_at": str(r[3])}
        for r in rows
    ])

@app.route("/api/notes", methods=["POST"])
def create_note():
    data = request.get_json()
    if not data or not data.get("title"):
        return jsonify({"error": "title es obligatorio"}), 400
    conn = get_conn()
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO notes (title, content) VALUES (%s, %s) RETURNING id",
        (data["title"], data.get("content", ""))
    )
    note_id = cur.fetchone()[0]
    conn.commit()
    cur.close(); conn.close()
    return jsonify({"id": note_id, "message": "nota creada"}), 201

@app.route("/api/notes/<int:note_id>", methods=["DELETE"])
def delete_note(note_id):
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("DELETE FROM notes WHERE id = %s", (note_id,))
    conn.commit()
    cur.close(); conn.close()
    return jsonify({"message": "nota eliminada"})


if __name__ == "__main__":
    init_db()
    app.run(host="0.0.0.0", port=5000)
