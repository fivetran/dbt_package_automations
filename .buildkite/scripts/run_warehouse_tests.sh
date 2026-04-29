#!/bin/bash
#
# run_warehouse_tests.sh - Execute dbt tests for a specific warehouse
#
# Usage: ./run_warehouse_tests.sh <warehouse_type>
# Example: ./run_warehouse_tests.sh postgres
#

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <warehouse_type>"
    echo "Supported warehouses: postgres, snowflake, bigquery, redshift, databricks, databricks-sql, sqlserver"
    exit 1
fi

WAREHOUSE_TYPE="$1"

# Generate unique schema name for this build
BUILD_NUMBER="${BUILDKITE_BUILD_NUMBER:-1}"
COMMIT_SHA="${BUILDKITE_COMMIT:0:7}"
PREFIX="zz_bk_integration_tests"
BUILD_SCHEMA="${PREFIX}_${COMMIT_SHA}_${BUILD_NUMBER}_${WAREHOUSE_TYPE}"

export BUILD_SCHEMA
echo "Build schema: ${BUILD_SCHEMA}"
echo "Running tests for warehouse: ${WAREHOUSE_TYPE}"

# Setup database credentials from Secret Manager
echo "Setting up database credentials..."
setup_credentials() {
    local secrets=(
        "GCLOUD_SERVICE_KEY"
        "CI_POSTGRES_DBT_HOST"
        "CI_POSTGRES_DBT_USER"
        "CI_POSTGRES_DBT_PASS"
        "CI_POSTGRES_DBT_DBNAME"
        "CI_REDSHIFT_DBT_DBNAME"
        "CI_REDSHIFT_DBT_HOST"
        "CI_REDSHIFT_DBT_PASS"
        "CI_REDSHIFT_DBT_USER"
        "CI_SNOWFLAKE_DBT_ACCOUNT"
        "CI_SNOWFLAKE_DBT_DATABASE"
        "CI_SNOWFLAKE_DBT_PASS"
        "CI_SNOWFLAKE_DBT_ROLE"
        "CI_SNOWFLAKE_DBT_USER"
        "CI_SNOWFLAKE_DBT_WAREHOUSE"
        "CI_DATABRICKS_DBT_HOST"
        "CI_DATABRICKS_DBT_HTTP_PATH"
        "CI_DATABRICKS_DBT_TOKEN"
        "CI_DATABRICKS_DBT_CATALOG"
        "CI_DATABRICKS_SQL_DBT_HTTP_PATH"
        "CI_DATABRICKS_SQL_DBT_TOKEN"
        "CI_SQLSERVER_DBT_SERVER"
        "CI_SQLSERVER_DBT_DATABASE"
        "CI_SQLSERVER_DBT_USER"
        "CI_SQLSERVER_DBT_PASS"
    )

    for secret in "${secrets[@]}"; do
        export "$secret"="$(gcloud secrets versions access latest --secret="$secret" --project="dbt-package-testing-363917")"
    done
}

# Setup credentials
setup_credentials
echo "✅ Database credentials configured"

# Install system dependencies
sudo apt-get update
sudo apt-get install -y libsasl2-dev

# Setup Python virtual environment
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip setuptools

# Get dbt adapter version from test scenarios config
get_adapter_version() {
    local warehouse_type="$1"
    local config_file="integration_tests/ci/test_scenarios.yml"
    local default_version=">=1.3.0,<2.0.0"

    if [[ -f "$config_file" ]]; then
        local version=$(python3 -c "
import subprocess, sys
try:
    subprocess.check_call([sys.executable, '-m', 'pip', 'install', '--quiet', 'PyYAML'],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    import yaml
    with open('$config_file', 'r') as f:
        config = yaml.safe_load(f) or {}
    versions = config.get('dbt_adapter_versions', {})
    print(versions.get('$warehouse_type', '$default_version'))
except Exception:
    print('$default_version')
")
        echo "$version"
    else
        echo "$default_version"
    fi
}

DBT_VERSION=$(get_adapter_version "$WAREHOUSE_TYPE")
echo "Installing dbt adapter for ${WAREHOUSE_TYPE} (${DBT_VERSION})"

# Install warehouse-specific dbt adapter
case "$WAREHOUSE_TYPE" in
      "sqlserver")
        pip install -r integration_tests/requirements_sqlserver.txt

        curl -sSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /usr/share/keyrings/microsoft-prod.gpg
        curl -sSL https://packages.microsoft.com/config/debian/12/prod.list > /etc/apt/sources.list.d/mssql-release.list

        apt-get update
        ACCEPT_EULA=Y apt-get install -y msodbcsql18
        ACCEPT_EULA=Y apt-get install -y mssql-tools18
        echo 'export PATH="$PATH:/opt/mssql-tools18/bin"' >> ~/.bashrc
        source ~/.bashrc
        apt-get -y install unixodbc-dev
        apt-get update

        pip uninstall -y pyodbc
        pip install --no-cache-dir --no-binary :all: pyodbc==4.0.39

        # odbcinst -j
        ;;
    "snowflake")
        pip install "dbt-snowflake${DBT_VERSION}"
        ;;
    "bigquery")
        pip install "dbt-bigquery${DBT_VERSION}"
        ;;
    "postgres")
        pip install "dbt-postgres${DBT_VERSION}"
        ;;
    "redshift")
        pip install "dbt-redshift${DBT_VERSION}"
        ;;
    "databricks"|"databricks_sql")
        pip install "dbt-databricks${DBT_VERSION}"
        ;;
    *)
        echo "Using generic adapter installation for: dbt-${WAREHOUSE_TYPE}"
        pip install "dbt-${WAREHOUSE_TYPE}${DBT_VERSION}"
        ;;
esac

# Create dbt profiles configuration
create_dbt_profiles() {
    mkdir -p ~/.dbt
    cat > ~/.dbt/profiles.yml <<'PROFILES'
integration_tests:
  target: redshift
  outputs:
    redshift:
      type: redshift
      host: "{{ env_var('CI_REDSHIFT_DBT_HOST') }}"
      user: "{{ env_var('CI_REDSHIFT_DBT_USER') }}"
      pass: "{{ env_var('CI_REDSHIFT_DBT_PASS') }}"
      dbname: "{{ env_var('CI_REDSHIFT_DBT_DBNAME') }}"
      port: 5439
      schema: "{{ env_var('BUILD_SCHEMA') }}"
      threads: 8
    bigquery:
      type: bigquery
      method: service-account-json
      project: 'dbt-package-testing'
      schema: "{{ env_var('BUILD_SCHEMA') }}"
      threads: 8
      keyfile_json: "{{ env_var('GCLOUD_SERVICE_KEY') | as_native }}"
    snowflake:
      type: snowflake
      account: "{{ env_var('CI_SNOWFLAKE_DBT_ACCOUNT') }}"
      user: "{{ env_var('CI_SNOWFLAKE_DBT_USER') }}"
      password: "{{ env_var('CI_SNOWFLAKE_DBT_PASS') }}"
      role: "{{ env_var('CI_SNOWFLAKE_DBT_ROLE') }}"
      database: "{{ env_var('CI_SNOWFLAKE_DBT_DATABASE') }}"
      warehouse: "{{ env_var('CI_SNOWFLAKE_DBT_WAREHOUSE') }}"
      schema: "{{ env_var('BUILD_SCHEMA') }}"
      threads: 8
    postgres:
      type: postgres
      host: "{{ env_var('CI_POSTGRES_DBT_HOST') }}"
      user: "{{ env_var('CI_POSTGRES_DBT_USER') }}"
      pass: "{{ env_var('CI_POSTGRES_DBT_PASS') }}"
      port: 5432
      dbname: "{{ env_var('CI_POSTGRES_DBT_DBNAME') }}"
      schema: "{{ env_var('BUILD_SCHEMA') }}"
      threads: 8
    databricks:
      type: databricks
      catalog: "{{ env_var('CI_DATABRICKS_DBT_CATALOG') }}"
      schema: "{{ env_var('BUILD_SCHEMA') }}"
      host: "{{ env_var('CI_DATABRICKS_DBT_HOST') }}"
      http_path: "{{ env_var('CI_DATABRICKS_DBT_HTTP_PATH') }}"
      token: "{{ env_var('CI_DATABRICKS_DBT_TOKEN') }}"
      threads: 8
    databricks_sql:
      type: databricks
      catalog: "{{ env_var('CI_DATABRICKS_DBT_CATALOG') }}"
      schema: "{{ env_var('BUILD_SCHEMA') }}"
      host: "{{ env_var('CI_DATABRICKS_DBT_HOST') }}"
      http_path: "{{ env_var('CI_DATABRICKS_SQL_DBT_HTTP_PATH') }}"
      token: "{{ env_var('CI_DATABRICKS_SQL_DBT_TOKEN') }}"
      threads: 8
    sqlserver:
      type: sqlserver
      server: "{{ env_var('CI_SQLSERVER_DBT_SERVER') }}"
      database: "{{ env_var('CI_SQLSERVER_DBT_DATABASE') }}"
      schema: "{{ env_var('BUILD_SCHEMA') }}"
      authentication: sql
      user: "{{ env_var('CI_SQLSERVER_DBT_USER') }}"
      password: "{{ env_var('CI_SQLSERVER_DBT_PASS') }}"
      driver: 'ODBC Driver 18 for SQL Server'
      threads: 8
      encrypt: true
      trust_cert: true
PROFILES
}

# Download test scenarios runner from central location
download_test_scenarios_runner() {
    if ! curl -fsSL \
        "https://raw.githubusercontent.com/fivetran/dbt_package_automations/test/superscript/.buildkite/scripts/run_test_scenarios.py" \
        -o run_test_scenarios.py; then
        echo "❌ Failed to download test scenarios runner"
        exit 1
    fi
    if [[ ! -s run_test_scenarios.py ]]; then
        echo "❌ Downloaded run_test_scenarios.py is empty"
        exit 1
    fi
    chmod +x run_test_scenarios.py
}

echo "⚙️  Setting up dbt configuration..."
create_dbt_profiles

echo "🔄 Entering integration tests directory..."
cd integration_tests

echo "Downloading test scenarios runner..."
download_test_scenarios_runner

echo "Running test scenarios for ${WAREHOUSE_TYPE}..."
python3 run_test_scenarios.py "${WAREHOUSE_TYPE}" "${BUILD_SCHEMA}"

echo "✅ Tests completed successfully for ${WAREHOUSE_TYPE}!"