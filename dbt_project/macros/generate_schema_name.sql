{#
    Por padrão o dbt prefixa schemas customizados com o schema do target
    (ex.: SILVER_GOLD). Aqui o schema configurado no modelo é usado como
    está, para que as camadas caiam exatamente em SILVER e GOLD, os mesmos
    schemas criados (e com permissões dadas) em setup/01_setup.sql.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
