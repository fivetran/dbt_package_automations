#!/usr/bin/env bash
set -euo pipefail

INCLUDE_DATABRICKS_SQL="${INCLUDE_DATABRICKS_SQL:-false}"
INCLUDE_SQLSERVER="${INCLUDE_SQLSERVER:-false}"

cat > .buildkite/pipeline.yml <<'YAML'
env:
  RUN_MODELS_URL: "https://raw.githubusercontent.com/fivetran/dbt_package_automations/refs/heads/feature/centralized-bk/.buildkite/scripts/run_models.sh"

steps:
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
    commands: |
      curl -s "${RUN_MODELS_URL}" | bash -s postgres

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
    commands: |
      curl -s "${RUN_MODELS_URL}" | bash -s snowflake

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
    commands: |
      curl -s "${RUN_MODELS_URL}" | bash -s bigquery

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
    commands: |
      curl -s "${RUN_MODELS_URL}" | bash -s redshift

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
    commands: |
      curl -s "${RUN_MODELS_URL}" | bash -s databricks
YAML

if [[ "$INCLUDE_DATABRICKS_SQL" == "true" ]]; then
  cat >> .buildkite/pipeline.yml <<'YAML'
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
    commands: |
      curl -s "${RUN_MODELS_URL}" | bash -s databricks-sql
YAML
fi

if [[ "$INCLUDE_SQLSERVER" == "true" ]]; then
  cat >> .buildkite/pipeline.yml <<'YAML'
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
    commands: |
      curl -s "${RUN_MODELS_URL}" | bash -s sqlserver
YAML
fi