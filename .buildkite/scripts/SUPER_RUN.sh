#!/bin/bash
#
# SUPER_RUN.sh - Universal BuildKite CI Script
# Single entry point for all dbt package CI execution
#
# This script:
# 1. Reads repo-specific config to determine what warehouses to test
# 2. Generates and uploads BuildKite pipeline dynamically
# 3. Each pipeline step sets up credentials and runs dbt tests for specific warehouses
#
# Usage: Called from pipeline.yml in each dbt package repo
# Environment Variables:
#   INCLUDE_DATABRICKS_SQL=true/false (optional, default: false)
#   INCLUDE_SQLSERVER=true/false (optional, default: false)
#

set -euo pipefail

echo "SUPER_RUN: Starting CI execution for $(basename "$PWD")"

# ============================================================================
# CONFIGURATION DETECTION
# ============================================================================

parse_yaml_config() {
    local config_file="$1"
    python3 -c "
import sys
import os
import subprocess

# Try to import yaml, install if not available
try:
    import yaml
except ImportError:
    print('Installing PyYAML...', file=sys.stderr)
    try:
        subprocess.check_call([sys.executable, '-m', 'pip', 'install', '--quiet', 'PyYAML'])
        import yaml
    except Exception as e:
        print(f'Failed to install PyYAML: {e}', file=sys.stderr)
        print('YAML_INCLUDE_DATABRICKS_SQL=false')
        print('YAML_INCLUDE_SQLSERVER=false')
        sys.exit(0)

try:
    with open('$config_file', 'r') as f:
        config = yaml.safe_load(f)

    # Extract warehouse settings with defaults
    include_databricks_sql = config.get('include_databricks_sql', False)
    include_sqlserver = config.get('include_sqlserver', False)

    # Print as key=value for bash to source
    print(f'YAML_INCLUDE_DATABRICKS_SQL={str(include_databricks_sql).lower()}')
    print(f'YAML_INCLUDE_SQLSERVER={str(include_sqlserver).lower()}')

except FileNotFoundError:
    print('YAML_INCLUDE_DATABRICKS_SQL=false')
    print('YAML_INCLUDE_SQLSERVER=false')
except Exception as e:
    print(f'Error parsing YAML: {e}', file=sys.stderr)
    print('YAML_INCLUDE_DATABRICKS_SQL=false')
    print('YAML_INCLUDE_SQLSERVER=false')
"
}

detect_warehouse_config() {
    local config_file="integration_tests/ci/test_scenarios.yml"
    local include_databricks_sql="${INCLUDE_DATABRICKS_SQL:-false}"
    local include_sqlserver="${INCLUDE_SQLSERVER:-false}"

    echo "Detecting warehouse configuration..."

    if [[ -f "$config_file" ]]; then
        echo "  - Found config file: $config_file"
        echo "  - Parsing YAML configuration..."

        # Parse YAML file using Python (installs PyYAML if needed)
        local yaml_output
        yaml_output=$(parse_yaml_config "$config_file")

        if [[ $? -eq 0 ]]; then
            # Source the output to get variables
            eval "$yaml_output"

            # Override defaults with YAML values if they're true
            if [[ "$YAML_INCLUDE_DATABRICKS_SQL" == "true" ]]; then
                include_databricks_sql="true"
                echo "  - Found include_databricks_sql: true in $config_file"
            fi

            if [[ "$YAML_INCLUDE_SQLSERVER" == "true" ]]; then
                include_sqlserver="true"
                echo "  - Found include_sqlserver: true in $config_file"
            fi
        else
            echo "  - Failed to parse YAML, using defaults"
        fi
    else
        echo "  - No config file found, using defaults"
    fi

    echo "  - INCLUDE_DATABRICKS_SQL: $include_databricks_sql"
    echo "  - INCLUDE_SQLSERVER: $include_sqlserver"

    # Export for use in pipeline generation
    export INCLUDE_DATABRICKS_SQL="$include_databricks_sql"
    export INCLUDE_SQLSERVER="$include_sqlserver"
}

# ============================================================================
# PIPELINE GENERATION & UPLOAD
# ============================================================================

generate_and_upload_pipeline() {
    echo "Generating and uploading BuildKite pipeline..."

    local script_url="https://raw.githubusercontent.com/fivetran/dbt_package_automations/test/superscript/.buildkite/scripts"
    local setup_url="$script_url/setup_credentials.sh"
    local test_url="$script_url/run_warehouse_tests.sh"

    # Show which warehouses will be tested
    local warehouses_list="postgres, snowflake, bigquery, redshift, databricks"
    if [[ "$INCLUDE_DATABRICKS_SQL" == "true" ]]; then
        warehouses_list="$warehouses_list, databricks-sql"
    fi
    if [[ "$INCLUDE_SQLSERVER" == "true" ]]; then
        warehouses_list="$warehouses_list, sqlserver"
    fi
    echo "  - Will test warehouses: $warehouses_list"

    # Generate pipeline YAML with explicit steps
    cat > /tmp/pipeline.yml <<EOF
steps:
  # Postgres
  - label: ":postgres: Run Tests - Postgres"
    key: "run_dbt_postgres"
    retry:
      automatic:
        - exit_status: -1
          limit: 1
    plugins:
      - docker#v3.13.0:
          image: "python:3.13"
          shell: ["/bin/bash", "-e", "-c"]
          environment:
            - "BASH_ENV=/tmp/.bashrc"
            - "BUILDKITE_BUILD_NUMBER"
            - "BUILDKITE_COMMIT"
            - "BUILDKITE_STEP_KEY"
            - "CI_POSTGRES_DBT_HOST"
            - "CI_POSTGRES_DBT_USER"
            - "CI_POSTGRES_DBT_PASS"
            - "CI_POSTGRES_DBT_DBNAME"
    commands: |
      curl -s "${setup_url}" | bash
      curl -s "${test_url}" | bash -s postgres

  # Snowflake
  - label: ":snowflake-db: Run Tests - Snowflake"
    key: "run_dbt_snowflake"
    retry:
      automatic:
        - exit_status: -1
          limit: 1
    plugins:
      - docker#v3.13.0:
          image: "python:3.13"
          shell: ["/bin/bash", "-e", "-c"]
          environment:
            - "BASH_ENV=/tmp/.bashrc"
            - "BUILDKITE_BUILD_NUMBER"
            - "BUILDKITE_COMMIT"
            - "BUILDKITE_STEP_KEY"
            - "CI_SNOWFLAKE_DBT_ACCOUNT"
            - "CI_SNOWFLAKE_DBT_DATABASE"
            - "CI_SNOWFLAKE_DBT_PASS"
            - "CI_SNOWFLAKE_DBT_ROLE"
            - "CI_SNOWFLAKE_DBT_USER"
            - "CI_SNOWFLAKE_DBT_WAREHOUSE"
    commands: |
      curl -s "${setup_url}" | bash
      curl -s "${test_url}" | bash -s snowflake

  # BigQuery
  - label: ":gcloud: Run Tests - BigQuery"
    key: "run_dbt_bigquery"
    retry:
      automatic:
        - exit_status: -1
          limit: 1
    plugins:
      - docker#v3.13.0:
          image: "python:3.13"
          shell: ["/bin/bash", "-e", "-c"]
          environment:
            - "BASH_ENV=/tmp/.bashrc"
            - "BUILDKITE_BUILD_NUMBER"
            - "BUILDKITE_COMMIT"
            - "BUILDKITE_STEP_KEY"
            - "GCLOUD_SERVICE_KEY"
    commands: |
      curl -s "${setup_url}" | bash
      curl -s "${test_url}" | bash -s bigquery

  # Redshift
  - label: ":amazon-redshift: Run Tests - Redshift"
    key: "run_dbt_redshift"
    retry:
      automatic:
        - exit_status: -1
          limit: 1
    concurrency: 3
    concurrency_group: "warehouse/redshift"
    plugins:
      - docker#v3.13.0:
          image: "python:3.13"
          shell: ["/bin/bash", "-e", "-c"]
          environment:
            - "BASH_ENV=/tmp/.bashrc"
            - "BUILDKITE_BUILD_NUMBER"
            - "BUILDKITE_COMMIT"
            - "BUILDKITE_STEP_KEY"
            - "CI_REDSHIFT_DBT_DBNAME"
            - "CI_REDSHIFT_DBT_HOST"
            - "CI_REDSHIFT_DBT_PASS"
            - "CI_REDSHIFT_DBT_USER"
    commands: |
      curl -s "${setup_url}" | bash
      curl -s "${test_url}" | bash -s redshift

  # Databricks
  - label: ":databricks: Run Tests - Databricks"
    key: "run_dbt_databricks"
    retry:
      automatic:
        - exit_status: -1
          limit: 1
    plugins:
      - docker#v3.13.0:
          image: "python:3.13"
          shell: ["/bin/bash", "-e", "-c"]
          environment:
            - "BASH_ENV=/tmp/.bashrc"
            - "BUILDKITE_BUILD_NUMBER"
            - "BUILDKITE_COMMIT"
            - "BUILDKITE_STEP_KEY"
            - "CI_DATABRICKS_DBT_HOST"
            - "CI_DATABRICKS_DBT_HTTP_PATH"
            - "CI_DATABRICKS_DBT_TOKEN"
            - "CI_DATABRICKS_DBT_CATALOG"
    commands: |
      curl -s "${setup_url}" | bash
      curl -s "${test_url}" | bash -s databricks
EOF

    # Add optional Databricks SQL step
    if [[ "$INCLUDE_DATABRICKS_SQL" == "true" ]]; then
        cat >> /tmp/pipeline.yml <<EOF

  # Databricks SQL (optional)
  - label: ":databricks: :database: Run Tests - Databricks-sql"
    key: "run_dbt_databricks_sql"
    retry:
      automatic:
        - exit_status: -1
          limit: 1
    plugins:
      - docker#v3.13.0:
          image: "python:3.13"
          shell: ["/bin/bash", "-e", "-c"]
          environment:
            - "BASH_ENV=/tmp/.bashrc"
            - "BUILDKITE_BUILD_NUMBER"
            - "BUILDKITE_COMMIT"
            - "BUILDKITE_STEP_KEY"
            - "CI_DATABRICKS_DBT_HOST"
            - "CI_DATABRICKS_SQL_DBT_HTTP_PATH"
            - "CI_DATABRICKS_SQL_DBT_TOKEN"
            - "CI_DATABRICKS_DBT_CATALOG"
    commands: |
      curl -s "${setup_url}" | bash
      curl -s "${test_url}" | bash -s databricks-sql
EOF
    fi

    # Add optional SQL Server step
    if [[ "$INCLUDE_SQLSERVER" == "true" ]]; then
        cat >> /tmp/pipeline.yml <<EOF

  # SQL Server (optional)
  - label: ":azure: Run Tests - Sqlserver"
    key: "run_dbt_sqlserver"
    retry:
      automatic:
        - exit_status: -1
          limit: 1
    plugins:
      - docker#v3.13.0:
          image: "python:3.13"
          shell: ["/bin/bash", "-e", "-c"]
          environment:
            - "BASH_ENV=/tmp/.bashrc"
            - "BUILDKITE_BUILD_NUMBER"
            - "BUILDKITE_COMMIT"
            - "BUILDKITE_STEP_KEY"
            - "CI_SQLSERVER_DBT_SERVER"
            - "CI_SQLSERVER_DBT_DATABASE"
            - "CI_SQLSERVER_DBT_USER"
            - "CI_SQLSERVER_DBT_PASS"
    commands: |
      curl -s "${setup_url}" | bash
      curl -s "${test_url}" | bash -s sqlserver
EOF
    fi

    echo "Uploading pipeline to BuildKite..."
    buildkite-agent pipeline upload /tmp/pipeline.yml

    echo "Pipeline uploaded successfully"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    detect_warehouse_config
    generate_and_upload_pipeline

    echo "SUPER_RUN completed successfully!"
    echo "   Repository: $(basename "$PWD")"
    echo "   Pipeline uploaded and ready to execute"
}

# Execute main function
main "$@"