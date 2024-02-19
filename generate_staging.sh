#!/bin/bash
mkdir -p $1/models/staging 
echo Generating staging.yml

dbt run-operation generate_staging_yml --args '{"schema_name": "'$4'", "package_name": "'$2'", "database_name": "'$3'", "model_names": '$5'}' | tail -n +4 | sed 's/\x1b\[[0-9;]*m//g' | sed 's/^[0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}  //' >> $1/models/staging/stg_$2.yml
