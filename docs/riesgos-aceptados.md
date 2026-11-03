# Riesgos aceptados del análisis estático de IaC

Hallazgos de Checkov y kube-linter sobre el manifiesto renderizado que no se corrigen en esta versión. Cada uno queda excluido del quality gate con una justificación y un control compensatorio, y se revisa antes de cada entrega.

| ID | Regla | Recursos | Justificación | Control compensatorio |
|----|-------|----------|---------------|-----------------------|
| RA-01 | CKV_K8S_43: la imagen debe usar digest | backend, frontend, postgres | El manifiesto se analiza en la Fase 2, antes de que la imagen exista en el registro, por lo que todavía no tiene digest. El backend se publica por digest recién en la Fase 4. | En la Fase 4 la imagen del backend se publica por digest, se firma con Cosign y la firma se verifica antes del despliegue (SS-03). La imagen base está fijada por digest en el Dockerfile. |
| RA-02 | CKV_K8S_40: UID alto (mayor a 10000) | frontend (101), postgres (70) | Los UID vienen definidos por las imágenes oficiales nginx-unprivileged y postgres; cambiarlos exige reconstruir esas imágenes. | runAsNonRoot, readOnlyRootFilesystem, drop ALL y allowPrivilegeEscalation false (Issue #2). |
| RA-03 | CKV_K8S_35: secretos como archivos | backend, postgres | La aplicación lee las credenciales de variables de entorno; montarlas como archivos requiere cambiar el código. | Las credenciales viven en un Secret de Kubernetes y no en el repositorio de la imagen. |
| RA-04 | CKV2_K8S_6: Pods sin NetworkPolicy | backend, frontend, postgres | El laboratorio corre en un clúster local de un solo nodo; definir políticas de red queda fuera del alcance de esta entrega. | Services de tipo ClusterIP: PostgreSQL y el backend no se exponen fuera del clúster. |
| RA-05 | kube-linter no-anti-affinity | backend, frontend | El laboratorio usa un único nodo, donde la anti-afinidad entre réplicas no tiene efecto. | Réplicas múltiples y estrategia RollingUpdate con maxUnavailable 0. |

## Riesgos aceptados para el Security Gate

El Security Gate no despliega si hay hallazgos CRITICAL o HIGH abiertos en DefectDojo (Anexo A §7). Los siguientes se aceptan de forma temporal y quedan registrados en DefectDojo o en el modelo de amenazas, con vencimiento o revisión.

| ID | Hallazgo | Justificación | Control compensatorio | Registro |
|----|----------|---------------|-----------------------|----------|
| RA-06 | CVE HIGH de paquetes de Debian de la imagen base (util-linux, mount, login, ncurses, perl, systemd, sqlite) sin versión corregida publicada | No existe parche: Trivy informa el campo de versión corregida vacío. Cuando Debian lo publique, Trivy lo informará y el hallazgo volverá a bloquear el despliegue hasta reconstruir la imagen. | Contenedor sin root (UID 10001), sin binarios setuid, sistema de archivos de solo lectura y sin capabilities: los binarios afectados no se pueden usar para escalar privilegios. | Aceptación de riesgo en DefectDojo con vencimiento a 30 días |
| RA-07 | Threagile missing-authentication (ingress → backend) | La Notes App no tiene usuarios por diseño y no maneja datos personales; la autenticación queda fuera del alcance del PIF. | El Ingress solo se publica en el clúster local; la API no se expone a Internet. | risk_tracking PIF-TM-08 en `threat-model/threagile.yaml` |
