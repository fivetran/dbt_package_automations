{% macro default__get_column_names_only(table_name, schema_name, database_name=target.database) %}

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
{% for col in results_list %}
{% if col in ('id','name') %}
{% do jinja_macro.append('        ' ~ col ~ ' as ' ~ table_name ~ '_' ~ col ~ (',' if not loop.last)) %}
{% else %}
{% do jinja_macro.append('        ' ~ col ~ (',' if not loop.last)) %}
{% endif %}
{% endfor %}

{% if execute %}
    {% set joined = jinja_macro | join ('\n') %}
    {{ log(joined, info=True) }}
    {% do return(joined) %}
{% endif %}

{{ return(results_list) }} 

{% endmacro %}



{% macro bigquery__get_column_names_only(table_name, schema_name, database_name=target.database) %}

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
{% for col in results_list %}
{% if col in ('id','name') %}
{% do jinja_macro.append('        ' ~ col ~ ' as ' ~ table_name ~ '_' ~ col ~ (',' if not loop.last)) %}
{% else %}
{% do jinja_macro.append('        ' ~ col ~ (',' if not loop.last)) %}
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



{% macro get_column_names_only(table_name, schema_name, database_name) -%}
{{ return(adapter.dispatch('get_column_names_only')(table_name, schema_name, database_name)) }}
{%- endmacro %}
