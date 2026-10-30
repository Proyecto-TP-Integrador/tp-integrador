# Post-mortem PM-001: fallo del PR Check por dependencias de test

> Las mediciones corresponden a las ejecuciones del repositorio de desarrollo [laudainotta/devops-PIF](https://github.com/laudainotta/devops-PIF), donde se integró cada cambio por Pull Request.

Análisis con enfoque de Cultura Justa (blameless): se asume que cada decisión se tomó de la mejor manera posible con la información disponible, y la causa se busca en las salvaguardas del sistema que permitieron que el error avanzara.

## Resumen

| Campo | Valor |
|-------|-------|
| Fecha | 22/10/2026 (hora de Argentina, UTC-3) |
| Cambio involucrado | PR #12: reorganización de la estructura del repositorio |
| Síntoma | El job `Validar PR` falló a los 8 segundos con `pytest: command not found` (exit code 127) |
| Impacto | Ninguno en `main`: el cambio no se integró hasta corregir el error |
| Tiempo de detección | 8 segundos desde la apertura del PR |
| Tiempo de resolución | 3 minutos desde la detección |

## Línea de tiempo

| Hora | Evento |
|------|--------|
| 23:09 | Se abre el PR #12. El workflow `PR Check` instala `app/backend/requirements-dev.txt` y ejecuta los tests. |
| 23:09 | `Validar PR` falla: `pytest: command not found`. |
| 23:10 | Diagnóstico con `gh run view --log-failed`: el comando `pytest` no está instalado en el runner. |
| 23:11 | Se publica el commit `fix(tests): dependencias de test en requirements-dev.txt`. |
| 23:12 | `Validar PR` pasa en 10 segundos; las Fases 1 y 2 del pipeline también pasan. |
| 23:15 | Se integra el PR #12 en `main`. |
| 23:21 | El pipeline completo de 4 fases termina en verde sobre `main`. |

## Causa raíz

En la estructura anterior, las dependencias de test (`pytest` y `pytest-cov`) estaban declaradas en el `requirements.txt` de la copia de la aplicación donde vivían los tests, y `requirements-dev.txt` solo contenía `-r requirements.txt`. La dependencia de los tests era implícita: funcionaba porque ese archivo de producción las incluía.

La reorganización movió los tests y `requirements-dev.txt` junto al `requirements.txt` de la aplicación que se compila y despliega, que no incluye dependencias de test. La referencia `-r requirements.txt` pasó a apuntar a otro archivo y las dependencias de test dejaron de instalarse.

| Pregunta | Respuesta |
|----------|-----------|
| ¿Por qué falló el job? | `pytest` no estaba instalado en el runner. |
| ¿Por qué no estaba instalado? | `requirements-dev.txt` no declaraba las dependencias de test de forma explícita. |
| ¿Por qué no se detectó antes del PR? | La validación local de la reorganización revisaba la sintaxis YAML, la existencia de los archivos y el renderizado del chart, pero no ejecutaba los tests. |

## Qué funcionó

- El `PR Check` detectó el error en 8 segundos, antes de cualquier integración.
- El log del job identificó el problema sin ambigüedad, lo que permitió corregirlo en minutos.
- El procedimiento de esperar los checks en verde antes de integrar evitó que el error llegara a `main`. En ese momento la protección de la rama exigía Pull Request, pero todavía no exigía checks.

## Acciones

| ID | Acción | Estado |
|----|--------|--------|
| A1 | Declarar de forma explícita las dependencias de test en `app/backend/requirements-dev.txt`. | Hecho (PR #12) |
| A2 | Convertir `Validar PR`, Fase 1 y Fase 2 en checks obligatorios de la protección de `main`, para que el bloqueo no dependa del procedimiento manual. | Hecho (después del PR #13) |
| A3 | Incluir la instalación de `requirements-dev.txt` y la ejecución de `pytest` en la validación local de todo cambio que mueva archivos de la aplicación. | Propuesta |

## Observación adicional

Antes de integrar el PR #12 se detectó que DefectDojo estaba detenido. La Fase 3 hubiera fallado en `main`. Se propone agregar al inicio de la Fase 3 una verificación de disponibilidad de la API de DefectDojo con un mensaje de error explícito.

## Lección aprendida

Una dependencia que funciona por una coincidencia de la estructura de archivos es una dependencia no declarada. Las salvaguardas automáticas, y no el cuidado individual, son las que impiden que ese tipo de error llegue a producción.
