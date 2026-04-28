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
echo "🏗️  Build schema: ${BUILD_SCHEMA}"
echo "🧪 Running tests for warehouse: ${WAREHOUSE_TYPE}"

# Install system dependencies
sudo apt-get update
sudo apt-get install -y libsasl2-dev

# Setup Python virtual environment
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip setuptools

echo "📦 Installing dbt adapter for ${WAREHOUSE_TYPE}"

# Install warehouse-specific dbt adapter
case "$WAREHOUSE_TYPE" in
    "sqlserver")
        pip install -r integration_tests/requirements_sqlserver.txt

        # Install SQL Server ODBC driver
        curl -sSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor > /usr/share/keyrings/microsoft-prod.gpg
        curl -sSL https://packages.microsoft.com/config/debian/12/prod.list | sudo tee /etc/apt/sources.list.d/mssql-release.list

        sudo apt-get update
        ACCEPT_EULA=Y sudo apt-get install -y msodbcsql18
        ACCEPT_EULA=Y sudo apt-get install -y mssql-tools18
        echo 'export PATH="$PATH:/opt/mssql-tools18/bin"' >> ~/.bashrc
        source ~/.bashrc
        sudo apt-get -y install unixodbc-dev
        sudo apt-get update

        pip uninstall -y pyodbc
        pip install --no-cache-dir --no-binary :all: pyodbc==4.0.39
        ;;
    "snowflake")
        pip install "dbt-snowflake>=1.3.0,<2.0.0"
        ;;
    "bigquery")
        pip install "dbt-bigquery>=1.3.0,<2.0.0"
        ;;
    "postgres")
        pip install "dbt-postgres>=1.3.0,<2.0.0"
        ;;
    "redshift")
        pip install "dbt-redshift>=1.3.0,<2.0.0"
        ;;
    "databricks"|"databricks-sql")
        pip install "dbt-databricks>=1.3.0,<2.0.0"
        ;;
    *)
        echo "Using generic adapter installation for: dbt-${WAREHOUSE_TYPE}"
        pip install "dbt-${WAREHOUSE_TYPE}>=1.3.0,<2.0.0"
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
    echo "📥 Downloading test scenarios runner..."
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

echo "🐍 Downloading test scenarios runner..."
download_test_scenarios_runner

echo "🚀 Running test scenarios for ${WAREHOUSE_TYPE}..."
python3 run_test_scenarios.py "${WAREHOUSE_TYPE}" "${BUILD_SCHEMA}"

echo "✅ Tests completed successfully for ${WAREHOUSE_TYPE}!"