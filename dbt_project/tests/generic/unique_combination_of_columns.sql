{#
    Teste genérico: a combinação das colunas informadas é única no modelo.
    Equivalente ao teste de mesmo nome do dbt_utils, escrito aqui para o
    projeto não depender de pacotes externos.
#}
{% test unique_combination_of_columns(model, combination_of_columns) %}

select
    {{ combination_of_columns | join(', ') }},
    count(*) as occurrences
from {{ model }}
group by {{ combination_of_columns | join(', ') }}
having count(*) > 1

{% endtest %}
