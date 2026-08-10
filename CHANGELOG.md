# dbt Package Automations Changelog

## v1.0.2 [2026-08-07]
- [PR #38](https://github.com/fivetran/dbt_package_automations/pull/38)

### Under the Hood
- Added `check-merge-ready.yml` workflow that checks for the `merge:ready` label on a pull request and reports the result as a GitHub commit status (`label/merge-ready`).
- Updated `generate-docs.yml` to post a `docs/generated` commit status after the docs generation job completes, indicating whether docs were successfully generated and committed.

## v1.0.1 [2026-07-07]
- [PR #37](https://github.com/fivetran/dbt_package_automations/pull/37)

### Bug Fix
- Hardened `auto-release.yml` against several edge cases surfaced by real-world runs: multiline release notes were being collapsed to a single line (heredoc fix), release body construction could fail on special characters (switched to `jq -n`), version header matching was too broad (added end-of-line anchor), and first-ever releases errored on a null API response. Added explicit error handling and fallback boundary detection for changelog parsing.

### Under the Hood
- Bumped `actions/checkout` from v4 to v6. Improved inline comments throughout `auto-release.yml`.

## v1.0.0 [2026-05-27]
- [PR #33](https://github.com/fivetran/dbt_package_automations/pull/33)

### Under the Hood
- Removed all legacy shell-script and macro-based scaffolding tooling — the `generate_*` scripts, dbt macros, and `new_package_files` template set. The repo now contains only the GitHub Actions workflows.
