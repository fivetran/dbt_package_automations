# dbt Package Automations

Tooling used to support the development and maintenance of Fivetran dbt packages.

## Contents

This repository includes:

- **GitHub Actions workflows** (`/.github/workflows/`)
  - `auto-release.yml` – Automates GitHub release creation
  - `check-merge-ready.yml` – Reports a GitHub commit status based on whether the `merge:ready` label is applied to a pull request
  - `generate-docs.yml` – Generates and commits dbt documentation to PR branches, and reports a commit status indicating success or failure