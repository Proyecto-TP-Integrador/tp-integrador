#!/usr/bin/env bash
# Crea los Issues #1, #2 y #3 del PIF con el formato de la plantilla security_hardening.yml
set -euo pipefail

REPO="laudainotta/devops-PIF"
PROYECTO="PIF DevSecOps - Notes App"


crear() {
  if gh issue list --repo "$REPO" --state all --limit 100 | grep -qF "$1"; then echo "Ya existe, se omite: $1"; return 0; fi
  URL=$(gh issue create --repo "$REPO" --title "$1" --label "$2" --assignee "@me" --body "$3")
  echo "$URL"
}

read -r -d '' CUERPO1 <<'EOF' || true
### Descripción de la Brecha / Vulnerabilidad Registrada

El Dockerfile heredado del TP18 (`app/backend/Dockerfile`) ejecuta el proceso con un UID implícito asignado por `useradd`, conserva binarios con bits setuid/setgid activos y usa una imagen base sin fijar por digest. Hallazgo H-01 de `docs/ASVS-gap-analysis.md`.

### Referencia OWASP ASVS v5.0.0

V5.2.1 (guía) → ASVS 5.0.0 V13 Configuration / V15 Secure Coding and Architecture (ver desvío D1)

### Criterios de Aceptación (Formato Gherkin)

```gherkin
Scenario: Imagen rootless sin binarios con privilegios elevados
  Given el Dockerfile de app/backend con compilación multietapa
  When se construye la imagen y se ejecuta "id -u" dentro del contenedor
  Then el UID del proceso debe ser 10001
  And "find / -xdev -perm /6000 -type f" no debe devolver ningún archivo
  And Hadolint debe finalizar sin errores en el pipeline
```
EOF

read -r -d '' CUERPO2 <<'EOF' || true
### Descripción de la Brecha / Vulnerabilidad Registrada

Los Deployments del chart (`helm/notes-app/templates/`) no declaran `securityContext`: permiten la escalada de privilegios y el sistema de archivos raíz es escribible. Hallazgo H-02 de `docs/ASVS-gap-analysis.md`.

### Referencia OWASP ASVS v5.0.0

V1.4.2 (guía) → ASVS 5.0.0 V13 Configuration (ver desvío D1)

### Criterios de Aceptación (Formato Gherkin)

```gherkin
Scenario: Pods con contexto de seguridad restrictivo
  Given el chart devops-portfolio renderizado con "helm template"
  When se inspeccionan los Deployments backend, frontend y postgres
  Then cada Pod debe declarar runAsNonRoot: true
  And cada contenedor debe declarar allowPrivilegeEscalation: false y readOnlyRootFilesystem: true
  And cada contenedor debe descartar todas las capacidades con drop: ["ALL"]
```
EOF

read -r -d '' CUERPO3 <<'EOF' || true
### Descripción de la Brecha / Vulnerabilidad Registrada

El pipeline renderiza el chart con `helm template`, pero el YAML resultante solo se analiza con Trivy IaC. No se ejecutan Checkov ni kube-linter sobre el manifiesto plano. Hallazgo H-03 de `docs/ASVS-gap-analysis.md`.

### Referencia OWASP ASVS v5.0.0

V1.1.3 (guía) → ASVS 5.0.0 V13 Configuration (ver desvío D1)

### Criterios de Aceptación (Formato Gherkin)

```gherkin
Scenario: Análisis estático sobre el manifiesto renderizado
  Given el chart devops-portfolio con los valores de values-prod.yaml
  When el pipeline ejecuta "helm template" antes del análisis de IaC
  Then Checkov y kube-linter deben analizar el YAML plano generado
  And el pipeline debe detenerse si se detectan hallazgos de severidad Alta o Crítica
```
EOF

crear "[SEC-HARDENING]: Hardening de Runtime en Contenedores Docker (ASVS V5.2.1)" "security,docker,hardening,asvs-v5,devsecops" "$CUERPO1"
crear "[SEC-HARDENING]: Endurecimiento de Contextos de Seguridad en Kubernetes (ASVS V1.4.2)" "security,k8s,pod-security,asvs-v5,devsecops" "$CUERPO2"
crear "[SEC-HARDENING]: Implementación del Patrón Render First en Charts de Helm (ASVS V1.1.3)" "helm,iac,checkov,asvs-v5,devsecops" "$CUERPO3"

gh issue list --repo "$REPO" --state all --json number,title --jq '.[] | "#\(.number) \(.title)"'
