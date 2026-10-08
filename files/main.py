"""
Uso: python main.py ruta/al/export.csv
"""

# python main.py "C:\Users\LENOVO\Desktop\proyectos\proyecto mesa as\files\a\no resueltos (Jira Service Management Agrosuper).csv"
import sys
from clean import cargar_csv
from load import get_engine, obtener_estados_actuales, registrar_cambios_estado, upsert_tickets, registrar_carga


def main(ruta_csv: str):
    print(f"Leyendo {ruta_csv}...")
    df = cargar_csv(ruta_csv)
    print(f"{len(df)} filas leídas y normalizadas.")

    engine = get_engine()

    print("Comparando contra el estado guardado en MySQL...")
    estados_previos = obtener_estados_actuales(engine)

    print("Actualizando tabla tickets (upsert)...")
    upsert_tickets(engine, df)

    # El upsert va antes: historial_estados tiene una llave foránea hacia
    # tickets.id_incidencia, así que el ticket debe existir en `tickets`
    # antes de poder registrar su cambio de estado.
    registrar_cambios_estado(engine, df, estados_previos)

    registrar_carga(engine, ruta_csv, len(df))
    print("Carga finalizada correctamente.")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Uso: python main.py ruta/al/export.csv")
        sys.exit(1)
    main(sys.argv[1])