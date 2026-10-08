const express = require('express');
const cors = require('cors');
const pool = require('./db');

const app = express();
app.use(cors());
app.use(express.json());

// Backlog actual por prioridad y estado
app.get('/api/backlog', async (req, res) => {
  try {
    const [rows] = await pool.query('SELECT * FROM vw_backlog_por_prioridad');
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Error al consultar el backlog' });
  }
});

// Tickets en riesgo de romper SLA (abiertos), ordenados por urgencia
app.get('/api/tickets-en-riesgo', async (req, res) => {
  try {
    const [rows] = await pool.query('SELECT * FROM vw_tickets_en_riesgo');
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Error al consultar tickets en riesgo' });
  }
});

// Cumplimiento histórico de SLA por prioridad
app.get('/api/sla-compliance', async (req, res) => {
  try {
    const [rows] = await pool.query('SELECT * FROM vw_sla_compliance');
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Error al consultar cumplimiento de SLA' });
  }
});

// Tendencia semanal: creados vs. resueltos
app.get('/api/tendencia-semanal', async (req, res) => {
  try {
    const [rows] = await pool.query('SELECT * FROM vw_tendencia_semanal');
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Error al consultar la tendencia semanal' });
  }
});

// Resumen general (KPI cards del dashboard)
app.get('/api/resumen', async (req, res) => {
  try {
    const [[{ total_abiertos }]] = await pool.query(
      'SELECT COUNT(*) AS total_abiertos FROM tickets WHERE resolucion IS NULL'
    );
    const [[{ total_breach }]] = await pool.query(
      `SELECT COUNT(*) AS total_breach FROM vw_tickets_en_riesgo WHERE estado_sla = 'Breach'`
    );
    const [[{ total_en_riesgo }]] = await pool.query(
      `SELECT COUNT(*) AS total_en_riesgo FROM vw_tickets_en_riesgo WHERE estado_sla = 'En riesgo'`
    );
    const [[{ ultima_carga, total_filas }]] = await pool.query(
      'SELECT fecha_carga AS ultima_carga, total_filas FROM cargas_csv ORDER BY fecha_carga DESC LIMIT 1'
    );

    res.json({ total_abiertos, total_breach, total_en_riesgo, ultima_carga, total_filas });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Error al consultar el resumen' });
  }
});

const PORT = process.env.PORT || 4000;
app.listen(PORT, () => {
  console.log(`API de SLA Dashboard corriendo en http://localhost:${PORT}`);
});
