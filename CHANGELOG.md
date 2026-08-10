# dbt Package Automations Changelog

## v1.0.2 [2026-08-10]
- [PR #39](https://github.com/fivetran/dbt_package_automations/pull/39)

### Under the Hood
- Adds `check-docs-current.yml` workflow, which reports a `docs/generated` commit status on a pull request based on whether any docs-relevant files have changed since docs were last generated, and removes the `docs:ready` label if docs are stale.
- Updates `generate-docs.yml` to commit as `fivetran-data-model-bot` and report a `docs/generated` failure status and remove the `docs:ready` label if the generation job fails.

## v1.0.1 [2026-07-07]
- [PR #37](https://github.com/fivetran/dbt_package_automations/pull/37)

### Bug Fix
- Hardens `auto-release.yml` against several edge cases surfaced by real-world runs: multiline release notes were being collapsed to a single line (heredoc fix), release body construction could fail on special characters (switched to `jq -n`), version header matching was too broad (added end-of-line anchor), and first-ever releases errored on a null API response. Added explicit error handling and fallback boundary detection for changelog parsing.

### Under the Hood
- Bumps `actions/checkout` from v4 to v6. Improved inline comments throughout `auto-release.yml`.

## v1.0.0 [2026-05-27]
- [PR #33](https://github.com/fivetran/dbt_package_automations/pull/33)

### Under the Hood
- Removes all legacy shell-script and macro-based scaffolding tooling — the `generate_*` scripts, dbt macros, and `new_package_files` template set. The repo now contains only the GitHub Actions workflows.
