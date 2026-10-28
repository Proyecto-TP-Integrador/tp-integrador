#!/usr/bin/env bash
# Crea la jerarquía ágil de 5 niveles del PIF (Épica > Feature > Historia > Task > PR)
# y completa los campos Tipo, Story Points y Status del tablero. Es idempotente.
set -euo pipefail

REPO="laudainotta/devops-PIF"
OWNER="laudainotta"
PROJ=1

numero_por_titulo() {
  gh issue list --repo "$REPO" --state all --limit 200 --json number,title \
    | jq -r --arg t "$1" '.[] | select(.title==$t) | .number' | head -1
}

crear() {
  local n url
  n=$(numero_por_titulo "$1")
  if [ -n "$n" ]; then echo "$n"; return 0; fi
  url=$(gh issue create --repo "$REPO" --title "$1" --label "$2" --assignee "@me" --body "$3")
  echo "${url##*/}"
}

vincular() {
  local hijo_id
  if gh api "repos/$REPO/issues/$1/sub_issues" --jq '.[].number' | grep -qx "$2"; then
    echo "  #$2 ya es sub-issue de #$1"
  else
    hijo_id=$(gh api "repos/$REPO/issues/$2" --jq .id)
    gh api -X POST "repos/$REPO/issues/$1/sub_issues" -F sub_issue_id="$hijo_id" --silent
    echo "  #$2 -> sub-issue de #$1"
  fi
}

read -r -d '' B_E1 <<'EOF' || true
**Nivel:** Iniciativa / Épica de Seguridad

**Macrodominio:** OWASP ASVS 5.0.0 V13 Configuration.

Agrupa las brechas de configuración insegura del runtime de contenedores, de los manifiestos de Kubernetes y del análisis de IaC: hallazgos H-01, H-02, H-03, H-05 y H-06 de `docs/ASVS-gap-analysis.md`.

**Ref. guía:** ASVS-V1 Architecture, Design and Threat Modeling (nomenclatura ASVS 4.0.3, ver desvío D1).
EOF

read -r -d '' B_E2 <<'EOF' || true
**Nivel:** Iniciativa / Épica de Seguridad

**Macrodominio:** OWASP ASVS 5.0.0 V15 Secure Coding and Architecture.

Agrupa las brechas de la cadena de suministro del artefacto de contenedor: hallazgos H-07 y H-08 de `docs/ASVS-gap-analysis.md`.
EOF

read -r -d '' B_F1 <<'EOF' || true
**Nivel:** Feature

Endurecer el runtime de la Notes App: imagen Docker sin privilegios (UID 10001, sin binarios setuid/setgid) y Pods de Kubernetes con `securityContext` restrictivo.
EOF

read -r -d '' B_F2 <<'EOF' || true
**Nivel:** Feature

Analizar el manifiesto YAML plano generado con `helm template` (patrón Render First) mediante Checkov y kube-linter, con quality gate bloqueante en el pipeline.
EOF

read -r -d '' B_F3 <<'EOF' || true
**Nivel:** Feature

Generar el SBOM de la imagen con Syft y firmarla con Cosign antes del despliegue. Implementación pendiente de consulta con la cátedra.
EOF

read -r -d '' B_US01 <<'EOF' || true
**ID:** US-01 | **Ponderación Fibonacci:** 3

**Justificación de Puntuación:** Complejidad baja-moderada. Requiere estructurar la plantilla base de Helm y parametrizar los valores de despliegue. Riesgo operativo acotado y baja fricción en la ejecución de pruebas.

**Título:** Configuración de Despliegue Declarativo en Kubernetes

**Descripción:** *Como* Operador de Infraestructura, *Quiero* disponer de manifestos de Kubernetes y Charts de Helm estandarizados, *Para* asegurar la repetibilidad y la consistencia en el despliegue del entorno operativo.

**Criterios de Aceptación (Gherkin):**

```gherkin
Scenario: Renderizado correcto de manifestos de Helm
  Given un Chart de Helm configurado con valores por defecto en values.yaml
  When ejecuto el comando "helm template release-name ./chart"
  Then la salida debe ser un manifiesto YAML plano con sintaxis Kubernetes 100% válida.
```
EOF

read -r -d '' B_AS02 <<'EOF' || true
**ID:** AS-02 | **Ponderación Fibonacci:** 5

**Justificación de Puntuación:** Complejidad media-alta. Implica modelar un vector de ataque de escalada de privilegios en el contenedor, exigiendo la reconfiguración del runtime de Docker, la eliminación de binarios con bits setuid/setgid y la reescritura de permisos en el sistema de archivos.

**Título:** Inyección de Cargas Maliciosas y Escalado de Privilegios en el Contenedor

**Descripción:** *Como* un Atacante no autorizado, *Quiero* explotar vulnerabilidades de elevación de privilegios en el tiempo de ejecución del contenedor, *Para* tomar el control del nodo subyacente del clúster a través del usuario root del proceso.

**Criterios de Aceptación (Gherkin):**

```gherkin
Scenario: Bloqueo de escalada de privilegios y escritura en root
  Given un contenedor en ejecución vulnerado con un shell efímero
  When el atacante intente ejecutar "chmod +s" o escribir en un directorio raíz (/usr, /sbin)
  Then el sistema operativo debe denegar la acción con error "Read-only file system" o "Operation not permitted".
```
EOF

read -r -d '' B_SS03 <<'EOF' || true
**ID:** SS-03 | **Ponderación Fibonacci:** 8

**Justificación de Puntuación:** Alta complejidad técnica e incertidumbre de integración. Exige integrar dos herramientas criptográficas (Syft para la generación de SBOM en formato SPDX/CDX y Cosign para la firma de imágenes), gestionar llaves criptográficas/modos *keyless* mediante OIDC, e integrar el Quality Gate en el pipeline de CI/CD.

**Título:** Inmutabilidad y Firma Criptográfica de Artefactos de Contenedor

**Descripción:** *Como* Oficial de Ciberseguridad, *Quiero* garantizar la trazabilidad de los contenedores construidos en el pipeline, *Para* impedir el despliegue de imágenes no verificadas o alteradas por terceros.

**Criterios de Aceptación (Gherkin):**

```gherkin
Scenario: Firma y verificación del artefacto de contenedor
  Given una imagen de contenedor compilada e inspeccionada en el pipeline
  When la herramienta Syft genere el catálogo SBOM y Cosign aplique la firma digital
  Then el registro de la firma debe ser verificado públicamente antes de autorizar el despliegue a producción.
```
EOF

echo "== Creando Issues de la jerarquía =="
E1=$(crear "[EPIC] ASVS V13 Configuration: Configuración Segura de Runtime e IaC" "epic,asvs-v5,security" "$B_E1")
E2=$(crear "[EPIC] ASVS V15 Secure Coding and Architecture: Cadena de Suministro" "epic,asvs-v5,security" "$B_E2")
F1=$(crear "[FEATURE] Hardening de Runtime en Contenedores Docker y Kubernetes" "feature,hardening" "$B_F1")
F2=$(crear "[FEATURE] Análisis Estático de IaC con Render First" "feature,iac" "$B_F2")
F3=$(crear "[FEATURE] Generación y Firma Digital de SBOM en Pipeline" "feature,security" "$B_F3")
US01=$(crear "[US-01] Configuración de Despliegue Declarativo en Kubernetes" "user-story,helm" "$B_US01")
AS02=$(crear "[AS-02] Inyección de Cargas Maliciosas y Escalado de Privilegios en el Contenedor" "abuse-story,security" "$B_AS02")
SS03=$(crear "[SS-03] Inmutabilidad y Firma Criptográfica de Artefactos de Contenedor" "security-story,security" "$B_SS03")
echo "E1=#$E1 E2=#$E2 F1=#$F1 F2=#$F2 F3=#$F3 US-01=#$US01 AS-02=#$AS02 SS-03=#$SS03"

echo "== Vinculando sub-issues =="
vincular "$E1" "$F1"; vincular "$E1" "$F2"; vincular "$E2" "$F3"
vincular "$F1" "$AS02"; vincular "$F2" "$US01"; vincular "$F3" "$SS03"
vincular "$AS02" 1; vincular "$AS02" 2; vincular "$US01" 3

echo "== Completando campos del tablero =="
PID=$(gh project view "$PROJ" --owner "$OWNER" --format json --jq .id)
FIELDS=$(gh project field-list "$PROJ" --owner "$OWNER" --format json)
campo_id()  { echo "$FIELDS" | jq -r --arg n "$1" '.fields[] | select(.name==$n) | .id'; }
opcion_id() { echo "$FIELDS" | jq -r --arg n "$1" --arg o "$2" '.fields[] | select(.name==$n) | .options[] | select(.name==$o) | .id'; }
item_id() {
  gh api graphql -F n="$1" -f query='
  query($n: Int!) {
    repository(owner: "laudainotta", name: "devops-PIF") {
      issue(number: $n) {
        projectItems(first: 5) { nodes { id project { number } } }
      }
    }
  }' | jq -r --argjson p "$PROJ" '.data.repository.issue.projectItems.nodes[] | select(.project.number==$p) | .id' | head -1
}


asignar() {
  local it
  it=$(item_id "$1")
  gh project item-edit --id "$it" --project-id "$PID" --field-id "$(campo_id Tipo)" --single-select-option-id "$(opcion_id Tipo "$2")" >/dev/null
  if [ "$3" != "-" ]; then
    gh project item-edit --id "$it" --project-id "$PID" --field-id "$(campo_id 'Story Points')" --number "$3" >/dev/null
  fi
  gh project item-edit --id "$it" --project-id "$PID" --field-id "$(campo_id Status)" --single-select-option-id "$(opcion_id Status "$4")" >/dev/null
  echo "  #$1 | Tipo: $2 | SP: $3 | Status: $4"
}

asignar "$E1"   "Épica"          "-" "Backlog"
asignar "$E2"   "Épica"          "-" "Backlog"
asignar "$F1"   "Feature"        "-" "Backlog"
asignar "$F2"   "Feature"        "-" "Backlog"
asignar "$F3"   "Feature"        "-" "Backlog"
asignar "$US01" "User Story"     "3" "Ready for Dev"
asignar "$AS02" "Abuse Story"    "5" "Ready for Dev"
asignar "$SS03" "Security Story" "8" "Backlog"
asignar 1       "Task"           "-" "Ready for Dev"
asignar 2       "Task"           "-" "Ready for Dev"
asignar 3       "Task"           "-" "Ready for Dev"

echo "== Listo =="
