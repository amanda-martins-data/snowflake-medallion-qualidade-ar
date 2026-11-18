-- Nenhuma medição pode estar no futuro (tolerância de 1 hora para
-- diferença de relógio entre fonte e Snowflake). Uma falha aqui indica
-- problema de fuso horário ou de parsing de data na Silver.
select *
from {{ ref('silver_air_quality') }}
where measured_at_utc > dateadd(hour, 1, convert_timezone('UTC', current_timestamp())::timestamp_ntz)
