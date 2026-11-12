#!/bin/bash
echo "Esperando a Postgres..."
# La conexión de prueba usa la misma función que la app (contraseña desde
# DB_PASSWORD_FILE, SS-16)
until python3 -c "import app; app.get_conn().close()" 2>/dev/null; do
    echo "  Postgres no disponible, reintentando en 2s..."
    sleep 2
done
echo "Postgres listo. Iniciando app..."
python3 -c "import app; app.init_db()" 2>/dev/null || true
exec "$@"
