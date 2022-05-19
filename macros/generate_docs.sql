{% macro generate_docs(package) %}

{% set package = ""~ package ~"" %}

{% set zsh_command = "source dbt_packages/dbt_package_automations/generate_docs.sh '../dbt_"""~ package ~""""+"'" %}

{{ log (zsh_command, info=True) }}

{% endmacro %} 