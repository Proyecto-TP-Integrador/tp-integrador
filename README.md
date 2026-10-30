# Notes App — Proyecto Final Integrador DevSecOps (UNAHUR)

Portfolio de la materia Desarrollo, Seguridad y Operaciones: una aplicación de notas (Flask + PostgreSQL + Nginx) desplegada con Helm en Kubernetes, con un pipeline de CI/CD en 4 fases, controles de seguridad automatizados y gestión centralizada de vulnerabilidades en OWASP DefectDojo.

## Estructura

| Ruta | Contenido |
|------|-----------|
| `app/backend/` | API Flask, Dockerfile y tests |
| `app/frontend/` | Frontend estático servido por Nginx |
| `helm/notes-app/` | Chart de Helm de la aplicación |
| `helm/values-dev.yaml`, `helm/values-prod.yaml` | Valores por entorno |
| `threat-model/threagile.yaml` | Modelo de amenazas (Threagile) |
| `scripts/` | Importación a DefectDojo y automatización del tablero |
| `docs/` | Análisis de brechas OWASP ASVS v5.0.0 y documentación del proyecto |
| `.github/` | Workflows de CI/CD y plantilla de Issues |

## Pipeline de CI/CD

| Fase | Herramientas | Función |
|------|--------------|---------|
| 1. Build & Package | Hadolint, Docker Buildx | Valida el Dockerfile y compila la imagen inmutable del backend |
| 2. Auditorías | Checkov, kube-linter, OWASP ZAP, Threagile, Semgrep, Trivy, Gitleaks | IaC sobre el manifiesto renderizado (Render First), DAST, modelado de amenazas, SAST, SCA y secretos |
| 3. Vulnerability Management | OWASP DefectDojo (API v2) | Centraliza y deduplica los hallazgos (runner self-hosted) |
| 4. Release & Deploy | Docker Hub, Syft, Cosign, Helm | Publica la imagen por digest, genera el SBOM, la firma, verifica la firma y despliega en Kubernetes |

## Gobernanza

El trabajo se gestionó en el tablero de GitHub Projects v2 [PIF DevSecOps - Notes App](https://github.com/users/laudainotta/projects/1), con jerarquía Épica, Feature, Historia (US/AS/SS), Task y Pull Request. Los Issues, los Pull Requests y la trazabilidad de cada cambio están en el repositorio de desarrollo [laudainotta/devops-PIF](https://github.com/laudainotta/devops-PIF); los scripts de `scripts/` que operan sobre el tablero apuntan a ese repositorio.

## Integrantes y etapas

| Etapa | Kary Parra (karyparrauni) | Lautaro Dainotta (laudainotta) | Leonardo Encarnacao (leoencarnacao-droid) |
|-------|---------------------------|--------------------------------|-------------------------------------------|
| DEV | Aplicación base | Chart de Helm y modelo de amenazas | Pipeline base y análisis de brechas ASVS |
| SEC | Hadolint | Checkov, kube-linter y prueba AS-02 | Syft y Cosign |
| OPS | Dockerfile rootless | securityContext y Nginx sin root | Correcciones de Checkov, riesgos aceptados y mejora continua |

## Uso local

```bash
helm template mi-app helm/notes-app -f helm/values-prod.yaml > manifests-rendered-prod.yaml
DEFECTDOJO_URL="http://localhost:8080" ./scripts/verificar-defectdojo.sh
```

El token de DefectDojo se toma de `DEFECTDOJO_API_KEY` o de `~/.defectdojo-token` y nunca se versiona en el repositorio.
