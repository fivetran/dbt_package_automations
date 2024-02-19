{% macro get_tables_in_schema(schema_name, database_name=target.database, table_pattern='%', exclude='') %}
    
    {% set tables=dbt_utils.get_relations_by_pattern(
        schema_pattern=schema_name,
        database=database_name,
        table_pattern=table_pattern,
        exclude=exclude
    ) %}

    {% set table_list= tables | map(attribute='identifier') %}

    {{ return(table_list | sort) }}

{% endmacro %}


---
{% macro generate_source_macro(schema_name, package_name=schema_name, database_name=target.database, generate_columns=False, include_descriptions=False, include_data_types=True, table_pattern='%', exclude='', name=schema_name, table_names=None, include_database=False, include_schema=False) %}

{% set sources_yaml=[] %}
{% do sources_yaml.append('version: 2') %}
{% do sources_yaml.append('') %}
{% do sources_yaml.append('sources:') %}
{% do sources_yaml.append('  - name: ' ~ package_name | lower) %}

{# {% if database_name != target.database or include_database %} #}
{# {% do sources_yaml.append('    database: "{% if target.type not in ("spark") %}{{ var("' ~ package_name ~ '_database", target.database) }}{% endif %}"' | lower) %} #}
{% do sources_yaml.append("    database: '" ~ '{% if target.type not in ("spark") %}{{ var("' ~ package_name ~ '_database", target.database) }}{% endif %}' | lower ~ "'" ) %}
{# {% endif %} #}

{# {% if schema_name != name or include_schema %} #}
{# {% do sources_yaml.append('    schema: "{{ var("' ~ package_name ~ '_schema", "' ~ package_name ~ '")}}"' | lower) %} #}
{% do sources_yaml.append("    schema: '" ~ '{{ var("' ~ package_name ~ '_schema", "' ~ package_name ~ '") }}' | lower ~ "'" ) %}
{# {% endif %} #}

{% do sources_yaml.append('    tables:') %}

{% if table_names is none %}
{% set tables=codegen.get_tables_in_schema(schema_name, database_name, table_pattern, exclude) %}
{% else %}
{% set tables = table_names %}
{% endif %}

{% for table in tables %}
    {% do sources_yaml.append('      - name: ' ~ table | lower ) %}
    {# {% do sources_yaml.append('        identifier: "{{ var("' ~ package_name ~ '_' ~ table ~ '_identifier", "' ~ table ~ '")}}"' ) %} #}
    {% do sources_yaml.append("        identifier: '" ~ '{{ var("' ~ package_name ~ '_' ~ table ~ '_identifier", "' ~ table ~ '") }}' ~ "'" ) %}

    {% if include_descriptions %}
        {# {% do sources_yaml.append('        description: "{{ doc("' ~ table ~ '") }}"' ) %} #}
        {% do sources_yaml.append("        description: '" ~ '{{ doc("' ~ table ~ '") }}' ~ "'" ) %}
    {% endif %}
    {% if generate_columns %}
    {% do sources_yaml.append('        columns:') %}

        {% set table_relation=api.Relation.create(
            database=database_name,
            schema=schema_name,
            identifier=table
        ) %}

        {% set columns=adapter.get_columns_in_relation(table_relation) %}

        {% for column in columns %}
            {% do sources_yaml.append('          - name: ' ~ column.name | lower ) %}
            {% if include_data_types %}
                {% do sources_yaml.append('            data_type: ' ~ codegen.data_type_format_source(column)) %}
            {% endif %}
            {% if include_descriptions %}
                {# {% do sources_yaml.append('            description: "{{ doc("' ~ column.name | lower ~ '") }}"' ) %} #}
                {% do sources_yaml.append("            description: '" ~ '{{ doc("' ~ column.name | lower ~ '") }}' ~ "'" ) %}

            {% endif %}
        {% endfor %}
            {% do sources_yaml.append('') %}

    {% endif %}

{% endfor %}

{% if execute %}

    {% set joined = sources_yaml | join ('\n') %}
    {{ log(joined, info=True) }}
    {% do return(joined) %}

{% endif %}

{% endmacro %}