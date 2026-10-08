const mysql = require('mysql2/promise');
require('dotenv').config();

const pool = mysql.createPool({
  host: process.env.DB_HOST || 'localhost',
  port: process.env.DB_PORT || 3306,
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASSWORD || 'admin',
  database: process.env.DB_NAME || 'sla_dashboard_as',
  waitForConnections: true,
  connectionLimit: 10,
  // Fuerza la collation de la conexión para que coincida con la de la
  // base de datos (utf8mb4_unicode_ci). Sin esto, MySQL 8 usa por
  // defecto utf8mb4_0900_ai_ci en la conexión, lo que choca contra las
  // columnas de las vistas y genera "Illegal mix of collations".
  charset: 'utf8mb4_unicode_ci',
});

module.exports = pool;