#!/bin/bash
# TP18F — Deduplicación global en DefectDojo.
# Aplica y verifica la configuración que evita que el mismo hallazgo se cargue
# N veces (una por ejecución del pipeline):
#   1. System Settings: Enable Deduplication = True, Delete Duplicates = False.
#   2. Engagement de la CI/CD: deduplicar dentro del mismo Engagement.
#   3. Worker de Celery en Running (es el que procesa la deduplicación).
#   4. Cantidad de Tests por herramienta: con reimport-scan queda uno por cada una.
# Uso: bash scripts/configurar-dedup-defectdojo.sh            (aplica y verifica)
#      SOLO_VERIFICAR=1 bash scripts/configurar-dedup-defectdojo.sh
set -uo pipefail

DEFECTDOJO_URL="${DEFECTDOJO_URL:-http://defectdojo.local:18080}"
API_KEY="${DEFECTDOJO_API_KEY:-$(tr -d '[:space:]' < "$HOME/.defectdojo-k8s-token" 2>/dev/null || tr -d '[:space:]' < "$HOME/.defectdojo-token" 2>/dev/null)}"
PRODUCT_NAME="${PRODUCT_NAME:-Notes App}"
ENGAGEMENT_NAME="${ENGAGEMENT_NAME:-CI/CD Automated Security Audits}"
SOLO_VERIFICAR="${SOLO_VERIFICAR:-0}"

[ -n "$API_KEY" ] || { echo "[FAIL] Sin API key: exporte DEFECTDOJO_API_KEY o cree ~/.defectdojo-k8s-token"; exit 1; }
command -v jq >/dev/null || { echo "[FAIL] jq no está instalado"; exit 1; }

api() { curl -s -H "Authorization: Token $API_KEY" -H "Content-Type: application/json" "$@"; }

echo "=========================================================="
echo "  TP18F: DEDUPLICACIÓN EN DEFECTDOJO"
echo "=========================================================="

echo ""
echo "--- 1. System Settings ---"
SS=$(api "$DEFECTDOJO_URL/api/v2/system_settings/")
SS_ID=$(echo "$SS" | jq -r '.results[0].id')
[ "$SS_ID" != "null" ] || { echo "[FAIL] No se pudo leer System Settings (¿token de un superusuario?)"; exit 1; }
if [ "$SOLO_VERIFICAR" != "1" ]; then
  api -X PATCH "$DEFECTDOJO_URL/api/v2/system_settings/$SS_ID/" \
    -d '{"enable_deduplication": true, "delete_duplicates": false}' > /dev/null
  SS=$(api "$DEFECTDOJO_URL/api/v2/system_settings/")
fi
echo "$SS" | jq -r '.results[0] | "  enable_deduplication = \(.enable_deduplication)\n  delete_duplicates    = \(.delete_duplicates)"'

echo ""
echo "--- 2. Engagement \"$ENGAGEMENT_NAME\" ---"
ENG=$(curl -s -G -H "Authorization: Token $API_KEY" "$DEFECTDOJO_URL/api/v2/engagements/" \
  --data-urlencode "name=$ENGAGEMENT_NAME" --data-urlencode "limit=10" \
  | jq -r '[.results[]] | first | .id // empty')
if [ -z "$ENG" ]; then
  echo "  [WARN] El Engagement no existe todavía: lo crea el pipeline en la primera importación."
else
  if [ "$SOLO_VERIFICAR" != "1" ]; then
    api -X PATCH "$DEFECTDOJO_URL/api/v2/engagements/$ENG/" -d '{"deduplication_on_engagement": true}' > /dev/null
  fi
  api "$DEFECTDOJO_URL/api/v2/engagements/$ENG/" \
    | jq -r '"  id = \(.id)\n  deduplication_on_engagement = \(.deduplication_on_engagement)"'
fi

echo ""
echo "--- 3. Worker de Celery ---"
if command -v kubectl >/dev/null; then
  kubectl -n defectdojo get pods --no-headers 2>/dev/null | grep -i celery \
    | awk '{printf "  %-55s %s\n", $1, $3}' || echo "  [WARN] No se encontraron pods de Celery"
else
  echo "  [WARN] kubectl no disponible"
fi

if [ -n "$ENG" ]; then
  echo ""
  echo "--- 4. Tests del Engagement por herramienta ---"
  api "$DEFECTDOJO_URL/api/v2/tests/?engagement=$ENG&limit=500" \
    | jq -r '[.results[] | .title // "(sin título)"] | group_by(.) | .[] | "  \(length)  \(.[0])"'
  echo "  (con reimport-scan cada herramienta queda con un único Test que se actualiza en cada ejecución)"
fi
