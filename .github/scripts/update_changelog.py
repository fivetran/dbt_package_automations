#!/usr/bin/env python3
"""POC: render a single working YAML changelog entry into a Markdown block
and prepend it to CHANGELOG.md.

Convention:
- One YAML file per release, living in .changes/.
- The action stamps `date` onto that file the first time it runs -
  authors don't set it themselves.
- Only the past month of dated release files are retained; older ones
  are pruned automatically.
- Every run resyncs CHANGELOG.md from origin/main before appending, and
  skips a release whose version header is already present there. This
  keeps re-runs (relabel, retry, manual dispatch) idempotent instead of
  stacking duplicate entries on top of a stale branch copy.
"""
from __future__ import annotations

import os
import subprocess
from datetime import date, timedelta
from pathlib import Path

import yaml

CHANGES_DIR = Path(".changes")
CHANGELOG_PATH = Path("CHANGELOG.md")
RETENTION_DAYS = 30

REPO = os.environ.get("GITHUB_REPOSITORY", "fivetran/dbt_package_automations")


def fetch_main_changelog() -> str:
    try:
        result = subprocess.run(
            ["git", "show", "origin/main:CHANGELOG.md"],
            capture_output=True,
            text=True,
            check=True,
        )
        return result.stdout
    except subprocess.CalledProcessError:
        return CHANGELOG_PATH.read_text() if CHANGELOG_PATH.exists() else "# Changelog\n"


def discover_pending_yaml(changelog_text: str) -> Path | None:
    candidates = sorted(CHANGES_DIR.glob("*.yaml"))
    for path in candidates:
        entry = yaml.safe_load(path.read_text()) or {}
        version = entry.get("version")
        if not version:
            continue
        if f"## v{version} [" not in changelog_text:
            return path
    return None


def render_markdown(entry: dict) -> str:
    version = entry.get("version", "0.0.0")
    pr_number = (entry.get("pr") or {}).get("number")
    entry_date = entry.get("date", date.today().isoformat())

    header = f"## v{version} [{entry_date}]"
    if entry.get("is_breaking"):
        header += " (Breaking Change)"
    lines = [header]
    if pr_number:
        lines.append(f"- [PR #{pr_number}](https://github.com/{REPO}/pull/{pr_number})")
    lines.append("")

    schema_entries = (entry.get("schema_data_changes") or {}).get("entries") or []
    if schema_entries:
        lines.append("### Schema/Data Change")
        for item in schema_entries:
            lines.append(f"- {item}")
        lines.append("")

    new_features = entry.get("new_features") or []
    if new_features:
        lines.append("### Feature Update")
        for feature in new_features:
            title = feature.get("title", "")
            description = feature.get("description", "")
            lines.append(f"- **{title}**: {description}" if title else f"- {description}")
        lines.append("")

    bug_fixes = entry.get("bug_fixes") or []
    if bug_fixes:
        lines.append("### Bug Fix")
        for fix in bug_fixes:
            lines.append(f"- {fix.get('description', '')}")
        lines.append("")

    dependencies = entry.get("dependencies") or []
    if dependencies:
        lines.append("### Dependency Update")
        for item in dependencies:
            lines.append(f"- {item}")
        lines.append("")

    under_the_hood = entry.get("under_the_hood") or []
    if under_the_hood:
        lines.append("### Under the Hood")
        for item in under_the_hood:
            lines.append(f"- {item}")
        lines.append("")

    contributors = entry.get("contributors") or []
    if contributors:
        formatted = ", ".join(c if c.startswith("@") else f"@{c}" for c in contributors)
        lines.append(f"Thanks to {formatted} for the contribution!")
        lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def prepend_to_changelog(rendered: str) -> None:
    existing = CHANGELOG_PATH.read_text() if CHANGELOG_PATH.exists() else "# Changelog\n"
    lines = existing.splitlines(keepends=True)

    # Insert after the title/header (first line(s) starting with a single '#'),
    # and any immediately following blank lines, above the first existing entry.
    insert_at = 0
    while insert_at < len(lines) and lines[insert_at].startswith("# "):
        insert_at += 1
    while insert_at < len(lines) and lines[insert_at].strip() == "":
        insert_at += 1

    new_lines = lines[:insert_at] + ["\n", rendered, "\n"] + lines[insert_at:]
    CHANGELOG_PATH.write_text("".join(new_lines))


def enforce_retention(days: int = RETENTION_DAYS) -> None:
    cutoff = date.today() - timedelta(days=days)
    for path in CHANGES_DIR.glob("*.yaml"):
        entry = yaml.safe_load(path.read_text()) or {}
        entry_date = entry.get("date")
        if not entry_date:
            continue
        try:
            parsed_date = date.fromisoformat(entry_date)
        except ValueError:
            continue
        if parsed_date < cutoff:
            path.unlink()


def main() -> None:
    # Resync from main first so a re-run always starts from the canonical
    # CHANGELOG.md, not whatever this branch happened to accumulate before.
    changelog_text = fetch_main_changelog()
    CHANGELOG_PATH.write_text(changelog_text)

    yaml_path = discover_pending_yaml(changelog_text)
    if yaml_path is None:
        print("Nothing to add — every .changes/*.yaml version is already in CHANGELOG.md.")
        enforce_retention()
        return

    entry = yaml.safe_load(yaml_path.read_text()) or {}
    entry.setdefault("date", date.today().isoformat())
    yaml_path.write_text(yaml.safe_dump(entry, sort_keys=False))

    rendered = render_markdown(entry)
    prepend_to_changelog(rendered)

    enforce_retention()


if __name__ == "__main__":
    main()
