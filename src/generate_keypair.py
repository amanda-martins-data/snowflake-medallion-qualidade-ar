"""
generate_keypair.py
--------------------
Gera o par de chaves RSA usado para autenticar no Snowflake sem senha
(key-pair authentication) — o método recomendado para scripts e para o
dbt, já que contas novas exigem MFA no login com senha.

Funciona igual em Windows, macOS e Linux (não depende de openssl).

Saída:
    keys/snowflake_rsa_key.p8   -> chave PRIVADA (nunca versionar)
    keys/snowflake_rsa_key.pub  -> chave pública
    + o comando ALTER USER pronto para colar no Snowsight

Uso:
    python src/generate_keypair.py --user SEU_USUARIO
"""

from __future__ import annotations

import argparse
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

KEYS_DIR = Path(__file__).resolve().parent.parent / "keys"


def generate(user: str) -> None:
    KEYS_DIR.mkdir(exist_ok=True)
    private_path = KEYS_DIR / "snowflake_rsa_key.p8"
    public_path = KEYS_DIR / "snowflake_rsa_key.pub"

    if private_path.exists():
        raise SystemExit(
            f"{private_path} já existe. Apague-o manualmente se quiser gerar um par novo."
        )

    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)

    private_path.write_bytes(
        key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption(),
        )
    )
    public_pem = key.public_key().public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    ).decode()
    public_path.write_text(public_pem)

    # O Snowflake quer só o corpo da chave, sem cabeçalho/rodapé nem quebras.
    body = "".join(line for line in public_pem.splitlines() if "-----" not in line)

    print(f"Chave privada: {private_path}")
    print(f"Chave pública: {public_path}\n")
    print("Cole no Snowsight (como ACCOUNTADMIN):\n")
    print(f"alter user {user} set rsa_public_key = '{body}';")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Gera par de chaves RSA para o Snowflake.")
    parser.add_argument("--user", required=True, help="Seu usuário do Snowflake.")
    generate(parser.parse_args().user)
