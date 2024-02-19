{% macro generate_column_yml(column, model_yaml, column_desc_dict, include_data_types, model, parent_column_name="") %}
    {% if parent_column_name %}
        {% set column_name = parent_column_name ~ "." ~ column.name %}
    {% else %}
        {% set column_name = column.name %}
    {% endif %}

    {% if column.name in ('id','name') %}
    {% do model_yaml.append('      - name: ' ~ model ~ '_' ~ column.name) %}
    {% do model_yaml.append("        description: '" ~ '{{ doc("' ~ model ~ '_' ~ column.name ~ '") }}' ~ "'" ) %}

    {% else %}
    {% do model_yaml.append('      - name: ' ~ column.name ~ '') %}
    {% do model_yaml.append("        description: '" ~ '{{ doc("' ~ column.name ~ '") }}' ~ "'" ) %}
    {% endif %}
    
    {% do model_yaml.append('') %}

    {% if column.fields|length > 0 %}
        {% for child_column in column.fields %}
            {% set model_yaml = codegen.generate_column_yaml(child_column, model_yaml, column_desc_dict, include_data_types, parent_column_name=column_name) %}
        {% endfor %}
    {% endif %}
    {% do return(model_yaml) %}
{% endmacro %}

{% macro generate_staging_yml(upstream_descriptions=False, package_name=[], schema_name=[], database_name=[], model_names=[]) %}

    {% set model_yaml=[] %}

    {% do model_yaml.append('version: 2') %}
    {% do model_yaml.append('') %}
    {% do model_yaml.append('models:') %}

    {% if model_names is string %}
        {{ exceptions.raise_compiler_error("The `model_names` argument must always be a list, even if there is only one model.") }}
    {% else %}
        {% for model in model_names %}
            {% do model_yaml.append('  - name: stg_' ~ package_name ~ '__' ~ model) %}
            {% do model_yaml.append("    description: '" ~ '{{ doc("stg_' ~ package_name ~ '__' ~ model ~ '") }}' ~ "'") %}
            {% do model_yaml.append('    columns:') %}

            {# {% set relation=source(package_name,model) %}
            {%- set columns = adapter.get_columns_in_relation(relation) -%} #}

            {% set table_relation=api.Relation.create(
                database=database_name,
                schema=schema_name,
                identifier=model
            ) %}

            {% set columns=adapter.get_columns_in_relation(table_relation) %}

            {% set column_desc_dict =  codegen.build_dict_column_descriptions(model) if upstream_descriptions else {} %}

            {% for column in columns %}
                {% set model_yaml = generate_column_yml(column, model_yaml, column_desc_dict, include_data_types, model) %}
            {% endfor %}
        {% endfor %}
    {% endif %}

{% if execute %}

    {% set joined = model_yaml | join ('\n') %}
    {{ log(joined, info=True) }}
    {% do return(joined) %}

{% endif %}

{% endmacro %}