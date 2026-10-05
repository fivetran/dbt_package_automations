# dbt Package Automations

Tooling used to support the development and maintenance of Fivetran dbt packages.

## Contents

This repository includes:

- **GitHub Actions workflows** (`/.github/workflows/`)
  - `auto-release.yml` – Automates GitHub release creation
  - `check-docs-current.yml` – Checks three things on every PR push: docs regenerated, `CHANGELOG.md` updated, and a `.changes/*.yml` entry present. Reports a single `docs/generated` commit status naming specifically which of the three are missing, and removes the `docs:ready` label if any are stale
  - `generate-docs.yml` – When the `docs:ready` label is applied, generates dbt documentation **and** runs the changelog update (see below) in one job, committing both to the PR branch in a single push. Reports a `docs/generated` failure status and removes the `docs:ready` label if either step fails

## Changelog generation

Adding the `docs:ready` label to a PR also renders a pending `.changes/*.yml` file into that
package's `CHANGELOG.md` (via `.github/scripts/update_changelog.py`), instead of `CHANGELOG.md`
being hand-written. One YAML file per release lives in a package repo's `.changes/` directory;
the file is picked up automatically once its `version` isn't yet reflected in `CHANGELOG.md`, so
authors don't need to name it anything special or flag which one is "pending."

The script resyncs `CHANGELOG.md` from `origin/main` before writing, so re-running it (relabel,
retry, manual dispatch) is idempotent rather than stacking duplicate entries. `.changes/*.yml`
files are kept for 45 days after being rendered, then pruned automatically.

### `.changes/*.yml` field reference

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `version` | string | Yes | e.g. `1.3.2`. Determines the filename convention (`.changes/1.3.2.yml`) and is used to detect whether this release is already in `CHANGELOG.md`. |
| `pr_number` | integer | No | Renders the `[PR #N](url) includes the following updates:` line, and is the default PR link for every contributor unless they set their own. |
| `is_breaking` | boolean | No | Appends `(--full-refresh required after upgrading)` to the Schema/Data Change heading. |
| `date` | string | No — set automatically | Stamped onto the file by the pipeline the first time it runs. Don't set this yourself. |
| `schema_data_changes.entries` | list | No | Each entry: `models` (list of model name strings), `change_type`, `old`, `new`, `notes`, `is_breaking` (per-entry — controls whether that row is sorted first and tagged `(Breaking)`). Renders as a summary table. |
| `new_features`, `bug_fixes`, `under_the_hood` | list | No | Each item is either a plain string, or an object with `description` (required), `title` (optional, bolded lead-in), and `details` (optional list, rendered as indented sub-bullets). |
| `dependencies` | list | No | Each item is either a plain string, or `{package, old_version, new_version, description}` — renders as `Bumps \`package\` from X to Y — description`. |
| `contributors` | list | No | Each item is either a bare GitHub handle string, or `{name, github_handle, contribution, pr_number}`. `pr_number` here overrides the release-level one, for a contributor credited via a different PR. |

**Fields accepted but not used by changelog rendering:** `hide_from_docs` (on any item in
`new_features`, `bug_fixes`, `dependencies`, `under_the_hood`, `schema_data_changes.entries`, or
`contributors`) and `is_breaking` on an individual `dependencies` item. These are intentionally
inert here — they're reserved for a future docs-generation consumer of this same YAML, not for
`CHANGELOG.md` rendering.