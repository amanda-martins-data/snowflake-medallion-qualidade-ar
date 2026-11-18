"""
snowflake_conn.py
------------------
Conexão com o Snowflake lida 100% de variáveis de ambiente — nenhuma
credencial no código ou no repositório. As mesmas variáveis são usadas
pelo dbt (profiles.yml), então só existe uma configuração.

Variáveis:
    SNOWFLAKE_ACCOUNT           ex.: abc12345.sa-east-1.aws  ou  orgname-accountname
    SNOWFLAKE_USER              seu usuário
    SNOWFLAKE_PRIVATE_KEY_PATH  caminho da chave gerada por generate_keypair.py
"""

from __future__ import annotations

import os

import snowflake.connector

WAREHOUSE = "WH_AIR_QUALITY_XS"
DATABASE = "AIR_QUALITY"


def _required(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise SystemExit(
            f"Variável de ambiente {name} não definida. Veja a seção 'Configuração' do README."
        )
    return value


def connect(role: str, schema: str) -> snowflake.connector.SnowflakeConnection:
    return snowflake.connector.connect(
        account=_required("SNOWFLAKE_ACCOUNT"),
        user=_required("SNOWFLAKE_USER"),
        private_key_file=_required("SNOWFLAKE_PRIVATE_KEY_PATH"),
        role=role,
        warehouse=WAREHOUSE,
        database=DATABASE,
        schema=schema,
        application="snowflake-medallion-qualidade-ar",
    )
