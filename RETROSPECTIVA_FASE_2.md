# Acta de Retrospectiva de Fase — Hito 2 (DevSecOps)

```text
================================================================================
ACTA DE RETROSPECTIVA DE FASE — HITO 2 (DEVSECOPS)
================================================================================
Proyecto Integrador Final: NotesApp DevSecOps
Equipo / Célula: Proyecto-TP-Integrador | Fecha: 2026-11-04
Integrantes: Lautaro Dainotta | Karina Parra | Leonardo Encarnacao
             (cada integrante cubrió una parte de Dev, Sec y Ops)
Iteración: Iteración 3 (2026-11-02 al 2026-11-08) — PRs #1 a #4
--------------------------------------------------------------------------------

1. ¿Qué funcionó bien en el pipeline y en la coordinación?
   • Andon Cord antes del clúster (Línea B): en el primer despliegue real
     (PR #3), Trivy detectó CVE HIGH con parche en la imagen del frontend y
     detuvo la Fase 4 antes de publicar o desplegar. La corrección (PR #4,
     apk upgrade y regreso al UID 101) se integró en unos 30 minutos.
   • Security Gate con excepciones trazables: el despliegue sólo avanza con
     0 hallazgos CRITICAL/HIGH abiertos en DefectDojo. Lo que no tiene parche
     se acepta de forma explícita y con vencimiento (RA-06 en DefectDojo,
     45 hallazgos, vence 2026-12-03; RA-07 y RA-08 en el modelo Threagile).
   • Despliegue inmutable: backend y frontend se despliegan por digest, el
     mismo que se firmó con Cosign y se verificó antes del helm upgrade.
   • Mínimo privilegio en el runner: el runner ARC dentro de k3d usa la
     ServiceAccount notes-deployer, limitada al namespace devops-portfolio;
     no puede crear namespaces ni leer los secretos de DefectDojo.
   • Gobernanza: protección de main con Peer Review obligatorio; cada PR se
     integró con la aprobación de otro integrante.

2. ¿Qué cuellos de botella técnicos o de seguridad nos frenaron?
   • Hallazgos que no reflejaban el estado real (restricción principal de la
     iteración): el gate mostraba HIGH que ya estaban resueltos.
       - DefectDojo descartaba al importar los estados mitigated y
         false-positive del risk_tracking de Threagile.
       - La deduplicación por título mezclaba riesgos distintos de Threagile.
       - Trivy no se deduplicaba entre ejecuciones porque el tag de la imagen
         cambiaba en cada commit (H-10).
   • Imagen del frontend inexistente: el chart apuntaba a una imagen que
     nunca se había publicado; el pipeline sólo construía el backend.
   • Infraestructura local: el pod de DefectDojo se reinició por falta de
     memoria (OOMKilled) con la configuración por defecto, y un nodo de k3d
     quedó con un certificado emitido para su IP anterior, lo que bloqueó
     kubectl exec y logs.
   • Guías de laboratorio desactualizadas: claves del chart de DefectDojo y
     versión de ARC que ya no existen obligaron a verificar contra la
     documentación vigente.

3. Análisis de Cultura Justa (Just Culture) & Doctrina de Dan Milstein
   • Ninguno de los problemas fue un descuido individual. Faltaban
     salvaguardas en el sistema:
       - la importación a DefectDojo no verificaba el estado resultante de
         cada hallazgo;
       - ningún control comprobaba que las imágenes referenciadas por el
         chart existieran, estuvieran escaneadas y firmadas;
       - el entorno local no tenía límites de recursos definidos para
         DefectDojo.
   • Cada corrección se implementó como un control automático en el pipeline
     o en la configuración, no como una advertencia a una persona.

4. Compromisos de Mejora Kaizen (Acciones Concretas)
   • Hechos en esta iteración:
       - Sincronizar por API los estados de Threagile después de importar
         (PR #2) y deduplicar Threagile por unique_id_from_tool.
       - Nombre fijo de imagen para el escaneo de Trivy (PR #1).
       - Construir, escanear, firmar y desplegar también el frontend (PR #3)
         y actualizar sus paquetes base al construir (PR #4).
       - Límites de memoria y procesos de uWSGI en los values de DefectDojo.
   • Pendientes para la Iteración 4 (2026-11-09 al 2026-11-15):
       - Importar el escaneo Trivy del frontend a DefectDojo para que el
         Security Gate cubra las dos imágenes.
       - Fijar la versión de la imagen del runner ARC (hoy usa latest).
       - Revisar RA-06 antes de su vencimiento (2026-12-03) y reconstruir la
         imagen si Debian publica los parches.
       - Planificar SS-04, SS-05 y SS-06 del Backlog; cerrar SS-07, resuelto
         en el PR #1.
   • Registrar estos compromisos en el campo 'Retrospective Notes' de
     Projects v2.
================================================================================
```

## Teoría de Restricciones en esta iteración

| Paso de Goldratt | Aplicación |
|------------------|------------|
| 1. Identificar | El Security Gate no podía confiar en DefectDojo: hallazgos resueltos seguían abiertos y riesgos distintos aparecían como duplicados. |
| 2. Explotar | Se analizaron los hallazgos por servicio y por identificador, y se confirmó en el código de DefectDojo por qué se perdían los estados. |
| 3. Subordinar | El despliegue quedó condicionado al gate: no se despliega mientras haya un CRITICAL/HIGH abierto sin aceptación registrada. |
| 4. Elevar | Sincronización de estados por API, deduplicación por identificador de la herramienta y aceptaciones de riesgo con vencimiento. |
| 5. Prevenir la inercia | Con el gate confiable, la restricción pasa a la cobertura: el escaneo del frontend todavía no se centraliza en DefectDojo. |
