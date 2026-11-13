# Acta de Retrospectiva de Fase — Iteración 4 (DevSecOps)

```text
================================================================================
ACTA DE RETROSPECTIVA DE FASE — ITERACIÓN 4 (DEVSECOPS)
================================================================================
Proyecto Integrador Final: NotesApp DevSecOps
Equipo / Célula: Proyecto-TP-Integrador | Fecha: 2026-11-13
Integrantes: Lautaro Dainotta | Karina Parra | Leonardo Encarnacao
             (cada integrante cubrió una parte de Dev, Sec y Ops)
Iteración: Iteración 4 (2026-11-09 al 2026-11-15) — PRs #8 a #23
--------------------------------------------------------------------------------

1. ¿Qué funcionó bien en el pipeline y en la coordinación?
   • Deduplicación en DefectDojo (TP18F): con reimport-scan y un Engagement
     fijo, cada herramienta tiene un único Test que se actualiza en cada
     ejecución. Un hallazgo corregido pasa a Mitigated en lugar de quedar
     duplicado en un Test nuevo.
   • Remediación medible de punta a punta: Checkov (NetworkPolicy, #13) y
     Kube-linter (límites de recursos, #21) tienen historia de usuario, PR y
     evidencia antes/después en la herramienta y en DefectDojo
     (Active → Mitigated).
   • Andon Cord efectivo: después del PR #15 el Security Gate frenó el
     despliegue por un hallazgo de Trivy IaC y una detección de Gitleaks; se
     corrigieron en el PR #16 antes de llegar al clúster.
   • Monitoreo de seguridad (TP12C): las 5 reglas pasaron de Pending a Firing
     con tráfico real y se recargan sin reiniciar Prometheus.
   • Render First, Validate Second (TP10B): el manifiesto renderizado se valida
     con helm lint, yamllint y un dry-run contra el API server antes de los
     escaneos de IaC.

2. ¿Qué cuellos de botella técnicos o de seguridad nos frenaron?
   • Alcance demasiado amplio (restricción principal de la iteración): se
     trabajó con cinco herramientas en paralelo. Por indicación docente el
     alcance se redujo a dos herramientas con una remediación cada una, lo que
     permitió documentar cada ciclo completo.
   • Duplicados heredados en DefectDojo: reimport-scan sólo cierra hallazgos
     dentro del mismo Test, por lo que los Engagements anteriores (uno por
     ejecución) tuvieron que eliminarse una vez.
   • Secreto en el historial: quitar la contraseña de los values no la borró
     del historial de Git y Gitleaks siguió detectándola hasta que se rotó.
   • Remediación sin trazabilidad: la corrección de Kube-linter (3bfb895) se
     integró sin Issue y sin centralizarse en DefectDojo; se documentó después
     (#21, PR #22).
   • Infraestructura local: cAdvisor no arrancaba en k3s por el montaje de
     /var/run (PR #19), y la simulación de caída de PostgreSQL provocó
     reinicios por liveness probe en lugar de errores de base de datos.

3. Análisis de Cultura Justa (Just Culture) & Doctrina de Dan Milstein
   • Ninguno de los problemas fue un descuido individual. Faltaban
     salvaguardas en el sistema:
       - el pipeline no enviaba los resultados de Kube-linter a DefectDojo, de
         modo que una corrección no dejaba evidencia centralizada;
       - el procedimiento para sacar un secreto del repositorio no incluía la
         rotación;
       - la importación creaba un Engagement por ejecución, sin un historial
         común con el que comparar.
   • Cada corrección se implementó como un control en el pipeline o en la
     configuración, no como una advertencia a una persona.

4. Compromisos de Mejora Kaizen (Acciones Concretas)
   • Hechos en esta iteración:
       - reimport-scan con deduplicación por Engagement e infraestructura del
         TP18 versionada en infra/ (PR #8).
       - Cabeceras de seguridad y CORS cerrado en la API (PR #12).
       - NetworkPolicy por componente y secretos como archivos (PR #15, #16).
       - Monitoreo y alertas de seguridad del TP12C (PR #18, #19).
       - Kube-linter centralizado en DefectDojo (PR #22) y matriz ASVS
         actualizada (PR #23).
   • Pendientes para la Iteración 5 (2026-11-16 al 2026-11-22):
       - Revisar RA-06 antes de su vencimiento (2026-12-03) y reconstruir la
         imagen si Debian publica los parches.
       - Importar a DefectDojo el escaneo Trivy del frontend, que hoy sólo
         actúa como Andon Cord.
       - Fijar la versión de la imagen del runner ARC.
       - Planificar SS-04 (Andon Cord en todas las auditorías de la Fase 2).
   • Registrar estos compromisos en el campo 'Retrospective Notes' de
     Projects v2.
================================================================================
```

## Teoría de Restricciones en esta iteración

| Paso de Goldratt | Aplicación |
|------------------|------------|
| 1. Identificar | La restricción fue el alcance: cinco herramientas en paralelo impedían cerrar y documentar cada remediación. |
| 2. Explotar | Se eligieron las dos herramientas con hallazgos reales y verificables en el chart: Checkov y Kube-linter. |
| 3. Subordinar | Cada remediación sigue el mismo flujo: Issue, PR con Peer Review, pipeline y evidencia en DefectDojo. |
| 4. Elevar | reimport-scan con un Engagement fijo, para que el antes y el después de cada hallazgo queden en el mismo Test. |
| 5. Prevenir la inercia | Con las remediaciones trazables, la restricción pasa a la cobertura: el Trivy del frontend todavía no se centraliza en DefectDojo. |
