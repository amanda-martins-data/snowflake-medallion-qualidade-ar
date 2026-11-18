-- =====================================================================
-- 01_setup.sql
-- Infraestrutura do projeto no Snowflake. Rodar UMA vez, numa worksheet
-- do Snowsight, logada como ACCOUNTADMIN.
--
-- Cria:
--   * 1 warehouse XS com auto-suspend de 60s (custo mínimo)
--   * 1 database com os schemas BRONZE, SILVER e GOLD
--   * 2 roles com menor privilégio: LOADER (escreve na Bronze) e
--     TRANSFORMER (lê a Bronze, escreve Silver/Gold via dbt)
--   * file format JSON, stage interno de landing e a tabela Bronze
--
-- Antes de rodar: troque <SEU_USUARIO> pelo resultado de
-- `select current_user();`, mantendo as aspas duplas (preservam
-- maiúsculas/minúsculas do nome).
-- =====================================================================

use role accountadmin;

-- ---------------------------------------------------------------------
-- 1. Warehouse: XS e auto-suspend agressivo. Em trial, o crédito é o
--    recurso escasso; 60s ocioso já desliga o compute.
-- ---------------------------------------------------------------------
create warehouse if not exists wh_air_quality_xs
    warehouse_size = 'XSMALL'
    auto_suspend = 60
    auto_resume = true
    initially_suspended = true
    comment = 'Compute do projeto Medallion de qualidade do ar';

-- ---------------------------------------------------------------------
-- 2. Database e schemas das três camadas
-- ---------------------------------------------------------------------
create database if not exists air_quality
    comment = 'Medallion (Bronze/Silver/Gold) de qualidade do ar - OpenAQ';

create schema if not exists air_quality.bronze comment = 'Dado bruto, imutável (VARIANT)';
create schema if not exists air_quality.silver comment = 'Dado limpo, tipado e deduplicado';
create schema if not exists air_quality.gold   comment = 'Agregados prontos para consumo/BI';

-- ---------------------------------------------------------------------
-- 3. Roles com menor privilégio
--    LOADER      -> só escreve na Bronze (ingestão)
--    TRANSFORMER -> só lê a Bronze e escreve Silver/Gold (dbt)
-- ---------------------------------------------------------------------
create role if not exists loader;
create role if not exists transformer;

grant role loader      to role sysadmin;
grant role transformer to role sysadmin;

grant usage on warehouse wh_air_quality_xs to role loader;
grant usage on warehouse wh_air_quality_xs to role transformer;

grant usage on database air_quality to role loader;
grant usage on database air_quality to role transformer;

-- LOADER: dono da Bronze
grant usage, create table, create stage, create file format
    on schema air_quality.bronze to role loader;

-- TRANSFORMER: leitura da Bronze (inclusive tabelas futuras)
grant usage on schema air_quality.bronze to role transformer;
grant select on all tables    in schema air_quality.bronze to role transformer;
grant select on future tables in schema air_quality.bronze to role transformer;

-- TRANSFORMER: dono de Silver e Gold
grant usage, create table, create view on schema air_quality.silver to role transformer;
grant usage, create table, create view on schema air_quality.gold   to role transformer;

-- Seu usuário recebe as duas roles (troque <SEU_USUARIO>, mantendo as aspas)
grant role loader      to user "<SEU_USUARIO>";
grant role transformer to user "<SEU_USUARIO>";

-- ---------------------------------------------------------------------
-- 4. Objetos da Bronze, criados já como LOADER (ele vira o dono)
-- ---------------------------------------------------------------------
use role loader;
use warehouse wh_air_quality_xs;
use schema air_quality.bronze;

create file format if not exists json_format
    type = json
    compression = auto
    comment = 'Payload bruto da OpenAQ (1 objeto JSON por arquivo)';

create stage if not exists landing_stage
    file_format = json_format
    comment = 'Zona de landing: arquivos enviados via PUT por src/load_bronze.py';

-- Bronze guarda o payload inteiro em VARIANT (schema-on-read).
-- Se a API mudar ou ganhar campos, a carga não quebra: a Bronze
-- continua recebendo tudo e a adaptação acontece só na Silver.
create table if not exists raw_openaq (
    payload           variant       not null,
    _source_file      varchar       not null,
    _file_row_number  number        not null,
    _loaded_at        timestamp_ltz not null default current_timestamp()
)
comment = 'Bronze: payload bruto da OpenAQ, append-only';

-- O TRANSFORMER precisa ler esta tabela (o grant "future" acima cobre
-- as próximas; este cobre a que acabou de ser criada).
use role accountadmin;
grant select on table air_quality.bronze.raw_openaq to role transformer;
