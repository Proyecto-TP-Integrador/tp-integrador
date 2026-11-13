# Riesgos aceptados del análisis estático de IaC

Hallazgos de Checkov y kube-linter sobre el manifiesto renderizado que no se corrigen en esta versión. Cada uno queda excluido del quality gate con una justificación y un control compensatorio, y se revisa antes de cada entrega.

| ID | Regla | Recursos | Justificación | Control compensatorio |
|----|-------|----------|---------------|-----------------------|
| RA-01 | CKV_K8S_43: la imagen debe usar digest | backend, frontend, postgres | El manifiesto se analiza en la Fase 2, antes de que la imagen exista en el registro, por lo que todavía no tiene digest. El backend se publica por digest recién en la Fase 4. | En la Fase 4 las imágenes del backend y del frontend se publican por digest y Helm despliega exactamente ese digest. La imagen base está fijada por digest en el Dockerfile. |
| RA-02 | CKV_K8S_40: UID alto (mayor a 10000) | frontend (101), postgres (70) | Los UID vienen definidos por las imágenes oficiales nginx-unprivileged y postgres; cambiarlos exige reconstruir esas imágenes. | runAsNonRoot, readOnlyRootFilesystem, drop ALL y allowPrivilegeEscalation false (Issue #2). |
| RA-05 | kube-linter no-anti-affinity | backend, frontend | Los tres nodos del clúster k3d de laboratorio son contenedores de la misma máquina virtual: repartir las réplicas entre nodos no protege ante la caída del host, que es la falla relevante en este entorno. | En values-prod.yaml, 3 réplicas de backend y frontend con RollingUpdate y maxUnavailable 0. El laboratorio despliega con values-dev.yaml (1 réplica). |

## Riesgos aceptados para el Security Gate

El Security Gate no despliega si hay hallazgos CRITICAL o HIGH abiertos en DefectDojo (Anexo A §7). Los siguientes se aceptan de forma temporal y quedan registrados en DefectDojo o en el modelo de amenazas, con vencimiento o revisión.

| ID | Hallazgo | Justificación | Control compensatorio | Registro |
|----|----------|---------------|-----------------------|----------|
| RA-06 | CVE HIGH de paquetes de Debian de la imagen base (util-linux, mount, login, ncurses, perl, systemd, sqlite) sin versión corregida publicada | No existe parche: Trivy informa el campo de versión corregida vacío. Cuando Debian lo publique, Trivy lo informará y el hallazgo volverá a bloquear el despliegue hasta reconstruir la imagen. | Contenedor sin root (UID 10001), sin binarios setuid, sistema de archivos de solo lectura y sin capabilities: los binarios afectados no se pueden usar para escalar privilegios. | Aceptación de riesgo en DefectDojo con vencimiento a 30 días |
| RA-07 | Threagile missing-authentication (ingress → backend) | La Notes App no tiene usuarios por diseño y no maneja datos personales; la autenticación queda fuera del alcance del PIF. | El Ingress solo se publica en el clúster local; la API no se expone a Internet. | risk_tracking PIF-TM-08 en `threat-model/threagile.yaml` |
| RA-08 | Threagile missing-hardening (volumen-postgres) | El aprovisionador local-path de k3d no cifra el volumen en reposo; cifrarlo exige otra clase de almacenamiento, fuera del alcance del laboratorio local. | PVC ReadWriteOnce montado sólo por PostgreSQL, fsGroup 70 y Service ClusterIP sin exposición fuera del clúster. | risk_tracking PIF-TM-11 en `threat-model/threagile.yaml` |

## Riesgos resueltos

Excepciones que dejaron de ser necesarias porque el hallazgo se corrigió. La regla vuelve a estar activa en el quality gate.

| ID | Regla | Resolución |
|----|-------|------------|
| RA-04 | CKV2_K8S_6: Pods sin NetworkPolicy | SS-15: el chart define una NetworkPolicy por componente. PostgreSQL solo acepta conexiones del backend en el puerto 5432; backend y frontend solo reciben tráfico del Ingress Controller, del smoke test del pipeline y, en el caso del backend, del frontend y de Prometheus. |
| RA-03 | CKV_K8S_35: secretos como variables de entorno | SS-16: la contraseña de PostgreSQL se monta como archivo de solo lectura desde el Secret (`/run/secrets/db/password`). El backend la lee con `DB_PASSWORD_FILE` y PostgreSQL con `POSTGRES_PASSWORD_FILE`. Además, la contraseña dejó de estar escrita en los values del chart: la genera Helm en la primera instalación y se conserva en el clúster. |
