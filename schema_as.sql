-- ============================================================
-- Esquema: Dashboard de monitoreo de SLA e incidentes IT
-- Motor: MySQL 8.0+
-- ============================================================

-- ------------------------------------------------------------
-- 1. Tabla de reglas de SLA por prioridad
-- ------------------------------------------------------------

CREATE TABLE sla_reglas (
    prioridad           VARCHAR(20) PRIMARY KEY,
    horas_resolucion    DECIMAL(6,2) NOT NULL,
    descripcion         TEXT
) ENGINE=InnoDB;

INSERT INTO sla_reglas (prioridad, horas_resolucion, descripcion) VALUES
    ('Crítica', 4,   'Servicio caído o bloqueo total de operación'),
    ('Alta',    8,   'Bloqueo parcial, afecta a varios usuarios'),
    ('Media',   24,  'Afecta a un usuario o proceso puntual'),
    ('Baja',    72,  'Consulta o mejora sin urgencia');

-- ------------------------------------------------------------
-- 2. Tabla de tickets (snapshot actual)
-- ------------------------------------------------------------

CREATE TABLE tickets (
    id_incidencia        BIGINT PRIMARY KEY,
    clave                VARCHAR(20) UNIQUE NOT NULL,
    tipo_incidencia      VARCHAR(50),
    resumen              TEXT,
    id_asignado          BIGINT,
    persona_asignada     VARCHAR(150),
    id_informador        BIGINT,
    informador           VARCHAR(150),
    prioridad            VARCHAR(20),
    estado               VARCHAR(50) NOT NULL,
    resolucion           VARCHAR(50),
    creada               DATETIME NOT NULL,
    actualizada          DATETIME,
    fecha_vencimiento    DATETIME,
    fecha_ultima_carga   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_tickets_prioridad FOREIGN KEY (prioridad) REFERENCES sla_reglas(prioridad)
) ENGINE=InnoDB;

CREATE INDEX idx_tickets_estado ON tickets(estado);
CREATE INDEX idx_tickets_prioridad ON tickets(prioridad);
CREATE INDEX idx_tickets_creada ON tickets(creada);

-- ------------------------------------------------------------
-- 3. Historial de cambios de estado
-- ------------------------------------------------------------

CREATE TABLE historial_estados (
    id                INT AUTO_INCREMENT PRIMARY KEY,
    id_incidencia     BIGINT NOT NULL,
    estado_anterior   VARCHAR(50),
    estado_nuevo      VARCHAR(50) NOT NULL,
    fecha_cambio      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_historial_ticket FOREIGN KEY (id_incidencia) REFERENCES tickets(id_incidencia)
) ENGINE=InnoDB;

CREATE INDEX idx_historial_ticket ON historial_estados(id_incidencia);

-- ------------------------------------------------------------
-- 4. Log de cargas (auditoría de cada export procesado)
-- ------------------------------------------------------------

CREATE TABLE cargas_csv (
    id                INT AUTO_INCREMENT PRIMARY KEY,
    archivo           VARCHAR(255),
    total_filas       INT NOT NULL,
    fecha_carga       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

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
    ROUND(AVG(TIMESTAMPDIFF(MINUTE, creada, NOW()) / 60.0), 1) AS horas_promedio_abierto
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
    ROUND(TIMESTAMPDIFF(MINUTE, t.creada, NOW()) / 60.0, 1) AS horas_transcurridas,
    ROUND(
        r.horas_resolucion - (TIMESTAMPDIFF(MINUTE, t.creada, NOW()) / 60.0), 1
    ) AS horas_restantes,
    CASE
        WHEN TIMESTAMPDIFF(MINUTE, t.creada, NOW()) / 60.0 > r.horas_resolucion
            THEN 'Breach'
        WHEN TIMESTAMPDIFF(MINUTE, t.creada, NOW()) / 60.0 > r.horas_resolucion * 0.8
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
            WHEN TIMESTAMPDIFF(MINUTE, t.creada, rr.fecha_resolucion) / 60.0
                 <= r.horas_resolucion
            THEN 1 ELSE 0
        END
    ) AS cumplidos_sla,
    ROUND(
        100.0 * SUM(
            CASE
                WHEN TIMESTAMPDIFF(MINUTE, t.creada, rr.fecha_resolucion) / 60.0
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
-- MySQL no tiene DATE_TRUNC: se calcula el lunes de cada
-- semana restando WEEKDAY(fecha) días a la fecha.

CREATE VIEW vw_tendencia_semanal AS
SELECT
    creados.semana,
    creados.total_creados,
    COALESCE(resueltos.total_resueltos, 0) AS total_resueltos
FROM (
    SELECT
        DATE_SUB(DATE(creada), INTERVAL WEEKDAY(creada) DAY) AS semana,
        COUNT(*) AS total_creados
    FROM tickets
    GROUP BY DATE_SUB(DATE(creada), INTERVAL WEEKDAY(creada) DAY)
) creados
LEFT JOIN (
    SELECT
        DATE_SUB(DATE(h.fecha_cambio), INTERVAL WEEKDAY(h.fecha_cambio) DAY) AS semana,
        COUNT(*) AS total_resueltos
    FROM historial_estados h
    WHERE h.estado_nuevo IN ('Resuelto', 'Cerrado')
    GROUP BY DATE_SUB(DATE(h.fecha_cambio), INTERVAL WEEKDAY(h.fecha_cambio) DAY)
) resueltos ON resueltos.semana = creados.semana
ORDER BY creados.semana;

