"""
Lectura y limpieza del CSV exportado desde Jira.
"""

import re
import pandas as pd
from config import COLUMN_MAP, DATE_COLUMNS, MESES_ES


def parse_fecha_es(valor: str):
    """
    Convierte '06/abr/26 00:09' -> datetime de pandas.
    Devuelve NaT si el valor está vacío o no calza con el formato.
    """
    if pd.isna(valor) or not str(valor).strip():
        return pd.NaT

    texto = str(valor).strip().lower()
    match = re.match(r"(\d{1,2})/([a-z]{3})/(\d{2,4})\s+(\d{1,2}):(\d{2})", texto)
    if not match:
        return pd.NaT

    dia, mes_es, anio, hora, minuto = match.groups()
    mes = MESES_ES.get(mes_es)
    if mes is None:
        return pd.NaT

    if len(anio) == 2:
        anio = "20" + anio

    return pd.to_datetime(f"{anio}-{mes}-{dia.zfill(2)} {hora.zfill(2)}:{minuto}")


def cargar_csv(ruta_archivo: str) -> pd.DataFrame:
    """Lee el CSV exportado de Jira y devuelve un DataFrame ya normalizado."""
    df = pd.read_csv(ruta_archivo, encoding="utf-8")

    columnas_faltantes = set(COLUMN_MAP) - set(df.columns)
    if columnas_faltantes:
        raise ValueError(f"Faltan columnas esperadas en el CSV: {columnas_faltantes}")

    df = df.rename(columns=COLUMN_MAP)
    df = df[list(COLUMN_MAP.values())]

    for col in DATE_COLUMNS:
        df[col] = df[col].apply(parse_fecha_es)

    # IDs numéricos: aseguramos tipo entero (nulos posibles en id_asignado)
    for col in ["id_incidencia", "id_asignado", "id_informador"]:
        df[col] = pd.to_numeric(df[col], errors="coerce")

    # Texto vacío -> NULL real, no cadena vacía
    columnas_texto = ["persona_asignada", "informador", "resolucion", "resumen"]
    for col in columnas_texto:
        df[col] = df[col].replace(r"^\s*$", pd.NA, regex=True)

    # Filas sin id_incidencia no sirven de nada: se descartan con aviso
    filas_invalidas = df["id_incidencia"].isna().sum()
    if filas_invalidas:
        print(f"Aviso: se descartaron {filas_invalidas} filas sin id_incidencia válido")
        df = df.dropna(subset=["id_incidencia"])

    df["id_incidencia"] = df["id_incidencia"].astype(int)

    # 'creada' es NOT NULL en el esquema: si el parseo falló para alguna
    # fila, avisamos antes de que MySQL rechace el upsert completo.
    sin_fecha_creada = df["creada"].isna().sum()
    if sin_fecha_creada:
        print(f"Aviso: {sin_fecha_creada} filas quedaron sin fecha 'creada' válida tras el parseo")

    return df










