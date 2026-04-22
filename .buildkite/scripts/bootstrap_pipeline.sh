#!/usr/bin/env bash
set -euo pipefail

echo "Central pipeline bootstrap starting..."
echo "ENABLED_WAREHOUSES=${ENABLED_WAREHOUSES:-}"

TMP_PIPELINE="$(mktemp)"

cat > "$TMP_PIPELINE" <<'YAML'
env:
  RUN_MODELS_URL: "https://raw.githubusercontent.com/fivetran/dbt_package_automations/refs/heads/feature/centralized-bk/.buildkite/scripts/run_models.sh"

steps:
  - label: ":bug: Debug Environment Variables"
    key: "debug_env"
    command: |
      echo "=== Environment Variables Debug ==="
      echo "ENABLED_WAREHOUSES: ${ENABLED_WAREHOUSES:-'(not set)'}"
      echo "BUILDKITE_BUILD_NUMBER: ${BUILDKITE_BUILD_NUMBER:-'(not set)'}"
      echo "BUILDKITE_COMMIT: ${BUILDKITE_COMMIT:-'(not set)'}"
      echo "BUILDKITE_STEP_KEY: ${BUILDKITE_STEP_KEY:-'(not set)'}"
      echo "=================================="
YAML

if [[ "${ENABLED_WAREHOUSES:-}" == *postgres* ]]; then
  cat >> "$TMP_PIPELINE" <<'YAML'
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
    command: |
      curl -s "${RUN_MODELS_URL}" | bash -s postgres
YAML
fi

if [[ "${ENABLED_WAREHOUSES:-}" == *snowflake* ]]; then
  cat >> "$TMP_PIPELINE" <<'YAML'
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
    command: |
      curl -s "${RUN_MODELS_URL}" | bash -s snowflake
YAML
fi

if [[ "${ENABLED_WAREHOUSES:-}" == *bigquery* ]]; then
  cat >> "$TMP_PIPELINE" <<'YAML'
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
    command: |
      curl -s "${RUN_MODELS_URL}" | bash -s bigquery
YAML
fi

if [[ "${ENABLED_WAREHOUSES:-}" == *redshift* ]]; then
  cat >> "$TMP_PIPELINE" <<'YAML'
  - label: ":amazon-redshift: Run Tests - Redshift"
    key: "run_dbt_redshift"
    concurrency: 3
    concurrency_group: "warehouse/redshift"
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
    command: |
      curl -s "${RUN_MODELS_URL}" | bash -s redshift
YAML
fi

if [[ "${ENABLED_WAREHOUSES:-}" == *databricks* ]]; then
  cat >> "$TMP_PIPELINE" <<'YAML'
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
    command: |
      curl -s "${RUN_MODELS_URL}" | bash -s databricks
YAML
fi

if [[ "${ENABLED_WAREHOUSES:-}" == *databricks_sql* ]]; then
  cat >> "$TMP_PIPELINE" <<'YAML'
  - label: ":databricks: :database: Run Tests - Databricks SQL"
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
    command: |
      curl -s "${RUN_MODELS_URL}" | bash -s databricks-sql
YAML
fi

if [[ "${ENABLED_WAREHOUSES:-}" == *sqlserver* ]]; then
  cat >> "$TMP_PIPELINE" <<'YAML'
  - label: ":azure: Run Tests - SQL Server"
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
    command: |
      curl -s "${RUN_MODELS_URL}" | bash -s sqlserver
YAML
fi

echo "--- Generated pipeline ---"
cat "$TMP_PIPELINE"

buildkite-agent pipeline upload "$TMP_PIPELINE"