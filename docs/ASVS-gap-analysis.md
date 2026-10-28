# Análisis de Brechas OWASP ASVS v5.0.0 (post-TP18)

Código auditado: base heredada del TP18 (Notes App en `app/`, chart `helm/notes-app/`, pipeline `.github/workflows/defectdojo-ci.yml`).

Flujo aplicado: Código heredado TP18 → Auditoría vs ASVS v5.0.0 → Matriz de hallazgos → Priorización por riesgo → Issues en GitHub Projects v2.

## Matriz de hallazgos

| ID | Hallazgo | Evidencia | Ref. guía | ASVS 5.0.0 | Severidad | Prioridad | Historia / Issue |
|----|----------|-----------|-----------|------------|-----------|-----------|------------------|
| H-01 | El contenedor corre con un UID implícito, conserva binarios con setuid/setgid y la imagen base no está fijada por digest | `app/backend/Dockerfile` | V5.2.1 | V13 Configuration / V15 Secure Coding and Architecture | Alta | P1 | AS-02 / Issue #1 |
| H-02 | Los Deployments no definen `securityContext`: se permite escalar privilegios y el sistema de archivos raíz es escribible | `templates/backend.yaml`, `frontend.yaml`, `postgres.yaml` | V1.4.2 | V13 Configuration | Alta | P1 | AS-02 / Issue #2 |
| H-03 | El YAML renderizado solo se analiza con Trivy IaC; no hay Checkov ni kube-linter | Fase 2 de `defectdojo-ci.yml` | V1.1.3 | V13 Configuration | Media | P1 | US-01 / Issue #3 |
| H-04 | Ningún escaneo corta el pipeline: Trivy usa `exit-code: '0'`, Semgrep y Gitleaks terminan con `\|\| true`, Threagile tiene `continue-on-error` y ZAP corre con `-I` | Fase 2 de `defectdojo-ci.yml` | No aplica | Control de proceso (fuera del alcance directo de ASVS) | Alta | P1 | Issue Andon Cord |
| H-05 | Contraseña de producción en texto plano dentro del repositorio | `helm/values-prod.yaml` | No aplica | V13 Configuration (gestión de secretos) | Alta | P2 | Issue |
| H-06 | Credenciales por defecto `postgres/postgres` como valor de respaldo | `app/backend/entrypoint.sh` | No aplica | V13 Configuration | Media | P2 | Issue |
| H-07 | La Fase 4 publica la imagen con el tag mutable `latest` | Fase 4 de `defectdojo-ci.yml` | No aplica | V15 Secure Coding and Architecture | Media | P2 | Issue |
| H-08 | La imagen no tiene SBOM ni firma criptográfica | Pipeline completo | No aplica | V15 Secure Coding and Architecture (dependencias) | Media | P3 | SS-03 (pendiente de consulta) |
| H-09 | Semgrep y Threagile analizan una copia de la aplicación distinta de la que el pipeline compila y despliega | Fase 2 de `defectdojo-ci.yml` | No aplica | Control de proceso | Media | P2 | Resuelto en la reorganización de la estructura |
| H-10 | Los hallazgos de Trivy Container no se deduplican en DefectDojo porque el hash incluye el tag SHA de la imagen | DefectDojo, TP18 | No aplica | Control de proceso | Baja | P3 | Issue |

## Criterio de priorización

- P1: brechas explotables en runtime o que impiden detectar fallas en el pipeline. Se resuelven primero.
- P2: exposición de secretos y configuraciones inseguras con impacto acotado.
- P3: mejoras de trazabilidad y de la cadena de suministro.

## Desvíos respecto de la guía

### D1. Referencias ASVS de la guía

- Problema: los IDs de la guía (V5.2.1, V1.4.2, V1.1.3) no corresponden a ASVS 5.0.0. En la versión 5.0.0, V1 es Encoding and Sanitization y V5 es File Handling; la nomenclatura "V1 Architecture, Design and Threat Modeling" pertenece a ASVS 4.0.3.
- Justificación: la trazabilidad a un estándar requiere que la referencia exista en la versión declarada.
- Versión 2: mapear cada hallazgo al capítulo vigente de ASVS 5.0.0.
- Cambio realizado: la matriz conserva el ID de la guía en "Ref. guía" y agrega el capítulo real en "ASVS 5.0.0".
