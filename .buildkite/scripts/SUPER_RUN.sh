#!/bin/bash
#
# SUPER_RUN.sh - Universal BuildKite CI Script
# Single entry point for all dbt package CI execution
#
# This script:
# 1. Reads repo-specific config to determine what warehouses to test
# 2. Sets up credentials from Google Cloud Secret Manager
# 3. Generates and uploads BuildKite pipeline dynamically
# 4. Each pipeline step runs dbt tests for specific warehouses
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
    local include_databricks_sql="${INCLUDE_DATABRICKS_SQL:-false}"
    local include_sqlserver="${INCLUDE_SQLSERVER:-false}"

    echo "Detecting warehouse configuration..."

    if [[ -f "$config_file" ]]; then
        echo "  - Found config file: $config_file"

        # Parse YAML file for warehouse settings
        if grep -q "^include_databricks_sql:" "$config_file"; then
            local yaml_databricks_sql=$(grep "^include_databricks_sql:" "$config_file" | sed 's/include_databricks_sql:[[:space:]]*//' | tr -d '"'"'"' | xargs)
            if [[ "$yaml_databricks_sql" == "true" ]]; then
                include_databricks_sql="true"
                echo "  - Found include_databricks_sql: true in $config_file"
            fi
        fi

        if grep -q "^include_sqlserver:" "$config_file"; then
            local yaml_sqlserver=$(grep "^include_sqlserver:" "$config_file" | sed 's/include_sqlserver:[[:space:]]*//' | tr -d '"'"'"' | xargs)
            if [[ "$yaml_sqlserver" == "true" ]]; then
                include_sqlserver="true"
                echo "  - Found include_sqlserver: true in $config_file"
            fi
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

    # Create pipeline steps dynamically
    local pipeline_steps=""

    # Standard warehouses (always included)
    local warehouses=("postgres" "snowflake" "bigquery" "redshift" "databricks")

    # Add optional warehouses based on config
    if [[ "$INCLUDE_DATABRICKS_SQL" == "true" ]]; then
        warehouses+=("databricks-sql")
    fi

    if [[ "$INCLUDE_SQLSERVER" == "true" ]]; then
        warehouses+=("sqlserver")
    fi

    echo "  - Will test warehouses: ${warehouses[*]}"

    # Generate pipeline YAML
    cat > /tmp/pipeline.yml <<EOF
steps:
EOF

    # Generate steps for each warehouse
    for warehouse in "${warehouses[@]}"; do
        local label_icon=""
        local concurrency_config=""

        case "$warehouse" in
            "postgres") label_icon=":postgres:" ;;
            "snowflake") label_icon=":snowflake-db:" ;;
            "bigquery") label_icon=":gcloud:" ;;
            "redshift")
                label_icon=":amazon-redshift:"
                concurrency_config="    concurrency: 3\n    concurrency_group: \"warehouse/redshift\""
                ;;
            "databricks") label_icon=":databricks:" ;;
            "databricks-sql") label_icon=":databricks: :database:" ;;
            "sqlserver") label_icon=":azure:" ;;
        esac

        cat >> /tmp/pipeline.yml <<EOF
  - label: "${label_icon} Run Tests - ${warehouse^}"
    key: "run_dbt_${warehouse//-/_}"
    retry:
      automatic:
        - exit_status: -1
          limit: 1
$(if [[ -n "$concurrency_config" ]]; then echo -e "$concurrency_config"; fi)
    plugins:
      - docker#v3.13.0:
          image: "python:3.13"
          shell: ["/bin/bash", "-e", "-c"]
          environment:
            - "BASH_ENV=/tmp/.bashrc"
            - "BUILDKITE_BUILD_NUMBER"
            - "BUILDKITE_COMMIT"
            - "BUILDKITE_STEP_KEY"
$(generate_warehouse_env_vars "$warehouse")
    commands: |
      # Setup credentials
      echo "Setting up credentials..."
      if ! curl -fsSL "${setup_url}" -o setup_credentials.sh; then
        echo "Failed to download setup_credentials.sh"
        exit 1
      fi
      if [[ ! -s setup_credentials.sh ]]; then
        echo "Downloaded setup_credentials.sh is empty"
        exit 1
      fi
      bash setup_credentials.sh

      # Run tests for this warehouse
      echo "Downloading warehouse test runner..."
      if ! curl -fsSL "${test_url}" -o run_warehouse_tests.sh; then
        echo "Failed to download run_warehouse_tests.sh"
        exit 1
      fi
      if [[ ! -s run_warehouse_tests.sh ]]; then
        echo "Downloaded run_warehouse_tests.sh is empty"
        exit 1
      fi
      bash run_warehouse_tests.sh "${warehouse}"

EOF
    done

    echo "Uploading pipeline to BuildKite..."
    buildkite-agent pipeline upload /tmp/pipeline.yml

    echo "Pipeline uploaded successfully"
}

generate_warehouse_env_vars() {
    local warehouse="$1"

    case "$warehouse" in
        "postgres")
            cat <<EOF
            - "CI_POSTGRES_DBT_HOST"
            - "CI_POSTGRES_DBT_USER"
            - "CI_POSTGRES_DBT_PASS"
            - "CI_POSTGRES_DBT_DBNAME"
EOF
            ;;
        "snowflake")
            cat <<EOF
            - "CI_SNOWFLAKE_DBT_ACCOUNT"
            - "CI_SNOWFLAKE_DBT_DATABASE"
            - "CI_SNOWFLAKE_DBT_PASS"
            - "CI_SNOWFLAKE_DBT_ROLE"
            - "CI_SNOWFLAKE_DBT_USER"
            - "CI_SNOWFLAKE_DBT_WAREHOUSE"
EOF
            ;;
        "bigquery")
            cat <<EOF
            - "GCLOUD_SERVICE_KEY"
EOF
            ;;
        "redshift")
            cat <<EOF
            - "CI_REDSHIFT_DBT_DBNAME"
            - "CI_REDSHIFT_DBT_HOST"
            - "CI_REDSHIFT_DBT_PASS"
            - "CI_REDSHIFT_DBT_USER"
EOF
            ;;
        "databricks"|"databricks-sql")
            if [[ "$warehouse" == "databricks-sql" ]]; then
                cat <<EOF
            - "CI_DATABRICKS_DBT_HOST"
            - "CI_DATABRICKS_SQL_DBT_HTTP_PATH"
            - "CI_DATABRICKS_SQL_DBT_TOKEN"
            - "CI_DATABRICKS_DBT_CATALOG"
EOF
            else
                cat <<EOF
            - "CI_DATABRICKS_DBT_HOST"
            - "CI_DATABRICKS_DBT_HTTP_PATH"
            - "CI_DATABRICKS_DBT_TOKEN"
            - "CI_DATABRICKS_DBT_CATALOG"
EOF
            fi
            ;;
        "sqlserver")
            cat <<EOF
            - "CI_SQLSERVER_DBT_SERVER"
            - "CI_SQLSERVER_DBT_DATABASE"
            - "CI_SQLSERVER_DBT_USER"
            - "CI_SQLSERVER_DBT_PASS"
EOF
            ;;
    esac
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    detect_warehouse_config
    generate_and_upload_pipeline

    echo "SUPER_RUN completed successfully!"
    echo "   Repository: $(basename "$PWD")"
    echo "   Warehouses: ${warehouses[*]:-"standard set"}"
    echo "   Pipeline uploaded and ready to execute"
}

# Execute main function
main "$@"