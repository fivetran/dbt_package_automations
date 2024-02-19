#!/bin/bash
mkdir -p $1/macros
echo Generating macros for $5
dbt run-operation dbt_package_automations.generate_columns_macro --args '{"table_name": "'$5'", "schema_name": "'$4'", "database_name":"'$3'"}' | tail -n +4 | sed 's/\x1b\[[0-9;]*m//g' | sed 's/^[0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}  //' > $1/macros/get_$5_columns.sql
