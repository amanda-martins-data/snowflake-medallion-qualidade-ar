"""
load_bronze.py
---------------
Ingestão na camada Bronze do Snowflake, no padrão nativo da plataforma:

    1. PUT       envia os JSON da landing local (data/raw) para um stage
                 interno, comprimidos em gzip
    2. COPY INTO carrega o stage na tabela BRONZE.RAW_OPENAQ, guardando o
                 payload inteiro em VARIANT + metadados do arquivo

Idempotência: o COPY INTO mantém metadados de carga por arquivo. Rodar
o script de novo com os mesmos arquivos não duplica nada — arquivos já
carregados (mesmo nome e mesmo conteúdo) são ignorados. Se um arquivo
for reenviado com conteúdo novo, ele é carregado de novo, e a
deduplicação fica a cargo da Silver.

Uso:
    python src/load_bronze.py
"""

from __future__ import annotations

import logging
from pathlib import Path

from snowflake_conn import connect

LANDING_DIR = Path(__file__).resolve().parent.parent / "data" / "raw"

logging.basicConfig(level=logging.INFO, format="%(asctime)s | %(levelname)s | %(message)s")
log = logging.getLogger("load_bronze")

COPY_SQL = """
    copy into raw_openaq (payload, _source_file, _file_row_number)
    from (
        select $1, metadata$filename, metadata$file_row_number
        from @landing_stage
    )
    pattern = '.*openaq_.*[.]json[.]gz'
    on_error = abort_statement
"""


def load_to_bronze() -> int:
    files = sorted(LANDING_DIR.glob("openaq_*.json"))
    if not files:
        raise FileNotFoundError(
            f"Nenhum arquivo openaq_*.json em {LANDING_DIR}. "
            "Rode src/generate_sample_data.py ou src/extract.py primeiro."
        )

    conn = connect(role="LOADER", schema="BRONZE")
    try:
        cur = conn.cursor()

        for f in files:
            # as_posix() gera barras normais, aceitas pelo PUT inclusive no Windows
            cur.execute(
                f"put 'file://{f.resolve().as_posix()}' @landing_stage "
                "auto_compress = true overwrite = true"
            )
            source, _, _, _, _, _, status, _ = cur.fetchone()
            log.info("PUT %s -> %s", source, status)

        cur.execute(COPY_SQL)
        loaded_rows = 0
        for row in cur.fetchall():
            # Sem arquivos novos, o COPY retorna uma única linha informativa
            if len(row) < 4:
                log.info("COPY: %s", row[0])
                continue
            file_name, status, rows_parsed, rows_loaded = row[:4]
            log.info("COPY %s -> %s (%s linhas)", file_name, status, rows_loaded)
            loaded_rows += rows_loaded or 0

        cur.execute("select count(*) from raw_openaq")
        total = cur.fetchone()[0]
        log.info("Carregadas %d linhas nesta execução; Bronze tem %d no total", loaded_rows, total)
        return loaded_rows
    finally:
        conn.close()


if __name__ == "__main__":
    load_to_bronze()
