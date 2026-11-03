#!/bin/bash
set -uo pipefail

echo "=========================================================="
echo "  VERIFICACIÓN Y CARGA LOCAL A DEFECTDOJO API v2"
echo "=========================================================="
echo ""

DEFECTDOJO_URL="${DEFECTDOJO_URL:-http://localhost:8080}"
# v2: el token nunca se escribe en el script; se toma de la variable o de ~/.defectdojo-token
API_KEY="${DEFECTDOJO_API_KEY:-$(tr -d '[:space:]' < "$HOME/.defectdojo-token" 2>/dev/null)}"
# v2: product_id es de solo lectura en la API; el contexto se resuelve por nombre
PRODUCT_TYPE_NAME="${PRODUCT_TYPE_NAME:-Aplicaciones Web DevSecOps}"
PRODUCT_NAME="${PRODUCT_NAME:-Notes App}"
ENGAGEMENT_NAME="${ENGAGEMENT_NAME:-Manual Local Scan}"
REPORTS_DIR="${REPORTS_DIR:-reports-json}"

[ -n "$API_KEY" ] || { echo "[FAIL] Sin API key: exporte DEFECTDOJO_API_KEY o cree ~/.defectdojo-token"; exit 1; }
command -v jq >/dev/null || { echo "[FAIL] jq no está instalado"; exit 1; }

RESP=$(mktemp)
trap 'rm -f "$RESP"' EXIT
OK=0
FAIL=0

import_scan() {
  local SCAN_TYPE="$1" FILE_PATH="$2" TEST_TITLE="$3"
  if [ ! -s "$FILE_PATH" ]; then
    echo "  [WARN] $FILE_PATH no encontrado o vacío. Genere el reporte previo."
    return
  fi
  echo "  [+] Enviando $SCAN_TYPE ($FILE_PATH)..."
  # v2: se separa el cuerpo de la respuesta del código HTTP
  HTTP_CODE=$(curl -s -o "$RESP" -w "%{http_code}" -X POST "$DEFECTDOJO_URL/api/v2/import-scan/" \
    -H "Authorization: Token $API_KEY" \
    -F "product_type_name=$PRODUCT_TYPE_NAME" \
    -F "product_name=$PRODUCT_NAME" \
    -F "engagement_name=$ENGAGEMENT_NAME" \
    -F "auto_create_context=true" \
    -F "scan_type=$SCAN_TYPE" \
    -F "test_title=$TEST_TITLE" \
    -F "service=$TEST_TITLE" \
    -F "close_old_findings=true" \
    -F "file=@$FILE_PATH")
  # v2: el éxito se valida por HTTP 201, no por la palabra "scan_type" en la respuesta
  if [ "$HTTP_CODE" = "201" ]; then
    echo "      [OK] HTTP 201 | test_id=$(jq -r '.test_id' "$RESP") | findings=$(jq -r '.statistics.after.total.total // "n/d"' "$RESP")"
    OK=$((OK+1))
  else
    echo "      [FAIL] HTTP $HTTP_CODE: $(head -c 300 "$RESP")"
    FAIL=$((FAIL+1))
  fi
}

# Al crear un hallazgo activo, DefectDojo limpia is_mitigated y false_p, así que
# los estados mitigated y false-positive del risk_tracking de Threagile se pierden
# en la importación (accepted sí se conserva). Se aplican después por la API,
# buscando cada riesgo por su synthetic_id exacto en todo el producto.
sync_threagile_status() {
  local FILE="$1"
  [ -s "$FILE" ] || return 0
  jq -r '.[] | select(.risk_status=="mitigated" or .risk_status=="false-positive") | "\(.risk_status) \(.synthetic_id)"' "$FILE" |
  while read -r STATUS SID; do
    if [ "$STATUS" = "mitigated" ]; then
      BODY='{"active":false,"is_mitigated":true}'
    else
      BODY='{"active":false,"false_p":true}'
    fi
    IDS=$(curl -s -G "$DEFECTDOJO_URL/api/v2/findings/" -H "Authorization: Token $API_KEY" \
      --data-urlencode "product_name=$PRODUCT_NAME" --data-urlencode "unique_id_from_tool=$SID" \
      --data-urlencode "limit=50" | jq -r --arg sid "$SID" '.results[] | select(.unique_id_from_tool==$sid) | .id')
    [ -n "$IDS" ] || { echo "      [WARN] $SID no está en DefectDojo"; continue; }
    for FID in $IDS; do
      CODE=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH "$DEFECTDOJO_URL/api/v2/findings/$FID/" \
        -H "Authorization: Token $API_KEY" -H "Content-Type: application/json" -d "$BODY")
      echo "      [SYNC] $STATUS -> finding $FID (HTTP $CODE): $SID"
    done
  done
}

# v2: scan_type reales del código de DefectDojo 3.4 y un test por cada reporte
import_scan "ZAP Scan"               "$REPORTS_DIR/zap-report.xml"               "OWASP ZAP DAST"
import_scan "Threagile risks report" "$REPORTS_DIR/threagile-risks.json"         "Threagile Threat Model"
sync_threagile_status "$REPORTS_DIR/threagile-risks.json"
import_scan "Semgrep JSON Report"    "$REPORTS_DIR/semgrep-results.json"         "Semgrep SAST"
import_scan "Trivy Scan"             "$REPORTS_DIR/trivy-container-results.json" "Trivy Container"
import_scan "Trivy Scan"             "$REPORTS_DIR/trivy-sca-results.json"       "Trivy SCA"
import_scan "Trivy Scan"             "$REPORTS_DIR/trivy-iac-results.json"       "Trivy IaC"
import_scan "Checkov Scan"           "$REPORTS_DIR/checkov-results.json"         "Checkov IaC"
import_scan "Gitleaks Scan"          "$REPORTS_DIR/gitleaks-report.json"         "Gitleaks Secret Scanning"

echo ""
echo "=== Verificación completada: $OK importaciones OK, $FAIL con error ==="
[ "$FAIL" -eq 0 ]
