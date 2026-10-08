"""
Carga de datos a MySQL: upsert de tickets + registro de cambios
de estado en historial_estados.
"""

import pandas as pd
from sqlalchemy import create_engine, text
from config import DB_CONFIG


def get_engine():
    url = (
        f"mysql+pymysql://{DB_CONFIG['user']}:{DB_CONFIG['password']}"
        f"@{DB_CONFIG['host']}:{DB_CONFIG['port']}/{DB_CONFIG['database']}"
        f"?charset=utf8mb4"
    )
    return create_engine(url)


def _valor_sql(v):
    """
    Convierte un valor de pandas a algo que MySQL entienda:
    NaN, NaT o None -> None (NULL real). pd.isna() detecta los
    tres casos sin importar si la columna es float64, datetime64
    u object, a diferencia de df.where(pd.notnull(df), None), que
    pandas revierte a NaN/NaT en columnas tipadas.
    """
    if pd.isna(v):
        return None
    if isinstance(v, pd.Timestamp):
        return v.to_pydatetime()
    return v


def _df_a_registros(df: pd.DataFrame):
    return [
        {col: _valor_sql(row[col]) for col in df.columns}
        for _, row in df.iterrows()
    ]


def obtener_estados_actuales(engine) -> dict:
    """Devuelve {id_incidencia: estado} de lo que ya hay en la tabla tickets."""
    with engine.connect() as conn:
        rows = conn.execute(text("SELECT id_incidencia, estado FROM tickets")).fetchall()
    return {row[0]: row[1] for row in rows}


def registrar_cambios_estado(engine, df: pd.DataFrame, estados_previos: dict):
    """
    Compara el estado nuevo (CSV) contra el estado guardado en BD.
    Inserta una fila en historial_estados por cada ticket nuevo o
    cuyo estado cambió desde la última carga.
    """
    cambios = []
    for _, row in df.iterrows():
        id_inc = row["id_incidencia"]
        estado_nuevo = row["estado"]
        estado_anterior = estados_previos.get(id_inc)  # None si es ticket nuevo

        if estado_anterior != estado_nuevo:
            cambios.append({
                "id_incidencia": int(id_inc),
                "estado_anterior": estado_anterior,
                "estado_nuevo": estado_nuevo,
            })

    if not cambios:
        print("Sin cambios de estado respecto a la carga anterior.")
        return 0

    with engine.begin() as conn:
        conn.execute(
            text(
                """
                INSERT INTO historial_estados (id_incidencia, estado_anterior, estado_nuevo)
                VALUES (:id_incidencia, :estado_anterior, :estado_nuevo)
                """
            ),
            cambios,
        )

    print(f"Se registraron {len(cambios)} cambios de estado en historial_estados.")
    return len(cambios)


def upsert_tickets(engine, df: pd.DataFrame):
    """Inserta tickets nuevos o actualiza los existentes (por id_incidencia)."""
    registros = _df_a_registros(df)

    sql = text(
        """
        INSERT INTO tickets (
            id_incidencia, clave, tipo_incidencia, resumen,
            id_asignado, persona_asignada, id_informador, informador,
            prioridad, estado, resolucion, creada, actualizada, fecha_vencimiento
        ) VALUES (
            :id_incidencia, :clave, :tipo_incidencia, :resumen,
            :id_asignado, :persona_asignada, :id_informador, :informador,
            :prioridad, :estado, :resolucion, :creada, :actualizada, :fecha_vencimiento
        )
        ON DUPLICATE KEY UPDATE
            clave = VALUES(clave),
            tipo_incidencia = VALUES(tipo_incidencia),
            resumen = VALUES(resumen),
            id_asignado = VALUES(id_asignado),
            persona_asignada = VALUES(persona_asignada),
            id_informador = VALUES(id_informador),
            informador = VALUES(informador),
            prioridad = VALUES(prioridad),
            estado = VALUES(estado),
            resolucion = VALUES(resolucion),
            actualizada = VALUES(actualizada),
            fecha_vencimiento = VALUES(fecha_vencimiento),
            fecha_ultima_carga = CURRENT_TIMESTAMP
        """
    )

    with engine.begin() as conn:
        conn.execute(sql, registros)

    print(f"Upsert completado: {len(registros)} tickets procesados.")


def registrar_carga(engine, archivo: str, total_filas: int):
    with engine.begin() as conn:
        conn.execute(
            text("INSERT INTO cargas_csv (archivo, total_filas) VALUES (:archivo, :total)"),
            {"archivo": archivo, "total": total_filas},
        )
