{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key=['location_id', 'parameter', 'measured_at_utc'],
        on_schema_change='append_new_columns'
    )
}}

-- silver_air_quality
-- Camada Silver: uma linha por medição (estação + poluente + horário),
-- já tipada, limpa e deduplicada.
--
-- * LATERAL FLATTEN abre o array `results` do payload VARIANT da Bronze.
-- * TRY_CAST: um valor fora do formato esperado vira NULL e é filtrado,
--   em vez de derrubar o pipeline inteiro.
-- * Incremental com MERGE: cada execução lê só o que chegou na Bronze
--   desde a última carga (_loaded_at) e faz upsert pela chave natural.
--   Reprocessar não duplica; uma medição reenviada atualiza a anterior.

with bronze as (

    select
        r.payload,
        r._source_file,
        r._loaded_at
    from {{ source('bronze', 'raw_openaq') }} as r

    {% if is_incremental() %}
    where r._loaded_at > (
        select coalesce(max(_loaded_at), '1900-01-01'::timestamp_ltz)
        from {{ this }}
    )
    {% endif %}

),

flattened as (

    select
        try_cast(m.value:_location_id::string as number)        as location_id,
        m.value:_location_name::string                           as location_name,
        m.value:_city_query::string                              as city,
        lower(m.value:parameter::string)                         as parameter,
        m.value:unit::string                                     as unit,
        try_cast(m.value:value::string as double)                as value,
        convert_timezone(
            'UTC', try_cast(m.value:date:utc::string as timestamp_tz)
        )::timestamp_ntz                                         as measured_at_utc,
        try_cast(b.payload:extracted_at::string as timestamp_tz) as extracted_at,
        coalesce(b.payload:_synthetic::boolean, false)           as is_synthetic,
        b._source_file,
        b._loaded_at
    from bronze as b,
        lateral flatten(input => b.payload:results) as m

)

select
    location_id,
    location_name,
    city,
    parameter,
    unit,
    value,
    measured_at_utc,
    measured_at_utc::date as measured_date,
    is_synthetic,
    extracted_at,
    _source_file,
    _loaded_at
from flattened
where location_id is not null
  and parameter is not null
  and measured_at_utc is not null
  and value is not null
  and value >= 0
-- mais de uma extração da mesma medição: fica a mais recente
qualify row_number() over (
    partition by location_id, parameter, measured_at_utc
    order by extracted_at desc, _loaded_at desc
) = 1
