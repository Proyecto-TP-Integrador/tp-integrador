#!/bin/bash
# TP10B — Verificación local: Render First y estado del despliegue en k3d.
# Uso (desde la raíz del repositorio): bash scripts/verificar.sh
set -uo pipefail

NS="${NS:-devops-portfolio}"
RELEASE="${RELEASE:-notes-app}"
CHART="${CHART:-helm/notes-app}"
VALUES="${VALUES:-helm/values-dev.yaml}"
HOST="${HOST:-devops-portfolio.local}"
URL="${URL:-http://127.0.0.1:18080}"
ERRORS=0

ok()   { echo "  [OK]   $1"; }
fail() { echo "  [FAIL] $1"; ERRORS=$((ERRORS+1)); }

echo "================================================="
echo "  VERIFICACIÓN HELM & INGRESS (TP10B - RENDER)"
echo "================================================="

echo ""
echo "--- 1. Validación de Renderizado (Render First) ---"
RENDER=$(mktemp)
trap 'rm -f "$RENDER"' EXIT
if helm lint "$CHART" -f "$VALUES" >/dev/null 2>&1; then
  ok "helm lint sin errores"
else
  fail "helm lint reportó errores"
fi
if helm template "$RELEASE" "$CHART" -f "$VALUES" > "$RENDER" 2>/dev/null; then
  ok "Renderizado de plantillas Go completado"
  if N=$(python3 -c "import yaml,sys; print(len([d for d in yaml.safe_load_all(open(sys.argv[1])) if d]))" "$RENDER" 2>/dev/null); then
    ok "YAML renderizado válido: $N objetos de Kubernetes"
  else
    fail "Error de sintaxis en el YAML renderizado"
  fi
  if kubectl apply --dry-run=server -f "$RENDER" >/dev/null 2>&1; then
    ok "El API Server acepta el manifiesto (kubectl apply --dry-run=server)"
  else
    fail "El API Server rechazó el manifiesto renderizado"
  fi
  if grep -Eq "checksum/config: [a-f0-9]{64}" "$RENDER"; then
    ok "Checksum SHA256 del ConfigMap calculado en el render"
  else
    fail "Checksum del ConfigMap sin calcular"
  fi
else
  fail "Error al ejecutar helm template"
fi

echo ""
echo "--- 2. Estado del Release de Helm ---"
STATUS=$(helm status "$RELEASE" -n "$NS" -o json 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['info']['status'])" 2>/dev/null)
[ "$STATUS" = "deployed" ] && ok "Release '$RELEASE' -> $STATUS" || fail "Release '$RELEASE' -> ${STATUS:-no encontrado}"

echo ""
echo "--- 3. Pods en Kubernetes ---"
while read -r NAME READY STATUS _; do
  [ -z "$NAME" ] && continue
  [ "$STATUS" = "Running" ] && ok "$NAME -> $STATUS ($READY)" || fail "$NAME -> $STATUS ($READY)"
done < <(kubectl get pods -n "$NS" -l app.kubernetes.io/instance="$RELEASE" --no-headers 2>/dev/null)

echo ""
echo "--- 4. Ingress (Capa 7) ---"
while read -r NAME _ HOSTS _; do
  [ -n "$NAME" ] && ok "Ingress '$NAME' -> $HOSTS"
done < <(kubectl get ingress -n "$NS" --no-headers 2>/dev/null)

echo ""
echo "--- 5. Pruebas HTTP vía Ingress ($HOST) ---"
for path in "/" "/health" "/api/notes"; do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: $HOST" --max-time 5 "$URL$path" 2>/dev/null)
  [ "$CODE" = "200" ] && ok "Endpoint $path -> HTTP $CODE" || fail "Endpoint $path -> HTTP $CODE"
done

echo ""
if [ "$ERRORS" -eq 0 ]; then
  echo "=== TP10B OK: Todos los checks de renderizado y despliegue pasaron ==="
else
  echo "=== ATENCIÓN: $ERRORS checks fallaron ==="
fi
exit "$ERRORS"
