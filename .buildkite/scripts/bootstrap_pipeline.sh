#!/usr/bin/env bash
set -euo pipefail

WAREHOUSES="${ENABLED_WAREHOUSES:-}"

cat > .buildkite/pipeline.yml <<'YAML'
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

if [[ "$WAREHOUSES" == *postgres* ]]; then
  cat >> .buildkite/pipeline.yml <<'YAML'
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
YAML
fi

if [[ "$WAREHOUSES" == *snowflake* ]]; then
  cat >> .buildkite/pipeline.yml <<'YAML'
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
YAML
fi