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

## Motor de base de datos
Se confirmó que Erik usa **MySQL local** (no PostgreSQL) y ya cargó el esquema sin errores.
`schema_mysql.sql` (tickets, historial_estados, sla_reglas, cargas_csv,
+ vistas vw_backlog_por_prioridad, vw_tickets_en_riesgo, vw_sla_compliance, vw_tendencia_semanal).

## Script de carga (ETL) — ya construido y probado
Carpeta `etl/` con 5 archivos, probados con datos simulados (lógica de limpieza validada;
la conexión real a MySQL no se pudo probar en el sandbox por falta de cliente MySQL, pero
usa SQL estándar y SQLAlchemy):

- `config.py` — conexión a MySQL vía variables de entorno + mapeo de columnas del CSV de Jira
  a nombres de columna de la tabla `tickets` + diccionario de meses en español para parseo de fechas.
- `clean.py` — lee el CSV, renombra columnas, parsea fechas tipo "06 abr 2026, 0:36" (formato
  español con coma interna, requiere que el CSV traiga esos campos citados), convierte IDs a
  numérico, limpia strings vacíos a NULL, descarta filas sin id_incidencia válido.
- `load.py` — obtiene estados actuales desde MySQL, compara contra el CSV nuevo y registra
  cambios en `historial_estados` (diff histórico), hace upsert en `tickets` con
  `INSERT ... ON DUPLICATE KEY UPDATE`, y registra cada carga en `cargas_csv`.
- `main.py` — orquesta todo: `python main.py ruta/al/export.csv`.
- `requirements.txt` — pandas, SQLAlchemy, PyMySQL.

Nota importante: en la primera carga, todos los tickets se registran como "nuevos" en
historial_estados (estado_anterior = NULL). El valor real de vw_sla_compliance aparece desde
la segunda carga en adelante, al comparar contra lo ya guardado.

## Carga real exitosa (hito importante)
Erik ejecutó el ETL contra datos reales de Agrosuper: **3033 tickets** cargados vía upsert
y 3033 cambios de estado registrados en historial_estados, sin errores.

Bugs reales encontrados y corregidos durante el proceso (quedan documentados por si
reaparecen en otra máquina o con otro export):
1. Orden de operaciones: el upsert de `tickets` debe ir ANTES de insertar en
   `historial_estados` (llave foránea lo exige).
2. `NaN`/`NaT` de pandas no se convierten a `None` con `df.where(pd.notnull(df), None)`
   en columnas tipadas (float64/datetime64) — se resolvió con una función `_valor_sql()`
   que usa `pd.isna()` valor por valor.
3. El formato real de fecha del export de Agrosuper es `DD/mes_abreviado/AA HH:MM`
   (ej. `06/abr/26 00:09`) — con barras, sin coma, año de 2 dígitos. Distinto al
   formato inicialmente asumido con comas y año de 4 dígitos.

## Backend Node/Express — ya construido
Carpeta `backend/`: `server.js`, `db.js` (pool de conexión mysql2), `.env.example`,
`package.json`. Expone 5 endpoints REST sobre las vistas SQL:
`/api/resumen`, `/api/backlog`, `/api/tickets-en-riesgo`, `/api/sla-compliance`,
`/api/tendencia-semanal`. Verificado con `node --check` (sin cliente MySQL en el
sandbox para probar la conexión real, pendiente que Erik lo confirme en su máquina).

## Próximos pasos (en orden)
1. ✅ Esquema SQL completo, adaptado a MySQL — cargado y confirmado sin errores
2. ✅ Script de carga en Python (ETL) — corrido con éxito contra datos reales (3033 tickets)
3. ✅ Backend Node/Express construido (pendiente que Erik lo pruebe en su máquina)
4. ⏳ Frontend React con dashboard de KPIs y alertas de breach de SLA

## Contexto del autor (para retomar tono/nivel técnico)
- Erik Avello Muñoz, profesional de operaciones IT en Agrosuper (Chile), en transición a roles junior de Data/BI Analyst.
- Ya construyó un dashboard ejecutivo real en Power BI para Agrosuper/Softtek alimentado por Jira (con restricciones de solo lectura, sin licencias adicionales).
- Objetivo explícito: que el proyecto sea desafiante y a la vez demuestre valor real a reclutadores, no un tutorial genérico.
