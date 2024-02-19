#!/bin/bash
mkdir -p $1/models/staging/base 

echo "{{
    fivetran_utils.union_data(
        table_identifier='$5', 
        database_variable='$2_database', 
        schema_variable='$2_schema', 
        default_database=target.database,
        default_schema='$2',
        default_variable='$5',
        union_schema_variable='$2_union_schemas',
        union_database_variable='$2_union_databases'
    )
}}" > $1/models/staging/base/stg_$2__$5_base.sql 

echo "" > $1/models/staging/stg_$2__$5.sql

echo "with base as (

    select * 
    from {{ ref('stg_$2__$5_base') }}
),

fields as (

    select
        {{
            fivetran_utils.fill_staging_columns(
                source_columns=adapter.get_columns_in_relation(ref('stg_$2__$5_base')),
                staging_columns=get_$5_columns()
            )
        }}
        {{ fivetran_utils.source_relation(
            union_schema_variable='$2_union_schemas', 
            union_database_variable='$2_union_databases') 
        }}
    from base
),

final as (
    
    select 
        source_relation, " >> $1/models/staging/stg_$2__$5.sql
    

dbt run-operation dbt_package_automations.get_column_names_only --args '{"table_name": "'$5'", "schema_name": "'$4'", "database_name":"'$3'"}' | tail -n +4 | sed 's/\x1b\[[0-9;]*m//g' | sed 's/^[0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}  //' >> $1/models/staging/stg_$2__$5.sql
    
    
echo "    from fields
)

select *
from final" >> $1/models/staging/stg_$2__$5.sql

echo Generated $5 base and staging models
