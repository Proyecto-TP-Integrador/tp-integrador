# Monitoreo y alertas de seguridad (TP12B y TP12C)

Stack del TP12 reutilizado (Prometheus, Grafana, Node Exporter, cAdvisor) más kube-state-metrics y las métricas del NGINX Ingress Controller. Todo corre en el namespace `devops-portfolio`.

| Archivo | Contenido |
|---------|-----------|
| `monitoring-k8s-manifests.yaml` | Prometheus, Grafana (dashboard con la fila *Sad Paths & Security Events*), Node Exporter, cAdvisor, kube-state-metrics e Ingress |
| `prometheus-alerts-security.yml` | Reglas de ciberseguridad del TP12C, cargadas con el ConfigMap `prometheus-rules` |
| `../scripts/generar-alertas-seguridad.sh` | Tráfico anómalo para verificar que las alertas pasen de *Pending* a *Firing* |

## Métricas

| Métrica | Origen | Uso |
|---------|--------|-----|
| `http_requests_total{method, endpoint, status}` | API Flask (`/metrics`) | Requests por ruta y código; ráfagas 4xx (Anexo B §5.2) |
| `http_request_duration_seconds` | API Flask | Latencia p95 (Anexo A, rol Ops) |
| `app_db_errors_total` | API Flask | Errores contra PostgreSQL (TP12C regla 4) |
| `nginx_ingress_controller_requests` | Ingress Controller | Escaneos y fuerza bruta (TP12C regla 1) |
| `kube_pod_container_status_restarts_total` | kube-state-metrics | Reinicios de pods (TP12C regla 2) |
| `node_*`, `container_*` | Node Exporter, cAdvisor | CPU, memoria y disco de nodos y contenedores |

## Instalación

```bash
# 1. Métricas del Ingress Controller
helm upgrade ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx --version 4.15.1 \
  --reuse-values --set controller.metrics.enabled=true --wait

# 2. Contraseña de Grafana (no se versiona)
kubectl -n devops-portfolio create secret generic grafana-admin \
  --from-literal=password="$(openssl rand -base64 18)"

# 3. Reglas del TP12C en el ConfigMap prometheus-rules (TP12C Paso 2)
kubectl create configmap prometheus-rules \
  --from-file=alerts.yml=monitoring/prometheus-alerts-security.yml \
  -n devops-portfolio --dry-run=client -o yaml | kubectl apply -f -

# 4. Stack de monitoreo
kubectl apply -f monitoring/monitoring-k8s-manifests.yaml
kubectl -n devops-portfolio rollout status deploy/prometheus --timeout=180s

# 5. Nombres locales
echo "127.0.0.1 grafana.local prometheus.local" | sudo tee -a /etc/hosts
```

Si después se modifican las reglas, se repite el paso 3 y, cuando Kubernetes actualiza el archivo montado (hasta un minuto), se recarga Prometheus sin reiniciarlo:

```bash
kubectl -n devops-portfolio exec deploy/prometheus -- wget -qO- --post-data='' http://localhost:9090/-/reload
```

Prometheus queda en `http://prometheus.local:18080` y Grafana en `http://grafana.local:18080` (usuario `admin`, contraseña en el Secret `grafana-admin`).

## Verificación

```bash
bash scripts/generar-alertas-seguridad.sh            # 3 minutos de tráfico anómalo
SIMULAR_DB=1 bash scripts/generar-alertas-seguridad.sh   # además, 90 s sin PostgreSQL (errores 503 de base de datos)
```

En **Status → Targets** de Prometheus, los jobs `kubernetes-pods`, `node-exporter`, `cadvisor`, `ingress-nginx` y `kube-state-metrics` deben estar en `UP`. En **Alerts**, las reglas pasan de *Inactive* a *Pending* y, al cumplirse el `for`, a *Firing*.
