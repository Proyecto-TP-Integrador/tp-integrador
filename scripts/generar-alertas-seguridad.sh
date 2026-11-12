#!/bin/bash
# TP12C Paso 4 — Simulación de tráfico anómalo para verificar las alertas.
# Genera, en paralelo y durante DURACION segundos, el tráfico que dispara:
#   - IngressPicoErrores4xx5xx           escaneo de rutas inexistentes (404)
#   - InvasionIntentosAccesoNoPermitido  métodos no admitidos sobre la API (405)
#   - RafagaErrores4xx (Anexo B §5.2)    payloads inválidos (400)
# Con SIMULAR_DB=1 además detiene PostgreSQL 90 segundos para disparar
# PicoErroresConexionBaseDatos (lo vuelve a levantar al terminar).
# Uso: bash scripts/generar-alertas-seguridad.sh
set -uo pipefail

URL="${URL:-http://127.0.0.1:18080}"
HOST="${HOST:-devops-portfolio.local}"
NS="${NS:-devops-portfolio}"
DURACION="${DURACION:-180}"
SIMULAR_DB="${SIMULAR_DB:-0}"
DIR=$(mktemp -d)

echo "=========================================================="
echo "  SIMULACIÓN DE ATAQUE / TRÁFICO ANÓMALO (TP12C)"
echo "=========================================================="
echo "Objetivo: $URL (Host: $HOST) durante $DURACION segundos"
echo ""

rafaga() {  # rafaga <nombre> <comando curl...>
  local NOMBRE="$1"; shift
  local FIN=$((SECONDS + DURACION))
  while [ "$SECONDS" -lt "$FIN" ]; do
    "$@" -s -o /dev/null -w "%{http_code}\n" -H "Host: $HOST" --max-time 3 >> "$DIR/$NOMBRE" 2>/dev/null || true
  done
}

echo "[1/3] Escaneo de rutas inexistentes en la API (HTTP 404 en el Ingress)..."
rafaga escaneo  bash -c 'curl "$0/api/admin-$RANDOM" "$@"' "$URL" &
echo "[2/3] Métodos no permitidos sobre /api/notes (HTTP 405)..."
rafaga metodos  curl -X PUT "$URL/api/notes" &
echo "[3/3] Payloads inválidos en POST /api/notes (HTTP 400)..."
rafaga payloads curl -X POST -H "Content-Type: application/json" -d '{}' "$URL/api/notes" &

if [ "$SIMULAR_DB" = "1" ]; then
  echo "[extra] PostgreSQL detenido 90 s: la API responde 503 y cuenta app_db_errors_total..."
  trap 'kubectl -n "$NS" scale deploy/postgres --replicas=1 >/dev/null' EXIT
  kubectl -n "$NS" scale deploy/postgres --replicas=0 >/dev/null
  DURACION=90 rafaga base-datos curl "$URL/api/notes" &
fi

echo ""
echo "Generando tráfico... ver el avance en Prometheus (Alerts) y en Grafana."
wait

if [ "$SIMULAR_DB" = "1" ]; then
  kubectl -n "$NS" scale deploy/postgres --replicas=1 >/dev/null
  kubectl -n "$NS" rollout status deploy/postgres --timeout=180s
  trap - EXIT
fi

echo ""
echo "=== Simulación completada: requests enviados por código HTTP ==="
for F in "$DIR"/*; do
  printf "  %-11s " "$(basename "$F")"
  sort "$F" | uniq -c | awk '{printf "%s x HTTP %s   ", $1, $2}'
  echo ""
done
rm -rf "$DIR"
echo ""
echo "Alertas en Prometheus: http://prometheus.local:18080/alerts"
echo "Panel en Grafana:      http://grafana.local:18080 (Notes App - PIF, fila Sad Paths & Security Events)"
