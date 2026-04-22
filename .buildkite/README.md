# Centralized Buildkite Infrastructure

This directory contains the centralized buildkite infrastructure for all Fivetran dbt packages.

## 🏗️ **Architecture**

- **Dynamic pipeline loading**: Packages load the centralized pipeline at runtime
- **One-line per package**: Each package has a 1-line pipeline.yml
- **Zero duplication**: All logic lives in this centralized repository
- **Instant updates**: Pipeline changes apply to all packages immediately

## 📁 **Files**

### Core Infrastructure
- `scripts/run_models.sh` - Main script that handles adapter installation, dbt setup, and test execution
- `scripts/run_test_scenarios.py` - Python script that runs test scenarios from YAML configuration
- `scripts/sample.profiles.yml` - dbt profiles template for all warehouses
- `pipeline.yml` - Template pipeline configuration

## 🚀 **Setting Up a New Package**

To use this centralized infrastructure in a new dbt package:

### 1. Create Minimal Files

**Create `.buildkite/pipeline.yml` with test configuration:**
```yaml
env:
  # Configure which warehouse tests to run (true/false)
  TEST_POSTGRES: true
  TEST_SNOWFLAKE: true
  TEST_BIGQUERY: true
  TEST_REDSHIFT: false
  TEST_DATABRICKS: false
  TEST_DATABRICKS_SQL: false
  TEST_SQLSERVER: false

steps:
  - label: ":gear: Load Central Pipeline"
    key: "load_pipeline"
    command: |
      # Download the centralized pipeline definition
      curl -f -s https://raw.githubusercontent.com/fivetran/dbt_package_automations/main/.buildkite/pipeline.yml \
        | buildkite-agent pipeline upload  # Upload and replace current pipeline
```

**Copy test scenarios template:**
```bash
cp new_package_files/integration_tests/ci/test_scenarios.yml YOUR_PACKAGE/integration_tests/ci/
```

### 2. Configure Tests

**Update test flags in `.buildkite/pipeline.yml`:**
```yaml
# Set to true to enable tests, false to disable
TEST_POSTGRES: true           # Enable PostgreSQL testing
TEST_SNOWFLAKE: true          # Enable Snowflake testing  
TEST_BIGQUERY: false          # Disable BigQuery testing
TEST_REDSHIFT: false          # Disable Redshift testing
TEST_DATABRICKS: false        # Disable Databricks testing
TEST_DATABRICKS_SQL: false    # Disable Databricks SQL testing
TEST_SQLSERVER: false         # Disable SQL Server testing
```

**Available test targets:**
- `TEST_POSTGRES` - PostgreSQL
- `TEST_SNOWFLAKE` - Snowflake
- `TEST_BIGQUERY` - Google BigQuery  
- `TEST_REDSHIFT` - Amazon Redshift
- `TEST_DATABRICKS` - Databricks
- `TEST_DATABRICKS_SQL` - Databricks SQL Warehouse
- `TEST_SQLSERVER` - SQL Server

### 3. Configure Test Scenarios

**Update `integration_tests/ci/test_scenarios.yml`:**
- Set `schema_variable_name` to your package's schema variable (e.g., `"amazon_ads_schema"`)
- Define test scenarios specific to your package

### 3. Configure Buildkite Environment
Ensure your Buildkite pipeline has the `BUILD_SCHEMA` environment variable set (used for schema isolation).

### 4. That's it! 
Your package now uses the centralized buildkite infrastructure with ultimate simplicity.

## 🔧 **How It Works**

1. **Buildkite triggers** your package's 1-line pipeline.yml
2. **Pipeline downloads** ONLY the central pipeline.yml (single file)
3. **Pipeline uploads** the centralized pipeline, replacing itself
4. **Centralized pipeline runs** with all warehouse steps
5. **run_models.sh downloads** the full .buildkite folder when needed (SVN checkout)
6. **Script installs** the appropriate dbt adapter for the warehouse
7. **Python script reads** your package's test_scenarios.yml
8. **Tests run** for each scenario and warehouse combination

## ✅ **Benefits**

- **True minimal download**: SVN checkout gets ONLY .buildkite folder
- **Zero duplication**: All logic lives in this repository
- **Instant updates**: Change centralized pipeline, all packages updated immediately
- **No maintenance**: Packages never need pipeline updates
- **Consistent behavior**: Impossible for packages to drift apart
- **Easy onboarding**: Copy one line, create test scenarios, done

## 🛠️ **Maintenance**

To update the infrastructure:
1. Update scripts in this directory
2. All packages automatically use the updated infrastructure
3. No need to update individual packages

## 📋 **Adapter Support**

Currently supported adapters:
- PostgreSQL
- Snowflake  
- BigQuery
- Redshift
- Databricks
- SQL Server (with special requirements handling)

To add a new adapter, update the adapter installation logic in `scripts/run_models.sh`.