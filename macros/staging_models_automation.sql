{% macro staging_models_automation(package, display_name, source_schema, source_database, tables) %}

{% set package = ""~ package ~"" %}
{% set source_schema = ""~ source_schema ~"" %}
{% set source_database = ""~ source_database ~"" %}
{% set tables_string = tables | join('","') %}
{% set tables_no_string = tables | join(',') %}

{% set starting_message = "source dbt_packages/dbt_package_automations/kick_off_generator.sh """~ display_name ~"""" %}
{% set zsh_command_columns = "source dbt_packages/dbt_package_automations/generate_columns.sh '../dbt_"""~ package ~"""' """~ package ~""" """~ source_database ~""" """~ source_schema ~""" " %}
{% set zsh_command_models = "source dbt_packages/dbt_package_automations/generate_models.sh '../dbt_"""~ package ~"""' """~ package ~""" """~ source_database ~""" """~ source_schema ~""" " %}
{% set zsh_command_source = "source dbt_packages/dbt_package_automations/generate_source.sh '../dbt_"""~ package ~"""' """~ package ~""" """~ source_database ~""" """~ source_schema ~""" '"""~ tables ~"""' " %}
{% set zsh_command_source_docs = "source dbt_packages/dbt_package_automations/generate_docs_md.sh '../dbt_"""~ package ~"""' """~ package ~""" """~ source_database ~""" """~ source_schema ~""" '"""~ tables_string ~"""' " %}
{% set zsh_files_creation = "source dbt_packages/dbt_package_automations/generate_files.sh """~ package ~""" '"""~ display_name ~"""' " %}
{% set dbt_project_yml_update = "source dbt_packages/dbt_package_automations/edit_dbt_project_yml.sh """~ package ~""" '"""~ tables_no_string ~"""' " %}
{% set dbt_integration_yml_update = "source dbt_packages/dbt_package_automations/edit_integrations_project_yml.sh """~ package ~""" '"""~ tables_no_string ~"""' " %}

{%- set columns_array = [] -%}
{%- set models_array = [] -%}

{% for t in tables %}
    {% set help_command = zsh_command_columns + t %}
    {{ columns_array.append(help_command) }}

    {% set help_command = zsh_command_models + t %}
    {{ models_array.append(help_command) }}

{% endfor %}

{{ log(starting_message + ' && \n' + zsh_command_source + ' && \n' + columns_array|join(' && \n') + ' && \n' + models_array|join(' && \n') + ' && \n' + zsh_command_source_docs+ ' && \n' + zsh_files_creation+ ' && \n' + dbt_project_yml_update+ ' && \n' + dbt_integration_yml_update, info=True) }}

{% endmacro %} 