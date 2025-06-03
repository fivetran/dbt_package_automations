# Fivetran dbt Package Automations

<p align="left">
    <a alt="License"
        href="https://github.com/fivetran/dbt_package_automations/blob/main/LICENSE">
        <img src="https://img.shields.io/badge/License-Apache%202.0-blue.svg" /></a>
    <a alt="dbt-core">
        <img src="https://img.shields.io/badge/dbt_core-version_>=1.0.0_<2.0.0-orange.svg" /></a>
    <a alt="Maintained?">
        <img src="https://img.shields.io/badge/Maintained%3F-yes-green.svg" /></a>
    <a alt="PRs">
        <img src="https://img.shields.io/badge/Contributions-welcome-blueviolet" /></a>
</p>

## What does this dbt package do?
This package is a combination of macros, bash scripts, and python scripts that are used to help expedite and automate the package development process. See the **Contents** below for the automations available within this package.

## Who is the target user of this dbt package?
- You use dbt
- You are a member of the Fivetran dbt package team, or would like to expedite the package development process

## How do I use the dbt package?
### Step 1: Installing the Package
Include the following dbt_package_automations package version in your `packages.yml`
> Check [dbt Hub](https://hub.getdbt.com/) for the latest installation instructions, or [read the dbt docs](https://docs.getdbt.com/docs/package-management) for more information on installing packages.
```yaml
packages:
  - git: https://github.com/fivetran/dbt_package_automations.git
    revision: main
    warn-unpinned: false
```
### Step 2: Using the Automations
See the specific details for each macros within the contents below.
## 📋 Contents
### Automation Macros
- [Automation Macros](#automation-macros)
  - [generate_columns_macro](#generate_columns_macro-source)
  - [generate_docs](#generate_docs-source)
  - [get_column_names_only](#get_column_names_only-source)
  - [get_columns_for_macro](#get_columns_for_macro-source)
  - [staging_models_automation](#staging_models_automation-source)

### GitHub Actions Workflows
- [GitHub Actions Workflows](#github-actions-workflows)
  - [generate-docs](#generate-docs-source)

### Automation Macros
These macros provide the scripts to automate parts of the model creation.

#### staging_models_automation ([source](macros/staging_models_automation.sql))
This macro is intended to be used as a `run-operation` when generating Fivetran dbt package staging models and all around package framework creation. This macro will receive user input to create the necessary bash commands so they may all be ran at once. The output of this macro within the CLI will then be copied and pasted as a command to generate the staging models/macros.

Additionally, you can rerun this macro as it will create or replace what currently exists in the macro & model folders.

Things to note:

- This macro will only work if you have already included your src.yml file.
- Please double check your outputs as there may be timestamps & notes that are not relevant to the file.

**Usage:**
```bash
dbt run-operation staging_models_automation --args '{package: intercom, display_name: Intercom, source_schema: intercom_schema, source_database: intercom_database, tables: ["admin","company_history"]}'
```
**CLI Output:**
```bash
source dbt_packages/dbt_package_automations/kick_off_generator.sh  && 
source dbt_packages/dbt_package_automations/generate_source.sh '../dbt_intercom' intercom intercom_database intercom_schema '['admin', 'company_history']'  && 
source dbt_packages/dbt_package_automations/generate_columns.sh '../dbt_intercom' intercom intercom_database intercom_schema admin && 
source dbt_packages/dbt_package_automations/generate_columns.sh '../dbt_intercom' intercom intercom_database intercom_schema company_history && 
source dbt_packages/dbt_package_automations/generate_models.sh '../dbt_intercom' intercom intercom_database intercom_schema admin && 
source dbt_packages/dbt_package_automations/generate_models.sh '../dbt_intercom' intercom intercom_database intercom_schema company_history && 
source dbt_packages/dbt_package_automations/generate_docs_md.sh '../dbt_intercom' intercom intercom_database intercom_schema 'admin","company_history'  && 
source dbt_packages/dbt_package_automations/generate_files.sh intercom 'Intercom'  && 
source dbt_packages/dbt_package_automations/edit_dbt_project_yml.sh intercom 'admin,company_history'  && 
source dbt_packages/dbt_package_automations/edit_integrations_project_yml.sh intercom 'admin,company_history' 
```
**Args:**
* `package`         (required): Name of the package for which you are creating staging models/macros.
* `display_name`    (required): Display name of the package for which you are creating that will be used mainly in the README generation.
* `source_schema`   (required): Name of the source_schema from which the bash command will query.
* `source_database` (required): Name of the source_database from which the bash command will query.
* `tables`          (required): List of the tables for which you want to create staging models/macros.

#### generate_columns_macro ([source](macros/generate_columns_macro.sql))
This macro is used to generate the macro used as an argument within the [fill_staging_columns](https://github.com/fivetran/dbt_fivetran_utils#fill_staging_columns-source) macro which will list all the expected columns within a respective table. The macro output will contain `name` and `datatype`; however, you may add an optional argument for `alias` if you wish to rename the column within the macro. 

The macro should be run using dbt's `run-operation` functionality, as used below. It will print out the macro text, which can be copied and pasted into the relevant `macro` directory file within the package.

**Usage:**
```
dbt run-operation dbt_package_automations.generate_columns_macro --args '{"table_name": "promoted_tweet_report", "schema_name": "twitter_ads", "database_name": "intercom_database"}'
```
**Output:**
```sql
{% macro get_admin_columns() %}

{% set columns = [
    {"name": "email", "datatype": dbt_utils.type_string()},
    {"name": "id", "datatype": dbt_utils.type_string(), "alias": "admin_id"},
    {"name": "job_title", "datatype": dbt_utils.type_string()},
    {"name": "name", "datatype": dbt_utils.type_string()},
    {"name": "_fivetran_deleted", "datatype": "boolean"},
    {"name": "_fivetran_synced", "datatype": dbt_utils.type_timestamp()}
] %}

{{ return(columns) }}

{% endmacro %}
```
**Args:**
* `table_name`    (required): Name of the schema which the table you are running the macro for resides in.
* `schema_name`   (required): Name of the schema which the table you are running the macro for resides in.
* `database_name` (optional): Name of the database which the table you are running the macro for resides in. If empty, the macro will default this value to `target.database`.

----
#### generate_docs ([source](macros/generate_docs.sql))
This macro will generate a `source` command that leverages `generate_docs.sh` to do the following:
- seeds, runs and creates documentation for integration tests models
- moves `catalog.json`, `index.html`, `manifest.json` and `run_results.json` into a `<project_name>/docs` folder. 
When the source script is ran, this feature will remove existing files in the `<project_name>/docs` if any exists. 

**Requirements:**
- This script assumes that you are running in a directory that is adjacent to your project. For example, say you are working on dbt_apple_search_ads. You may run the macro & the source command from the CLI Output within your dev directory below. 
```bash
├── apple_search_ads
│   ├── dbt_apple_search_ads
│   ├── dbt_apple_search_ads_source
│   └── dev
```
- Make sure your integration_test profiles in `~/.dbt/profiles.yml` is set for the appropriate project name.

**Usage:**
```bash
dbt run-operation generate_docs --args '{package: apple_search_ads_source}'
```
**CLI Output:**
```bash
source dbt_packages/dbt_package_automations/generate_docs.sh '../dbt_apple_search_ads_source'
```
**Args:**
* `package` (required): Name of the package; include whether package is source or not

----
----
#### get_column_names_only ([source](macros/get_column_names_only.sql))
This macro is used in the `generate_models.sh` script to further the `staging_models_automation` macro. This macro outputs all columns from the specified table, allowing `generate_models.sh` to prefill column fields in the final select statement.

Note this will retain the timestamp from the built-in formatting update from dbt 1.0.0. Therefore in the staging model resulting from `generate_models.sh`, you will need to manually delete the timestamp.

**Usage:**
```bash
dbt run-operation get_column_names_only --args '{table_name: log, schema_name: fivetran_log, database_name: database-name' 

```
**CLI Output:**
```bash
14:41:40      _fivetran_synced,
    connector_id,
    event,
    id,
    message_data,
    message_event,
    process_id,
    sequence_number,
    sync_id,
    time_stamp,
    transformation_id

```
**Args:**
* `table_name`    (required): Name of the table you are wanting to return column names and datatypes.
* `schema_name`   (required): Name of the schema where the above mentioned table resides.
* `database_name` (optional): Name of the database where the above mentioned schema and table reside. By default this will be your target.database.

----
#### get_columns_for_macro ([source](macros/get_columns_for_macro.sql))
This macro returns all column names and datatypes for a specified table within a database and is used as part of the [generate_columns_macro](macros/generate_columns_macro.sql).

**Usage:**
```sql
{{ fivetran_utils.get_columns_for_macro(table_name="team", schema_name="my_teams", database_name="my_database") }}
```
**Args:**
* `table_name`    (required): Name of the table you are wanting to return column names and datatypes.
* `schema_name`   (required): Name of the schema where the above mentioned table resides.
* `database_name` (optional): Name of the database where the above mentioned schema and table reside. By default this will be your target.database.

----

### Bash Scripts
#### generate_columns.sh ([source](generate_columns.sh))

This bash file can be used to setup or update packages to use the `fill_staging_columns` macro above. The bash script does the following:

* Creates a `.sql` file in the `macros` directory for a source table and fills it with all the columns from the table.
    * Be sure your `dbt_project.yml` file does not contain any **Warnings** or **Errors**. If warnings or errors are present, the messages from the terminal will be printed above the macro within the `.sql` file in the `macros` directory.

The usage is as follows, assuming you are executing via a `zsh` terminal and in a dbt project directory that has already imported this repo as a dependency:
```bash
source dbt_packages/dbt_package_automations/generate_columns.sh "path/to/directory" file_prefix database_name schema_name table_name
```

As an example, assuming we are in a dbt project in an adjacent folder to `dbt_apple_search_ads_source`:
```bash
source dbt_packages/dbt_package_automations/generate_columns.sh '../dbt_apple_search_ads_source' stg_apple_search_ads intercom_database apple_search_ads campaign_history
```

In that example, it will:
* Create a `get_campaign_history_columns.sql` file in the `macros` directory, with the necessary macro within it.

----
#### generate_docs.sh([source](generate_docs.sh))
This bash file can be used to create or replace package documentation (`<project_name>/docs`). 

**Requirements:**
- This script assumes that you are running in a directory that is adjacent to your project. For example, say you are working on dbt_apple_search_ads. You may run the the source command within your dev directory below. 
```bash
├── apple_search_ads
│   ├── dbt_apple_search_ads
│   ├── dbt_apple_search_ads_source
│   └── dev 
```
- Make sure your integration_test profiles in `~/.dbt/profiles.yml` is set for the appropriate project name.

**Usage:**
```bash
source dbt_packages/dbt_package_automations/generate_docs.sh '../dbt_apple_search_ads_source'
```
The bash script does the following:
- seeds, runs and creates documentation for integration tests models
- moves `catalog.json`, `index.html`, `manifest.json` and `run_results.json` into a `<project_name>/docs` folder. 

----
#### generate_models.sh ([source](generate_models.sh))

This bash file can be used to setup or update packages to use the `generate_models` macro above. The bash script assumes that there already exists a macro directory with all relevant `get_<table_name>_columns.sql` files created. The bash script does the following:

* Creates a `..._tmp.sql` file in the `models/tmp` directory and fills it with a `select * from {{ var('table_name') }}` where `table_name` is the name of the source table.
* Creates or updates a `.sql` file in the `models` directory and fills it with the filled out version of the `fill_staging_columns` macro as shown above. You can then write whatever SQL you want around the macro to finishing off the staging file.

```bash
source dbt_packages/dbt_package_automations/generate_models.sh "path/to/directory" file_prefix database_name schema_name table_name
```

As an example, assuming we are in a dbt project in an adjacent folder to `dbt_apple_search_ads_source`:
```bash
source dbt_packages/dbt_package_automations/generate_models.sh '../dbt_apple_search_ads_source' stg_apple_search_ads intercom_database apple_search_ads campaign_history
```

With the above example, the script will:
* Create a `stg_apple_search_ads__campaign_history_tmp.sql` file in the `models/tmp` directory, with `select * from {{ var('campaign_history') }}` in it.
* Create or update a `stg_apple_search_ads__campaign_history.sql` file in the `models` directory with the pre-filled out `fill_staging_columns` macro.

### GitHub Actions Workflows
#### generate-docs ([source](.github/workflows/generate-docs.yml))

This reusable GitHub Actions workflow generates dbt documentation (`catalog.json`, `manifest.json`, `index.html`) based on the integration tests project and commits it to the associated PR branch.

It runs when a PR is labeled with `docs:ready` and:
- Spins up a temporary Postgres instance using Docker
- Seeds and runs the dbt
- Automatically toggles doc-specific variables in `dbt_project.yml` using tags:
  - `@docs-include`: uncommented during doc generation
  - `@docs-ignore`: commented out during doc generation
- Copies the generated docs into the root `/docs` folder
- Commits the updated docs back to the PR branch

**Usage in the package repo:**
```yml
name: 'generate dbt docs'
on:
  pull_request:
    types:
      - labeled

jobs:
  generate-docs:
    if: github.event.label.name == 'docs:ready'
    uses: fivetran/dbt_package_automations/.github/workflows/generate-docs.yml@main
    with:
      schema_var_name: <name of the package's schema variable>
    secrets: inherit
```

## How is this package maintained and can I contribute?
### Package Maintenance
The Fivetran team maintaining this package _only_ maintains the latest version of the package. We highly recommend you stay consistent with the [latest version](https://hub.getdbt.com/fivetran/package_automations/latest/) of the package and refer to the [CHANGELOG](https://github.com/fivetran/dbt_package_automations/blob/main/CHANGELOG.md) and release notes for more information on changes across versions.

### Contributions
A small team of analytics engineers at Fivetran develops these dbt packages. However, the packages are made better by community contributions.

We highly encourage and welcome contributions to this package. Check out [this dbt Discourse article](https://discourse.getdbt.com/t/contributing-to-a-dbt-package/657) on the best workflow for contributing to a package.

## Are there any resources available?
- If you have questions or want to reach out for help, see the [GitHub Issue](https://github.com/fivetran/dbt_package_automations/issues/new/choose) section to find the right avenue of support for you.
- If you would like to provide feedback to the dbt package team at Fivetran or would like to request a new dbt package, fill out our [Feedback Form](https://www.surveymonkey.com/r/DQ7K7WW).