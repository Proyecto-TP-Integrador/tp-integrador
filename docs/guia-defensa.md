# Guía de la defensa oral (18/11/2026)

Cronograma de la guía del PIF (§7.1) y del Anexo A (§12), con lo que se muestra en cada bloque y quién lo presenta. Las respuestas de §7.2 y del Anexo A §12 están adaptadas a lo que este proyecto implementó.

## Alcance presentado

Dos herramientas del Top 5, con un hallazgo real y una remediación cada una:

| Herramienta | Hallazgo | Historia | Remediación | DefectDojo |
|-------------|----------|----------|-------------|------------|
| Checkov | CKV2_K8S_6: Pods sin NetworkPolicy (CWE-200) | #13 | PR #15 | Active → Mitigated |
| Kube-linter | `unset-cpu/memory-requirements`: contenedor sin límites (CWE-770) | #21 | 3bfb895 + PR #22 | Active → Mitigated |

Evidencia antes/después de cada una en los Issues y en las capturas del informe.

## Preparación (antes de entrar)

```bash
kubectl get nodes                                         # clúster k3d arriba
kubectl -n defectdojo get pods                            # DefectDojo y Celery en Running
kubectl -n actions-runner-system get pods                 # runner ARC esperando trabajos
kubectl -n devops-portfolio get pods                      # app y monitoreo en Running
SOLO_VERIFICAR=1 bash scripts/configurar-dedup-defectdojo.sh
```

Pestañas abiertas: tablero de Projects, Issue #13, PR #15, Issue #21, PR #22, Actions, DefectDojo (Test "Checkov IaC" y "KubeLinter IaC"), Prometheus Alerts, Grafana. Contraseñas de DefectDojo y Grafana ya ingresadas: no se muestran en el proyector.

## Bloque 1 — Arquitectura e Iceberg (00:00 a 05:00)

- Topología: GitHub Actions (Fases 1, 2 y la parte de Fase 4 que publica la imagen) en runners de GitHub; Fase 3 y despliegue en el runner ARC dentro de k3d; DefectDojo, Notes App y monitoreo en namespaces separados del mismo clúster.
- Pipeline de 4 fases: Build → Auditorías → DefectDojo → Security Gate y despliegue con Helm.
- Iceberg: lo visible es la app; lo sumergido es Render First, el Andon Cord, la deduplicación, la aceptación de riesgos con vencimiento y el mínimo privilegio del runner.

## Bloque 2 — Demo en vivo (05:00 a 15:00)

1. **Tablero** (Anexo A §12, 0 a 3): columnas, campos `Story Points`, `Iteration` y `Retrospective Notes`, etiquetas por herramienta y CWE.
2. **Trazabilidad** (3 a 7): Issue #13 → PR #15 (`closes #13`, Peer Review, checks en verde) → ejecución en Actions.
3. **Andon Cord en vivo**: un cambio que reintroduce el hallazgo de Kube-linter y el pipeline lo frena en la Fase 2.

   ```bash
   git switch main && git pull -q && git switch -c demo/andon-cord
   nano helm/notes-app/templates/backend.yaml   # borrar el bloque resources: del initContainer wait-for-db
   git commit -qam "demo: initContainer sin límites" && git push -q -u origin demo/andon-cord
   gh pr create --base main --title "demo: Andon Cord" --body "Demostración, no se mergea."
   gh pr checks --watch                          # Fase 2 falla en "Andon Cord: kube-linter"
   ```

   Al terminar: `gh pr close --delete-branch` y `git switch main && git branch -D demo/andon-cord`.
4. **DefectDojo** (7 a 12): Engagement "CI/CD Automated Security Audits" con un Test por herramienta; Test "KubeLinter IaC" con 2 reimports y los 4 hallazgos en Mitigated; System Settings con deduplicación activa.
5. **Monitoreo** (si sobra tiempo): `bash scripts/generar-alertas-seguridad.sh` y las alertas pasando a Pending en Prometheus.

## Bloque 3 — Interrogatorio por rol (15:00 a 25:00)

### Guía del PIF §7.2

**Dev — ¿Cómo garantiza que el escaneo dinámico no contamine la base de datos de producción?**

El escaneo dinámico del proyecto es OWASP ZAP, que reemplazó a Schemathesis. Corre en la Fase 2 sobre un entorno efímero: en el runner de GitHub se levanta una red Docker propia con un PostgreSQL desechable y el backend construido en la Fase 1 con el mismo SHA del commit, en modo de solo lectura y sin capabilities. Al terminar el job, la máquina del runner se destruye con todo su estado. ZAP nunca llega al clúster: la base real está en k3d y, además, la NetworkPolicy `postgres-solo-backend` solo admite conexiones del backend.

**Sec — Si hay una vulnerabilidad en una librería de base sin parche oficial, ¿cómo la gestionan sin romper el Andon Cord?**

Es el caso de RA-06: CVE de paquetes de Debian en la imagen del backend sin parche publicado. Se registró una aceptación de riesgo en DefectDojo con justificación y vencimiento el 03/12/2026 (`scripts/aceptar-riesgo-ra06.sh`) y un Issue (#20) para revisarla antes de esa fecha. El Security Gate excluye solo los hallazgos con `risk_accepted=true`, así que cualquier HIGH o CRITICAL nuevo sigue cortando el despliegue. Los controles compensatorios están en el runtime: usuario sin privilegios, sistema de archivos de solo lectura, sin capabilities y NetworkPolicy. Lo que sí tenía parche se corrigió reconstruyendo la imagen con `apt-get upgrade` (PR #9).

**Ops — ¿Por qué es obligatorio Render First antes de Checkov?**

Checkov y Kube-linter no entienden las plantillas Go de Helm: sobre el chart crudo omiten bloques condicionales o fallan al parsear. El pipeline ejecuta `helm template` con los values de producción y genera `manifests-rendered-prod.yaml`, el mismo YAML que aplicaría Kubernetes. Sobre ese archivo corren helm lint, yamllint, Checkov y Kube-linter, y en la Fase 4 un `kubectl apply --dry-run=server` contra el API server (TP10B). Por ejemplo, el hallazgo del initContainer sin límites (H-15) solo aparece en el manifiesto renderizado.

### Anexo A §12

**Dev — ¿Por qué no validar con Regex contra inyección SQL?**

Una lista negra con Regex se evade con codificaciones alternativas. La Notes App usa consultas parametrizadas de psycopg2: el driver envía el comando y los datos por separado, y la entrada nunca se interpreta como SQL. Semgrep revisa en cada PR que no haya consultas armadas por concatenación.

**Sec — ¿Cómo evitan que los reportes salgan a Internet al enviarlos a DefectDojo?**

La Fase 3 y el despliegue corren en un runner self-hosted (ARC) dentro del clúster k3d. El runner abre una conexión saliente HTTPS a GitHub para pedir trabajos y no expone puertos entrantes. Los reportes viajan como artefactos del pipeline y la importación a la API v2 de DefectDojo se hace desde dentro del clúster. Además, el runner usa la ServiceAccount `notes-deployer`, limitada al namespace de la aplicación.

**Ops — ¿Cómo resolvieron los falsos positivos de Checkov sobre el chart?**

Con Render First (ver la respuesta de Ops de §7.2). Los hallazgos reales que no se corrigen quedan como excepciones justificadas en `.checkov.yaml` y `.kube-linter.yaml`, documentadas en `docs/riesgos-aceptados.md` con control compensatorio. En esta iteración, dos de esas excepciones (RA-03 y RA-04) se corrigieron y salieron de la lista.

## Bloque 4 — Devolución (25:00 a 30:00)

Tomar nota de las observaciones del tribunal para la retrospectiva de la Iteración 5.
