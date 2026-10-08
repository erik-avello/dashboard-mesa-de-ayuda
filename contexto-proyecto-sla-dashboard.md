# Contexto del proyecto: Dashboard de monitoreo de SLA/incidentes IT

## Objetivo
Proyecto de portafolio de GitHub (Python + SQL + Node.js + React) que resuelve un problema real de operaciones IT: monitoreo de cumplimiento de SLA sobre tickets de Jira, inspirado en la experiencia real del autor en Agrosuper/Softtek.

## Decisiones tomadas

1. **Idea elegida**: entre 3 propuestas (monitoreo de SLA, auditoría de accesos IT, motor de recomendación Uber), se eligió **monitoreo de SLA e incidentes IT**.

2. **Fuente de datos**: se descartó tanto el correo de suscripción JQL (limitado a 200 de ~3047 tickets) como la API REST directa. **Se confirmó y eligió el export nativo de Jira Cloud a CSV** (botón "Exportar" dentro del filtro → "CSV: todos los campos" / "CSV: filtrar campos"), que trae el universo completo de resultados (hasta 10.000 issues, muy por encima de los ~3000 tickets del filtro).

3. **JQL base del filtro real**: `resolution = Unresolved ORDER BY created ASC`

4. **Columnas confirmadas del CSV exportado**:
   `Tipo de Incidencia, Clave de incidencia, ID de la incidencia, Resumen, Persona asignada, ID de la persona asignada, Informador, ID del informador, Prioridad, Estado, Resolución, Creada, Actualizada, Fecha de vencimiento`

   Nota: las fechas vienen como texto tipo `06 abr 2026, 0:36` (formato español, requiere parseo de mes abreviado).

## Arquitectura acordada

```
CSV exportado desde Jira
        ↓
Script Python (pandas): lectura + limpieza + normalización
        ↓
Upsert en PostgreSQL por id_incidencia (clave estable)
        ↓
Diff histórico: si el estado cambió respecto a la carga anterior,
se inserta una fila en historial_estados con la transición
        ↓
Vistas SQL: cumplimiento de SLA, backlog por prioridad, tendencia
        ↓
API Node.js (Express) que expone esas vistas
        ↓
Dashboard React (Recharts) con KPIs y alertas de breach
```

## Por qué el diseño es así
- Cada export CSV es una "fotografía" (snapshot) completa del filtro en un momento dado.
- Como no hay historial nativo de cambios de estado en un solo CSV, el propio pipeline construye ese historial comparando cada nueva carga contra el estado guardado en base de datos.
- Esto permite calcular tiempo real en cada estado (para SLA), no solo un snapshot estático.

## Próximos pasos (en orden)
1. ✅ Esquema SQL completo (tickets, historial_estados, reglas de SLA, vistas de KPIs)
2. ⏳ Script de carga en Python paso a paso (lectura CSV → limpieza → upsert → diff histórico)
3. ⏳ Backend Node/Express que expone las vistas SQL como API REST
4. ⏳ Frontend React con dashboard de KPIs y alertas

## Contexto del autor (para retomar tono/nivel técnico)
- Erik Avello Muñoz, profesional de operaciones IT en Agrosuper (Chile), en transición a roles junior de Data/BI Analyst.
- Ya construyó un dashboard ejecutivo real en Power BI para Agrosuper/Softtek alimentado por Jira (con restricciones de solo lectura, sin licencias adicionales).
- Objetivo explícito: que el proyecto sea desafiante y a la vez demuestre valor real a reclutadores, no un tutorial genérico.
