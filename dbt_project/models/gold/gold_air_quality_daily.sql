-- gold_air_quality_daily
-- Camada Gold: uma linha por cidade, poluente e dia, com a classificação
-- de Índice de Qualidade do Ar (AQI) quando o poluente é PM2.5.
--
-- Faixas de PM2.5 (µg/m³, média de 24h) simplificadas a partir da escala
-- da EPA (EUA): referência pública, não substitui a escala oficial de
-- cada país para fins regulatórios.

with silver as (
    select * from {{ ref('silver_air_quality') }}
),

aggregated as (
    select
        city,
        parameter,
        unit,
        measured_date,
        count(*)               as reading_count,
        round(avg(value), 2)   as avg_value,
        round(min(value), 2)   as min_value,
        round(max(value), 2)   as max_value,
        boolor_agg(is_synthetic) as is_synthetic
    from silver
    group by city, parameter, unit, measured_date
)

select
    *,
    case
        when parameter != 'pm25' then null
        when avg_value <= 12.0   then 'Boa'
        when avg_value <= 35.4   then 'Moderada'
        when avg_value <= 55.4   then 'Insalubre p/ grupos sensíveis'
        when avg_value <= 150.4  then 'Insalubre'
        else 'Muito insalubre'
    end as aqi_category_pm25
from aggregated
