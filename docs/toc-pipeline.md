# Teoría de Restricciones aplicada al pipeline de CI/CD

> Las mediciones corresponden a las ejecuciones del repositorio de desarrollo [laudainotta/devops-PIF](https://github.com/laudainotta/devops-PIF), donde se integró cada cambio por Pull Request.

Aplicación de los 5 Pasos de Focalización de Goldratt sobre el pipeline `defectdojo-ci.yml`. Los tiempos provienen de las ejecuciones exitosas en `main` y se obtienen con `scripts/metricas-pipeline.sh`.

## Métricas del sistema

### Tiempos por ejecución

| Commit | Cambio incorporado | Fase 1 | Fase 2 | Fase 3 | Fase 4 | Lead time |
|--------|--------------------|--------|--------|--------|--------|-----------|
| `8dbbe3b` | Reorganización de la estructura del repositorio | 0m 33s | 2m 32s | 0m 25s | 0m 28s | 4m 6s |
| `8418100` | Issue #1: Dockerfile rootless y Hadolint | 0m 22s | 1m 59s | 0m 16s | 0m 28s | 3m 14s |
| `e0ede1b` | Issue #2: securityContext y prueba AS-02 | 0m 22s | 2m 6s | 0m 16s | 0m 28s | 3m 21s |
| `8e68a0f` | Issue #3: Render First con Checkov y kube-linter | 0m 26s | 2m 46s | 0m 15s | 0m 26s | 4m 2s |
| `ac06b85` | Task #17: SBOM con Syft y firma con Cosign | 0m 24s | 3m 1s | 0m 14s | 0m 43s | 4m 29s |

### Promedio por fase

| Fase | Duración promedio | Espera promedio en cola | Porcentaje del lead time |
|------|-------------------|-------------------------|--------------------------|
| Fase 1: Build & Package | 0m 25s | 0m 1s | 11% |
| Fase 2: Auditorías | 2m 28s | 0m 2s | 64% |
| Fase 3: Centralización en DefectDojo | 0m 17s | 0m 2s | 7% |
| Fase 4: Release & Deploy | 0m 30s | 0m 2s | 13% |
| Lead time total | 3m 50s | | 100% |

### Pasos más lentos de la Fase 2 (última ejecución, 3m 1s)

| Paso | Duración | Porcentaje de la Fase 2 |
|------|----------|-------------------------|
| OWASP ZAP Baseline | 0m 55s | 30% |
| Checkov sobre el manifiesto renderizado | 0m 27s | 14% |
| Semgrep SAST | 0m 19s | 10% |
| Trivy Container Scan | 0m 16s | 8% |
| Trivy SCA | 0m 14s | 7% |
| Levantar la Notes App efímera para DAST | 0m 11s | 6% |
| Trivy IaC | 0m 9s | 4% |

## Paso 1: Identificar la restricción

La restricción del sistema es la Fase 2 (Auditorías): concentra el 64% del lead time promedio y es la fase que más creció, de 1m 59s a 3m 1s, a medida que se incorporaron controles de seguridad.

Dentro de la Fase 2, el paso de mayor latencia es OWASP ZAP (30% de la fase), seguido por Checkov (14%) y Semgrep (10%).

La espera en cola de todas las fases es de 1 a 2 segundos, incluida la Fase 3, que corre en el runner self-hosted. La restricción está en el tiempo de procesamiento de las herramientas, no en la disponibilidad de runners.

## Paso 2: Explotar la restricción

Optimizaciones posibles sin agregar infraestructura (propuestas, no aplicadas en esta entrega):

- Checkov y Semgrep se instalan desde cero en cada ejecución (`pipx run` y `pip install`). Guardar esas dependencias en la caché de GitHub Actions evita repetir la descarga.
- ZAP corre en modo baseline contra un único endpoint de la API. Se puede acotar el tiempo máximo del spider con la opción `-m` sin perder cobertura, porque la aplicación expone pocas rutas.

## Paso 3: Subordinar todo lo demás a la restricción

El orden de los controles ya está subordinado a la Fase 2:

- Hadolint corre en la Fase 1, antes de compilar. Un Dockerfile inseguro detiene el pipeline antes de consumir los 2 a 3 minutos de la Fase 2.
- Dentro de la Fase 2, Checkov y kube-linter (análisis estático, segundos) corren antes que ZAP (análisis dinámico, casi un minuto). Si el manifiesto falla, el pipeline se detiene sin ejecutar el escaneo más costoso.

Como regla de subordinación, ningún control nuevo se agrega a la Fase 2 sin medir antes su impacto en el lead time con `scripts/metricas-pipeline.sh`.

## Paso 4: Elevar la restricción

Si la Fase 2 sigue siendo la restricción después de explotarla, se eleva su capacidad dividiéndola en tres jobs paralelos, que solo dependen de la Fase 1:

| Job paralelo | Herramientas |
|--------------|--------------|
| IaC | Checkov, kube-linter, Trivy IaC |
| Código y dependencias | Semgrep, Trivy Container, Trivy SCA, Gitleaks |
| DAST y amenazas | Notes App efímera, OWASP ZAP, Threagile |

La duración de la Fase 2 pasaría a ser la del job más lento (DAST, alrededor de 1m 6s más el tiempo de preparación del job) en lugar de la suma de todos los pasos. GitHub Actions no cobra los runners alojados en repositorios públicos, por lo que la elevación no tiene costo de infraestructura. La división en jobs paralelos queda propuesta y no se aplica en esta entrega.

## Paso 5: Repetir el proceso

Con la Fase 2 paralelizada, la siguiente restricción candidata es la Fase 4, que pasó de 0m 28s a 0m 43s al incorporar la generación del SBOM y la firma de la imagen. La medición se repite con `scripts/metricas-pipeline.sh` después de cada cambio en el pipeline, como parte de la mejora continua (Kaizen).

## Conclusión

Cada control de seguridad incorporado aumentó el lead time: entre el commit `8418100` y el `ac06b85` el pipeline pasó de 3m 14s a 4m 29s (39% más). El aumento se acepta porque cada control bloquea una clase concreta de defecto antes del despliegue, y los controles más rápidos se ejecutan primero para detener el pipeline lo antes posible.
