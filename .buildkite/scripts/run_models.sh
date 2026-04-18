#!/bin/bash

set -euo pipefail

# Install system dependencies
apt-get update
apt-get install libsasl2-dev

# Setup Python virtual environment
python3 -m venv venv
. venv/bin/activate
pip install --upgrade pip setuptools

echo "Installing dbt adapter: dbt-${1}"
if [ "$1" == "sqlserver" ]; then
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
elif [ "$1" == "databricks-sql" ]; then
    pip install "dbt-databricks>=1.3.0,<2.0.0"
else
    # Install specific adapter for this database
    pip install "dbt-${1}>=1.3.0,<2.0.0"
fi

# Setup dbt configuration
mkdir -p ~/.dbt
curl -f -s -o ~/.dbt/profiles.yml \
    "https://raw.githubusercontent.com/fivetran/dbt_package_automations/refs/heads/feature/buildkite-scripts/.buildkite/scripts/sample.profiles.yml"

cd integration_tests

# Fetch central test scenario script
mkdir -p ../.buildkite/scripts
curl -f -s -o ../.buildkite/scripts/run_test_scenarios.py \
    "https://raw.githubusercontent.com/fivetran/dbt_package_automations/refs/heads/feature/buildkite-scripts/.buildkite/scripts/run_test_scenarios.py"

# Run test scenarios using Python script (includes deps, seed, compile)
# Test parameters and scenarios are configured in: integration_tests/ci/test_scenarios.yml
python3 ../.buildkite/scripts/run_test_scenarios.py "${1}" "${BUILD_SCHEMA}"
