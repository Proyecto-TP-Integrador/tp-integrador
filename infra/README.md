# Infraestructura de la fábrica DevSecOps en k3d (TP18B, TP18D y TP18E)

DefectDojo (TP18) dejó de correr en Docker Compose y se integró al mismo clúster k3d que la Notes App. El runner de GitHub Actions también corre dentro del clúster, así que los reportes viajan del runner a DefectDojo por la red privada de Kubernetes y nunca salen a Internet (TP18E, Caso A).

```text
 GitHub (nube)                        Clúster k3d notes-cluster
 ─────────────                        ──────────────────────────────────────────────────────
 Fases 1, 2 y Release      ──jobs──▶  actions-runner-system   runner ARC efímero (label pif)
 en ubuntu-latest                       │  ServiceAccount notes-deployer (RBAC mínimo)
                                        ├─ Fase 3 ──reimport-scan──▶ defectdojo  (Helm)
                                        │    http://defectdojo-django.defectdojo.svc
                                        └─ Fase 4 ──Security Gate + helm upgrade──▶ devops-portfolio
                                                                                     Notes App + monitoreo
```

| Archivo | TP | Contenido |
|---------|----|-----------|
| `defectdojo/values-defectdojo.yaml` | TP18B, TP18E, TP18F | DefectDojo con el chart oficial: Ingress con timeouts de 600 s y 50 MB, PostgreSQL y `/app/media` persistentes, deduplicación de Threagile |
| `arc/rbac-deployer.yaml` | TP18D | ServiceAccount del runner con permisos solo sobre `devops-portfolio` |
| `arc/runner-deployment.yaml` | TP18D | Runner efímero de ARC v0.27.6 registrado en este repositorio |

## Orden de instalación

```bash
# 1. DefectDojo (TP18B)
helm repo add defectdojo https://charts.defectdojo.com && helm repo update
helm upgrade --install defectdojo defectdojo/defectdojo -n defectdojo --create-namespace \
  --version 1.9.65 -f infra/defectdojo/values-defectdojo.yaml

# 2. ARC y el runner (TP18D); requiere cert-manager y el Secret controller-manager
kubectl apply --server-side -f https://github.com/actions/actions-runner-controller/releases/download/v0.27.6/actions-runner-controller.yaml
kubectl apply -f infra/arc/rbac-deployer.yaml
kubectl apply -f infra/arc/runner-deployment.yaml

# 3. Deduplicación en DefectDojo (TP18F)
bash scripts/configurar-dedup-defectdojo.sh
```

## Protocolo de verificación (TP18E §5)

```bash
# Checkpoint 1: el chart y los valores son válidos
helm template defectdojo defectdojo/defectdojo --version 1.9.65 -f infra/defectdojo/values-defectdojo.yaml > /dev/null && echo "render OK"

# Checkpoint 2: ingesta E2E por la API v2 (HTTP 200 con el token del pipeline)
curl -s -o /dev/null -w "%{http_code}\n" -H "Authorization: Token $(cat ~/.defectdojo-k8s-token)" \
  http://defectdojo.local:18080/api/v2/products/

# Checkpoint 3: resiliencia; la API Key y los hallazgos sobreviven al reinicio
kubectl -n defectdojo rollout restart deployment/defectdojo-django
kubectl -n defectdojo rollout status deployment/defectdojo-django --timeout=300s

# Checkpoint 4: el runner resuelve DefectDojo por el DNS privado del clúster
POD=$(kubectl -n actions-runner-system get pod -l runner-deployment-name=notesapp-runnerdeploy -o name | head -1)
kubectl -n actions-runner-system exec "$POD" -c runner -- getent hosts defectdojo-django.defectdojo.svc.cluster.local
```

Las contraseñas de DefectDojo las genera el chart y quedan en Secrets del namespace `defectdojo`; ninguna se versiona en el repositorio. El secreto `DEFECTDOJO_URL` del repositorio apunta al nombre interno del clúster.
