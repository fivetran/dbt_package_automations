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

detect_warehouse_config() {
    local config_file="integration_tests/ci/test_scenarios.yml"

    echo "Detecting warehouse configuration..."

    if [[ -f "$config_file" ]]; then
        echo "  - Found config file: $config_file"

        # Parse YAML and set variables directly
        eval $(python3 -c "
import subprocess, sys

# Install PyYAML silently
try:
    subprocess.check_call([sys.executable, '-m', 'pip', 'install', '--quiet', 'PyYAML'],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    import yaml

    with open('$config_file', 'r') as f:
        config = yaml.safe_load(f) or {}

    databricks_sql = str(config.get('include_databricks_sql', False)).lower()
    sqlserver = str(config.get('include_sqlserver', False)).lower()

    print(f'export INCLUDE_DATABRICKS_SQL={databricks_sql}')
    print(f'export INCLUDE_SQLSERVER={sqlserver}')

except Exception as e:
    print(f'echo ERROR: Failed to parse config file: {e}', file=sys.stderr)
    sys.exit(1)
")
    else
        echo "ERROR: Config file not found: $config_file"
        echo "Each dbt package must have a test_scenarios.yml file"
        exit 1
    fi
}

# ============================================================================
# PIPELINE GENERATION & UPLOAD
# ============================================================================

generate_and_upload_pipeline() {
    echo "Generating and uploading BuildKite pipeline..."

    local script_url="https://raw.githubusercontent.com/fivetran/dbt_package_automations/test/superscript/.buildkite/scripts"
    local test_url="$script_url/run_warehouse_tests.sh"

    # Show which warehouses will be tested
    local warehouses_list="postgres, snowflake, bigquery, redshift, databricks"

    # Append optional warehouses based on config
    if [[ "$INCLUDE_DATABRICKS_SQL" == "true" ]]; then
        warehouses_list="$warehouses_list, databricks_sql"
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
    commands: |
      curl -s "${test_url}" -o run_warehouse_tests.sh && bash run_warehouse_tests.sh postgres

  # Snowflake
  - label: ":snowflake-db: Run Tests - Snowflake"
    key: "run_dbt_snowflake"
    retry:
      automatic:
        - exit_status: -1
          limit: 1
    commands: |
      curl -s "${test_url}" -o run_warehouse_tests.sh && bash run_warehouse_tests.sh snowflake

  # BigQuery
  - label: ":gcloud: Run Tests - BigQuery"
    key: "run_dbt_bigquery"
    retry:
      automatic:
        - exit_status: -1
          limit: 1
    commands: |
      curl -s "${test_url}" -o run_warehouse_tests.sh && bash run_warehouse_tests.sh bigquery

  # Redshift
  - label: ":amazon-redshift: Run Tests - Redshift"
    key: "run_dbt_redshift"
    retry:
      automatic:
        - exit_status: -1
          limit: 1
    concurrency: 3
    concurrency_group: "warehouse/redshift"
    commands: |
      curl -s "${test_url}" -o run_warehouse_tests.sh && bash run_warehouse_tests.sh redshift

  # Databricks
  - label: ":databricks: Run Tests - Databricks"
    key: "run_dbt_databricks"
    retry:
      automatic:
        - exit_status: -1
          limit: 1
    commands: |
      curl -s "${test_url}" -o run_warehouse_tests.sh && bash run_warehouse_tests.sh databricks
EOF

#     # Add optional Databricks SQL step
#     if [[ "$INCLUDE_DATABRICKS_SQL" == "true" ]]; then
#         cat >> /tmp/pipeline.yml <<EOF

#   # Databricks SQL (optional)
#   - label: ":databricks: :database: Run Tests - Databricks-sql"
#     key: "run_dbt_databricks_sql"
#     retry:
#       automatic:
#         - exit_status: -1
#           limit: 1
#     commands: |
#       curl -s "${test_url}" -o run_warehouse_tests.sh && bash run_warehouse_tests.sh databricks_sql
# EOF
#     fi

    # Add optional SQL Server step
    # Have to use python:3.10 image for SQL Server tests due to pyodbc compatibility issues with Python 3.11+
    if [[ "$INCLUDE_SQLSERVER" == "true" ]]; then
        cat >> /tmp/pipeline.yml <<EOF

  # SQL Server (optional)
  - label: ":azure: Run Tests - Sqlserver"
    key: "run_dbt_sqlserver"
    retry:
      automatic:
        - exit_status: -1
          limit: 1
    commands: |
      pyenv install -s 3.10
      eval "\$(pyenv init -)"
      pyenv shell 3.10
      python --version
      curl -s "${test_url}" -o run_warehouse_tests.sh && bash run_warehouse_tests.sh sqlserver
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