#!/usr/bin/env bash
# Mueve un Issue a una columna del tablero respetando el límite WIP = 2 por integrante.
# Uso: scripts/mover.sh <numero_issue> "<Status>"
set -euo pipefail

PROJ=1
OWNER="Proyecto-TP-Integrador"
WIP=2
N="${1:?Falta el número de Issue}"
DESTINO="${2:?Falta el Status destino}"

item_y_status() {
  gh api graphql -F n="$1" -f query='
  query($n: Int!) {
    repository(owner: "Proyecto-TP-Integrador", name: "devops-PIF") {
      issue(number: $n) {
        projectItems(first: 5) { nodes {
          id project { number }
          status: fieldValueByName(name: "Status") { ... on ProjectV2ItemFieldSingleSelectValue { name } }
        } }
      }
    }
  }' | jq -r --argjson p "$PROJ" '.data.repository.issue.projectItems.nodes[] | select(.project.number==$p) | "\(.id)|\(.status.name // "")"' | head -1
}

if [ "$DESTINO" = "In Progress" ]; then
  EN_CURSO=0
  for m in $(gh issue list --repo "$OWNER/devops-PIF" --state open --assignee "@me" --limit 100 --json number --jq '.[].number'); do
    [ "$m" = "$N" ] && continue
    [ "$(item_y_status "$m" | cut -d'|' -f2)" = "In Progress" ] && EN_CURSO=$((EN_CURSO + 1))
  done
  if [ "$EN_CURSO" -ge "$WIP" ]; then
    echo "WIP excedido: ya tenés $EN_CURSO tareas en In Progress (límite $WIP). Terminá una antes de empezar otra."
    exit 1
  fi
fi

DATOS=$(item_y_status "$N")
ITEM="${DATOS%%|*}"
[ -n "$ITEM" ] || { echo "ERROR: el Issue #$N no está en el proyecto"; exit 1; }
PID=$(gh project view "$PROJ" --owner "$OWNER" --format json --jq .id)
FIELDS=$(gh project field-list "$PROJ" --owner "$OWNER" --format json)
FID=$(echo "$FIELDS" | jq -r '.fields[] | select(.name=="Status") | .id')
OID=$(echo "$FIELDS" | jq -r --arg o "$DESTINO" '.fields[] | select(.name=="Status") | .options[] | select(.name==$o) | .id')
[ -n "$OID" ] || { echo "ERROR: no existe la columna \"$DESTINO\""; exit 1; }
gh project item-edit --id "$ITEM" --project-id "$PID" --field-id "$FID" --single-select-option-id "$OID" >/dev/null
echo "#$N: ${DATOS#*|} -> $DESTINO"
