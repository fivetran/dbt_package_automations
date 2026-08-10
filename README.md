# dbt Package Automations

Tooling used to support the development and maintenance of Fivetran dbt packages.

## Contents

This repository includes:

- **GitHub Actions workflows** (`/.github/workflows/`)
  - `auto-release.yml` – Automates GitHub release creation
  - `check-docs-current.yml` – Reports a `docs/generated` commit status based on whether docs-relevant files have changed since docs were last generated, and removes the `docs:ready` label if docs are stale
  - `generate-docs.yml` – Generates and commits dbt documentation to PR branches, and reports a `docs/generated` failure status and removes the `docs:ready` label if generation fails