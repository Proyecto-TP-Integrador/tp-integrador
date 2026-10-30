#!/usr/bin/env bash
# Mide los tiempos reales del pipeline de CI/CD para la Teoría de Restricciones (TOC).
# Uso: scripts/metricas-pipeline.sh [cantidad_de_ejecuciones]   (por defecto 6)
# Toma las últimas ejecuciones exitosas en main y muestra la salida en formato de tabla Markdown.
set -euo pipefail

REPO="Proyecto-TP-Integrador/devops-PIF"
WF="defectdojo-ci.yml"
CANT="${1:-6}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

gh api "repos/$REPO/actions/workflows/$WF/runs?branch=main&event=push&status=success&per_page=$CANT" \
  --jq '.workflow_runs[].id' > "$TMP/runs.txt"
[ -s "$TMP/runs.txt" ] || { echo "ERROR: no hay ejecuciones exitosas en main"; exit 1; }
while read -r id; do
  gh api "repos/$REPO/actions/runs/$id/jobs?per_page=50" --jq '.jobs' > "$TMP/jobs-$id.json"
done < "$TMP/runs.txt"
jq -s 'add' "$TMP"/jobs-*.json > "$TMP/jobs.json"

# Funciones comunes: conversión de fechas ISO 8601 (con o sin offset) y formato de duración
DEFS='
def ts: capture("^(?<b>[0-9-]+T[0-9:]+)(\\.[0-9]+)?(?<z>Z|(?<s>[+-])(?<h>[0-9]{2}):(?<m>[0-9]{2}))$")
  | ((.b + "Z") | fromdateiso8601)
    - (if .z == "Z" then 0 else ((if .s == "+" then 1 else -1 end) * ((.h | tonumber) * 3600 + (.m | tonumber) * 60)) end);
def dur(a; b): ((b | ts) - (a | ts));
def fmt: (. | floor) as $s | "\($s / 60 | floor)m \($s % 60)s";
def fase: (capture("^Fase (?<n>[0-9])") | .n) // "?";
'

echo "### Tiempos por ejecución (últimas $(wc -l < "$TMP/runs.txt") ejecuciones exitosas en main)"
echo
echo "| Commit | Fecha (UTC) | Fase 1 | Fase 2 | Fase 3 | Fase 4 | Lead time |"
echo "|--------|-------------|--------|--------|--------|--------|-----------|"
jq -r "$DEFS"'
  group_by(.run_id) | sort_by(.[0].created_at) | .[]
  | (map({key: (.name | fase), value: dur(.started_at; .completed_at)}) | from_entries) as $f
  | "| `\(.[0].head_sha[0:7])` | \(.[0].created_at[0:16] | sub("T"; " ")) | \($f["1"] // 0 | fmt) | \($f["2"] // 0 | fmt) | \($f["3"] // 0 | fmt) | \($f["4"] // 0 | fmt) | \(dur(map(.created_at) | min; map(.completed_at) | max) | fmt) |"
' "$TMP/jobs.json"

echo
echo "### Promedio por fase"
echo
echo "| Fase | Duración promedio | Espera promedio en cola | % del lead time |"
echo "|------|-------------------|-------------------------|-----------------|"
jq -r "$DEFS"'
  (group_by(.run_id) | map(dur(map(.created_at) | min; map(.completed_at) | max)) | add / length) as $lead
  | group_by(.name | fase) | .[]
  | (map(dur(.started_at; .completed_at)) | add / length) as $d
  | (map(dur(.created_at; .started_at)) | add / length) as $q
  | "| \(.[0].name) | \($d | fmt) | \($q | fmt) | \($d / $lead * 100 | floor)% |"
' "$TMP/jobs.json"
jq -r "$DEFS"'
  group_by(.run_id) | map(dur(map(.created_at) | min; map(.completed_at) | max)) | add / length
  | "| **Lead time total** | **\(fmt)** | | 100% |"
' "$TMP/jobs.json"

echo
echo "### Pasos más lentos de la Fase 2 (última ejecución)"
echo
echo "| Paso | Duración | % de la Fase 2 |"
echo "|------|----------|----------------|"
jq -r "$DEFS"'
  (map(.run_id) | max) as $ultimo
  | map(select(.run_id == $ultimo and (.name | startswith("Fase 2")))) | .[0]
  | dur(.started_at; .completed_at) as $total
  | [.steps[] | select(.started_at != null and .completed_at != null and (.name | startswith("Post ") | not))
      | {n: .name, d: dur(.started_at; .completed_at)}]
  | sort_by(-.d) | .[0:8] | .[]
  | "| \(.n) | \(.d | fmt) | \(.d / $total * 100 | floor)% |"
' "$TMP/jobs.json"
