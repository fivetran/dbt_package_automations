{% macro default__get_column_names_for_docs(table_name, schema_name, database_name=target.database, package_name=schema_name) %}

{% set query %}

select
    lower(column_name)
from {{ database_name }}.information_schema.columns
where lower(table_name) = '{{ table_name }}'
and lower(table_schema) = '{{ schema_name }}'
order by 1

{% endset %}

{% set results = run_query(query) %}
{% set results_list = results.columns[0].values() %}}
{% do jinja_macro.append('{% docs ' ~ table_name ~ ' %} <insert description here> {% enddocs %}') %}
{% do jinja_macro.append('{% docs stg_' ~ package_name ~ '__' ~ table_name ~ ' %} <insert description here> {% enddocs %}') %}
{% for col in results_list %}
{% if col in ('id','name') %}
{% do jinja_macro.append('{% docs ' ~ col ~ ' %} <insert description here> {% enddocs %}') %}
{% do jinja_macro.append('{% docs ' ~ table_name ~ '_' ~ col ~ ' %} <insert description here> {% enddocs %}') %}
{% else %}
{% do jinja_macro.append('{% docs ' ~ col ~ ' %} <insert description here> {% enddocs %}') %}
{% endif %}
{% endfor %}

{% if execute %}
    {% set joined = jinja_macro | join ('\n') %}
    {{ log(joined, info=True) }}
    {% do return(joined) %}
{% endif %}

{{ return(results_list) }} 

{% endmacro %}



{% macro bigquery__get_column_names_for_docs(table_name, schema_name, database_name=target.database, package_name=schema_name) %}

{% set query %}

select
    lower(column_name)
from `{{ database_name }}`.{{ schema_name }}.INFORMATION_SCHEMA.COLUMNS
where lower(table_name) = '{{ table_name }}'
and lower(table_schema) = '{{ schema_name }}'
order by 1

{% endset %}

{% set jinja_macro=[] %}
{% set results = run_query(query) %}
{% set results_list = results.columns[0].values() %}}
{% do jinja_macro.append('{% docs ' ~ table_name ~ ' %} <insert description here> {% enddocs %}') %}
{% do jinja_macro.append('{% docs stg_' ~ package_name ~ '__' ~ table_name ~ ' %} <insert description here> {% enddocs %}') %}
{% for col in results_list %}
{% if col in ('id','name') %}
{% do jinja_macro.append('{% docs ' ~ col ~ ' %} <insert description here> {% enddocs %}') %}
{% do jinja_macro.append('{% docs ' ~ table_name ~ '_' ~ col ~ ' %} <insert description here> {% enddocs %}') %}
{% else %}
{% do jinja_macro.append('{% docs ' ~ col ~ ' %} <insert description here> {% enddocs %}') %}
{% endif %}
{% endfor %}

{% if execute %}
    {% set joined = jinja_macro | join ('\n') %}
    {{ log(joined, info=True) }}
    {% do return(joined) %}
{% endif %}

{{ log(joined, info=True)}} 
{{ return(joined) }}

{% endmacro %}



{% macro get_column_names_for_docs(table_name, schema_name, database_name, package_name) %}
{{ return(adapter.dispatch('get_column_names_for_docs')(table_name, schema_name, database_name, package_name)) }}
{% endmacro %}
