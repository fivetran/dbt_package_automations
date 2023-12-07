#!/bin/bash
mkdir -p $1/models/staging 
echo Generating source.yml
dbt run-operation generate_source_macro --args '{"schema_name": "'$4'", "package_name": "'$2'", "database_name": "'$3'", "generate_columns": true, "include_data_types": false, "include_descriptions": true, "table_names": '$5'}' | tail -n +4 | sed 's/\x1b\[[0-9;]*m//g' | sed 's/^[0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}  //' >> $1/models/staging/src_$2.yml
