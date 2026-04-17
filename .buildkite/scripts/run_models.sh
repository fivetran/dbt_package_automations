#!/bin/bash

set -euo pipefail

# =============================================================================
# BUILD SETUP - Schema generation and authentication
# =============================================================================

# Generate unique schema name for this build
BUILD_NUMBER="${BUILDKITE_BUILD_NUMBER:-0}"
COMMIT_SHA=$(echo "${BUILDKITE_COMMIT:-unknown}" | cut -c1-7)

# Add databricks-specific identifier for SQL warehouse to differentiate from all purpose cluster
if [[ "${BUILDKITE_STEP_KEY:-}" == "run_dbt_databricks_sql" ]]; then
    BUILD_SCHEMA=$(echo "zz_bk_integration_tests_sql_${COMMIT_SHA}_${BUILD_NUMBER}" | cut -c1-63 | sed 's/_$//')
else
    BUILD_SCHEMA=$(echo "zz_bk_integration_tests_${COMMIT_SHA}_${BUILD_NUMBER}" | cut -c1-63 | sed 's/_$//')
fi

export BUILD_SCHEMA
echo "Build schema: ${BUILD_SCHEMA}"

# Download centralized profiles file
mkdir -p ~/.dbt
curl -f -s -o ~/.dbt/profiles.yml \
    "https://raw.githubusercontent.com/fivetran/dbt_package_automations/refs/heads/feature/buildkite-scripts/.buildkite/scripts/sample.profiles.yml"
echo "Downloaded centralized profiles configuration"

# Export secrets only for the warehouse needed by this step
echo "Step key: ${BUILDKITE_STEP_KEY:-unknown}"
echo "Build number: ${BUILDKITE_BUILD_NUMBER:-unknown}"
echo "Commit: ${BUILDKITE_COMMIT:-unknown}"

case "${BUILDKITE_STEP_KEY:-}" in
    "run_dbt_bigquery")
        echo "Setting up BigQuery credentials and dependencies"
        export GCLOUD_SERVICE_KEY=$(gcloud secrets versions access latest --secret="GCLOUD_SERVICE_KEY" --project="dbt-package-testing-363917")
        ;;
    "run_dbt_postgres")
        echo "Setting up PostgreSQL credentials and dependencies"
        export CI_POSTGRES_DBT_HOST=$(gcloud secrets versions access latest --secret="CI_POSTGRES_DBT_HOST" --project="dbt-package-testing-363917")
        export CI_POSTGRES_DBT_USER=$(gcloud secrets versions access latest --secret="CI_POSTGRES_DBT_USER" --project="dbt-package-testing-363917")
        export CI_POSTGRES_DBT_PASS=$(gcloud secrets versions access latest --secret="CI_POSTGRES_DBT_PASS" --project="dbt-package-testing-363917")
        export CI_POSTGRES_DBT_DBNAME=$(gcloud secrets versions access latest --secret="CI_POSTGRES_DBT_DBNAME" --project="dbt-package-testing-363917")
        ;;
    "run_dbt_redshift")
        echo "Setting up Redshift credentials and dependencies"
        export CI_REDSHIFT_DBT_DBNAME=$(gcloud secrets versions access latest --secret="CI_REDSHIFT_DBT_DBNAME" --project="dbt-package-testing-363917")
        export CI_REDSHIFT_DBT_HOST=$(gcloud secrets versions access latest --secret="CI_REDSHIFT_DBT_HOST" --project="dbt-package-testing-363917")
        export CI_REDSHIFT_DBT_PASS=$(gcloud secrets versions access latest --secret="CI_REDSHIFT_DBT_PASS" --project="dbt-package-testing-363917")
        export CI_REDSHIFT_DBT_USER=$(gcloud secrets versions access latest --secret="CI_REDSHIFT_DBT_USER" --project="dbt-package-testing-363917")
        ;;
    "run_dbt_snowflake")
        echo "Setting up Snowflake credentials and dependencies"
        export CI_SNOWFLAKE_DBT_ACCOUNT=$(gcloud secrets versions access latest --secret="CI_SNOWFLAKE_DBT_ACCOUNT" --project="dbt-package-testing-363917")
        export CI_SNOWFLAKE_DBT_DATABASE=$(gcloud secrets versions access latest --secret="CI_SNOWFLAKE_DBT_DATABASE" --project="dbt-package-testing-363917")
        export CI_SNOWFLAKE_DBT_PASS=$(gcloud secrets versions access latest --secret="CI_SNOWFLAKE_DBT_PASS" --project="dbt-package-testing-363917")
        export CI_SNOWFLAKE_DBT_ROLE=$(gcloud secrets versions access latest --secret="CI_SNOWFLAKE_DBT_ROLE" --project="dbt-package-testing-363917")
        export CI_SNOWFLAKE_DBT_USER=$(gcloud secrets versions access latest --secret="CI_SNOWFLAKE_DBT_USER" --project="dbt-package-testing-363917")
        export CI_SNOWFLAKE_DBT_WAREHOUSE=$(gcloud secrets versions access latest --secret="CI_SNOWFLAKE_DBT_WAREHOUSE" --project="dbt-package-testing-363917")
        ;;
    "run_dbt_databricks")
        echo "Setting up Databricks credentials and dependencies"
        export CI_DATABRICKS_DBT_HOST=$(gcloud secrets versions access latest --secret="CI_DATABRICKS_DBT_HOST" --project="dbt-package-testing-363917")
        export CI_DATABRICKS_DBT_HTTP_PATH=$(gcloud secrets versions access latest --secret="CI_DATABRICKS_DBT_HTTP_PATH" --project="dbt-package-testing-363917")
        export CI_DATABRICKS_DBT_TOKEN=$(gcloud secrets versions access latest --secret="CI_DATABRICKS_DBT_TOKEN" --project="dbt-package-testing-363917")
        export CI_DATABRICKS_DBT_CATALOG=$(gcloud secrets versions access latest --secret="CI_DATABRICKS_DBT_CATALOG" --project="dbt-package-testing-363917")
        ;;
    *)
        echo "⚠️  WARNING: Unknown step key '${BUILDKITE_STEP_KEY:-}' - no credentials fetched"
        echo "Available step keys: run_dbt_bigquery, run_dbt_postgres, run_dbt_redshift, run_dbt_snowflake, run_dbt_databricks"
        ;;
esac

# =============================================================================
# TESTING EXECUTION - Dependencies and dbt testing
# =============================================================================

echo "Installing system dependencies..."
apt-get update
apt-get install libsasl2-dev

echo "Setting up Python environment..."
python3 -m venv venv
. venv/bin/activate
pip install --upgrade pip setuptools

# Install specific adapter for this database
echo "Installing dbt adapter: dbt-${1}"
pip install "dbt-${1}>=1.3.0,<2.0.0"

cd integration_tests

# Fetch central test scenario script
mkdir -p ../.buildkite/scripts
curl -f -s -o ../.buildkite/scripts/run_test_scenarios.py \
    "https://raw.githubusercontent.com/fivetran/dbt_package_automations/refs/heads/feature/buildkite-scripts/.buildkite/scripts/run_test_scenarios.py"

# Run test scenarios using Python script (includes deps, seed, compile)
# Test parameters and scenarios are configured in: integration_tests/ci/test_scenarios.yml
echo "Executing dbt tests for ${1} with schema ${BUILD_SCHEMA}..."
python3 ../.buildkite/scripts/run_test_scenarios.py "${1}" "${BUILD_SCHEMA}"

echo "Tests completed successfully"
