"""
Diagnóstico: muestra los valores RAW de la columna Creada tal cual
vienen en el CSV, antes de cualquier limpieza. Esto nos permite ver
el formato exacto para ajustar el parser.
Uso: python diagnostico_fechas.py ruta/al/export.csv
"""
import sys
import pandas as pd

ruta = sys.argv[1]
df = pd.read_csv(ruta, encoding="utf-8")

print("Columnas detectadas en el CSV:")
print(list(df.columns))
print()
print("Primeros 10 valores crudos de la columna 'Creada':")
for v in df["Creada"].head(10):
    print(repr(v))
