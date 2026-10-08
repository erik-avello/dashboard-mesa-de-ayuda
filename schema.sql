-- ============================================================
-- Esquema: Dashboard de monitoreo de SLA e incidentes IT
-- Motor: PostgreSQL
-- ============================================================

-- ------------------------------------------------------------
-- 1. Tabla de reglas de SLA por prioridad
-- ------------------------------------------------------------
-- Define cuántas horas tiene el equipo para resolver un ticket
-- según su prioridad. Ajustar estos valores según el acuerdo
-- real de servicio de la organización.

CREATE TABLE sla_reglas (
    prioridad           VARCHAR(20) PRIMARY KEY,
    horas_resolucion     NUMERIC(6,2) NOT NULL,
    descripcion          TEXT
);

INSERT INTO sla_reglas (prioridad, horas_resolucion, descripcion) VALUES
    ('Crítica', 4,   'Servicio caído o bloqueo total de operación'),
    ('Alta',    8,   'Bloqueo parcial, afecta a varios usuarios'),
    ('Media',   24,  'Afecta a un usuario o proceso puntual'),
    ('Baja',    72,  'Consulta o mejora sin urgencia');

-- ------------------------------------------------------------
-- 2. Tabla de tickets (snapshot actual)
-- ------------------------------------------------------------
-- Se actualiza en cada carga de CSV vía UPSERT (ON CONFLICT).
-- id_incidencia es la clave estable (no cambia aunque el
-- proyecto/prefijo del ticket se modifique).

CREATE TABLE tickets (
    id_incidencia        BIGINT PRIMARY KEY,
    clave                VARCHAR(20) UNIQUE NOT NULL,
    tipo_incidencia       VARCHAR(50),
    resumen               TEXT,
    id_asignado           BIGINT,
    persona_asignada      VARCHAR(150),
    id_informador         BIGINT,
    informador            VARCHAR(150),
    prioridad             VARCHAR(20) REFERENCES sla_reglas(prioridad),
    estado                VARCHAR(50) NOT NULL,
    resolucion            VARCHAR(50),
    creada                TIMESTAMP NOT NULL,
    actualizada           TIMESTAMP,
    fecha_vencimiento     TIMESTAMP,
    fecha_ultima_carga    TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_tickets_estado ON tickets(estado);
CREATE INDEX idx_tickets_prioridad ON tickets(prioridad);
CREATE INDEX idx_tickets_creada ON tickets(creada);

-- ------------------------------------------------------------
-- 3. Historial de cambios de estado
-- ------------------------------------------------------------
-- Se llena desde el script Python: antes de cada UPSERT se
-- compara el estado guardado vs. el estado nuevo del CSV; si
-- difieren, se inserta una fila aquí con la transición.

CREATE TABLE historial_estados (
    id                SERIAL PRIMARY KEY,
    id_incidencia     BIGINT NOT NULL REFERENCES tickets(id_incidencia),
    estado_anterior   VARCHAR(50),
    estado_nuevo      VARCHAR(50) NOT NULL,
    fecha_cambio      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_historial_ticket ON historial_estados(id_incidencia);

-- ------------------------------------------------------------
-- 4. Log de cargas (auditoría de cada export procesado)
-- ------------------------------------------------------------
-- Permite verificar que cada carga trajo el universo completo
-- de tickets (comparando total_filas contra lo esperado).

CREATE TABLE cargas_csv (
    id                SERIAL PRIMARY KEY,
    archivo           VARCHAR(255),
    total_filas       INTEGER NOT NULL,
    fecha_carga       TIMESTAMP NOT NULL DEFAULT NOW()
);

-- ============================================================
-- VISTAS DE ANÁLISIS / KPIs
-- ============================================================

-- ------------------------------------------------------------
-- 5. Backlog actual por prioridad y estado
-- ------------------------------------------------------------

CREATE VIEW vw_backlog_por_prioridad AS
SELECT
    prioridad,
    estado,
    COUNT(*) AS total_tickets,
    ROUND(AVG(EXTRACT(EPOCH FROM (NOW() - creada)) / 3600), 1) AS horas_promedio_abierto
FROM tickets
WHERE resolucion IS NULL
GROUP BY prioridad, estado
ORDER BY prioridad, total_tickets DESC;

-- ------------------------------------------------------------
-- 6. Tickets en riesgo de romper SLA (aún sin resolver)
-- ------------------------------------------------------------

CREATE VIEW vw_tickets_en_riesgo AS
SELECT
    t.clave,
    t.resumen,
    t.prioridad,
    t.estado,
    t.creada,
    r.horas_resolucion,
    ROUND(EXTRACT(EPOCH FROM (NOW() - t.creada)) / 3600, 1) AS horas_transcurridas,
    ROUND(
        r.horas_resolucion - (EXTRACT(EPOCH FROM (NOW() - t.creada)) / 3600), 1
    ) AS horas_restantes,
    CASE
        WHEN EXTRACT(EPOCH FROM (NOW() - t.creada)) / 3600 > r.horas_resolucion
            THEN 'Breach'
        WHEN EXTRACT(EPOCH FROM (NOW() - t.creada)) / 3600 > r.horas_resolucion * 0.8
            THEN 'En riesgo'
        ELSE 'Dentro de SLA'
    END AS estado_sla
FROM tickets t
JOIN sla_reglas r ON r.prioridad = t.prioridad
WHERE t.resolucion IS NULL
ORDER BY horas_restantes ASC;

-- ------------------------------------------------------------
-- 7. Cumplimiento de SLA histórico (tickets ya resueltos)
-- ------------------------------------------------------------
-- Usa el historial de estados para calcular el tiempo real
-- hasta el primer estado "Resuelto"/"Cerrado".

CREATE VIEW vw_sla_compliance AS
WITH resolucion_real AS (
    SELECT
        h.id_incidencia,
        MIN(h.fecha_cambio) AS fecha_resolucion
    FROM historial_estados h
    WHERE h.estado_nuevo IN ('Resuelto', 'Cerrado')
    GROUP BY h.id_incidencia
)
SELECT
    t.prioridad,
    COUNT(*) AS total_resueltos,
    SUM(
        CASE
            WHEN EXTRACT(EPOCH FROM (rr.fecha_resolucion - t.creada)) / 3600
                 <= r.horas_resolucion
            THEN 1 ELSE 0
        END
    ) AS cumplidos_sla,
    ROUND(
        100.0 * SUM(
            CASE
                WHEN EXTRACT(EPOCH FROM (rr.fecha_resolucion - t.creada)) / 3600
                     <= r.horas_resolucion
                THEN 1 ELSE 0
            END
        ) / COUNT(*), 1
    ) AS porcentaje_cumplimiento
FROM tickets t
JOIN resolucion_real rr ON rr.id_incidencia = t.id_incidencia
JOIN sla_reglas r ON r.prioridad = t.prioridad
GROUP BY t.prioridad
ORDER BY t.prioridad;

-- ------------------------------------------------------------
-- 8. Tendencia semanal: creados vs. resueltos
-- ------------------------------------------------------------

CREATE VIEW vw_tendencia_semanal AS
SELECT
    DATE_TRUNC('week', creados.semana) AS semana,
    creados.total_creados,
    COALESCE(resueltos.total_resueltos, 0) AS total_resueltos
FROM (
    SELECT DATE_TRUNC('week', creada) AS semana, COUNT(*) AS total_creados
    FROM tickets
    GROUP BY DATE_TRUNC('week', creada)
) creados
LEFT JOIN (
    SELECT DATE_TRUNC('week', h.fecha_cambio) AS semana, COUNT(*) AS total_resueltos
    FROM historial_estados h
    WHERE h.estado_nuevo IN ('Resuelto', 'Cerrado')
    GROUP BY DATE_TRUNC('week', h.fecha_cambio)
) resueltos ON resueltos.semana = creados.semana
ORDER BY semana;
