#!/bin/bash
# RA-06 — Aceptación temporal de riesgo en DefectDojo (Anexo A §7.2, rol Sec).
# Acepta los hallazgos HIGH/CRITICAL abiertos del Test "Trivy Container" que NO
# tienen versión corregida publicada (CVE de paquetes de Debian sin parche).
# Los que sí tienen parche quedan afuera: esos se corrigen, no se aceptan.
# La aceptación vence el $VENCE; al vencer, DefectDojo reactiva los hallazgos y el
# Security Gate vuelve a bloquear el despliegue hasta revisarlos.
# Uso: bash scripts/aceptar-riesgo-ra06.sh
set -uo pipefail

DEFECTDOJO_URL="${DEFECTDOJO_URL:-http://defectdojo.local:18080}"
API_KEY="${DEFECTDOJO_API_KEY:-$(tr -d '[:space:]' < "$HOME/.defectdojo-k8s-token" 2>/dev/null || tr -d '[:space:]' < "$HOME/.defectdojo-token" 2>/dev/null)}"
PRODUCT_NAME="${PRODUCT_NAME:-Notes App}"
ENGAGEMENT_NAME="${ENGAGEMENT_NAME:-CI/CD Automated Security Audits}"
TEST_TITLE="${TEST_TITLE:-Trivy Container}"
VENCE="${VENCE:-2026-12-03}"

[ -n "$API_KEY" ] || { echo "[FAIL] Sin API key"; exit 1; }
get() { curl -s -G -H "Authorization: Token $API_KEY" "$@"; }

ENG=$(get "$DEFECTDOJO_URL/api/v2/engagements/" --data-urlencode "name=$ENGAGEMENT_NAME" --data-urlencode "limit=10" | jq -r '.results[0].id // empty')
[ -n "$ENG" ] || { echo "[FAIL] No existe el Engagement \"$ENGAGEMENT_NAME\""; exit 1; }
TEST=$(get "$DEFECTDOJO_URL/api/v2/tests/" --data-urlencode "engagement=$ENG" --data-urlencode "limit=500" \
  | jq -r --arg t "$TEST_TITLE" '[.results[] | select(.title==$t)] | sort_by(.id) | last | .id // empty')
[ -n "$TEST" ] || { echo "[FAIL] No existe el Test \"$TEST_TITLE\""; exit 1; }

ABIERTOS=$(for S in High Critical; do
  get "$DEFECTDOJO_URL/api/v2/findings/" --data-urlencode "test=$TEST" --data-urlencode "severity=$S" \
    --data-urlencode "active=true" --data-urlencode "duplicate=false" --data-urlencode "risk_accepted=false" \
    --data-urlencode "limit=500" | jq -c '.results[]'
done)
# Sin versión corregida: fix_available=false o, si DefectDojo no informa ese campo,
# una mitigación sin número de versión
SIN_FIX='if .fix_available == null then ((.mitigation // "") | test("[0-9]") | not) else (.fix_available | not) end'
SIN_PARCHE=$(echo "$ABIERTOS" | jq -s "[.[] | select($SIN_FIX)]")
CON_PARCHE=$(echo "$ABIERTOS" | jq -s "[.[] | select($SIN_FIX | not)]")

echo "Test \"$TEST_TITLE\" (id $TEST): $(echo "$SIN_PARCHE" | jq length) HIGH/CRITICAL sin parche, $(echo "$CON_PARCHE" | jq length) con parche"
echo "$CON_PARCHE" | jq -r '.[] | "  [con parche, NO se acepta] \(.title)"'
[ "$(echo "$SIN_PARCHE" | jq length)" -gt 0 ] || { echo "Nada para aceptar."; exit 0; }

OWNER=$(get "$DEFECTDOJO_URL/api/v2/user_profile/" | jq -r '.user.id // empty')
[ -n "$OWNER" ] || OWNER=$(get "$DEFECTDOJO_URL/api/v2/users/" --data-urlencode "username=admin" | jq -r '.results[0].id')

BODY=$(jq -n --argjson ids "$(echo "$SIN_PARCHE" | jq '[.[].id]')" --argjson owner "$OWNER" --arg vence "${VENCE}T23:59:00Z" '{
  name: "RA-06 CVE de Debian sin parche (imagen base del backend)",
  owner: $owner,
  accepted_findings: $ids,
  recommendation: "A",
  recommendation_details: "No existe versión corregida publicada por Debian (Trivy informa la versión corregida vacía).",
  decision: "A",
  decision_details: "Control compensatorio: UID 10001, sistema de archivos de solo lectura, sin capabilities ni binarios setuid. Revisión en el Issue de RA-06.",
  accepted_by: "Equipo PIF (rol Sec)",
  expiration_date: $vence,
  reactivate_expired: true
}')
RESP=$(mktemp); trap 'rm -f "$RESP"' EXIT
CODE=$(curl -s -o "$RESP" -w "%{http_code}" -X POST "$DEFECTDOJO_URL/api/v2/risk_acceptance/" \
  -H "Authorization: Token $API_KEY" -H "Content-Type: application/json" -d "$BODY")
if [ "$CODE" = "201" ]; then
  echo "[OK] Risk Acceptance id=$(jq -r .id "$RESP") con $(jq '.accepted_findings | length' "$RESP") hallazgos, vence el $VENCE"
else
  echo "[FAIL] HTTP $CODE: $(head -c 400 "$RESP")"; exit 1
fi
