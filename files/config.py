"""
Configuración del pipeline de carga.
Ajusta los datos de conexión a tu MySQL local, o defínelos como
variables de entorno (recomendado para no versionar credenciales
en un repo público de GitHub).
"""

import os

DB_CONFIG = {
    "host": os.getenv("DB_HOST", "localhost"),
    "port": int(os.getenv("DB_PORT", "3306")),
    "user": os.getenv("DB_USER", "root"),
    "password": os.getenv("DB_PASSWORD", "admin"),
    "database": os.getenv("DB_NAME", "sla_dashboard_as"),
}

# Mapeo: nombre de columna en el CSV exportado de Jira -> nombre de columna en la tabla `tickets`
COLUMN_MAP = {
    "Tipo de Incidencia": "tipo_incidencia",
    "Clave de incidencia": "clave",
    "ID de la incidencia": "id_incidencia",
    "Resumen": "resumen",
    "Persona asignada": "persona_asignada",
    "ID de la persona asignada": "id_asignado",
    "Informador": "informador",
    "ID del informador": "id_informador",
    "Prioridad": "prioridad",
    "Estado": "estado",
    "Resolución": "resolucion",
    "Creada": "creada",
    "Actualizada": "actualizada",
    "Fecha de vencimiento": "fecha_vencimiento",
}

# Columnas que contienen fechas en formato español: "06 abr 2026, 0:36"
DATE_COLUMNS = ["creada", "actualizada", "fecha_vencimiento"]

MESES_ES = {
    "ene": "01", "feb": "02", "mar": "03", "abr": "04",
    "may": "05", "jun": "06", "jul": "07", "ago": "08",
    "sep": "09", "oct": "10", "nov": "11", "dic": "12",
}

# Estados que se consideran "resolución" para efectos de historial/SLA
ESTADOS_RESUELTOS = ["Resuelto", "Cerrado"]
