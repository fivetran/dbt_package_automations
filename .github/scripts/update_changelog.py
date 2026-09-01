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
import re
import subprocess
from datetime import date, timedelta
from pathlib import Path

import yaml

CHANGES_DIR = Path(".changes")
CONFIG_PATH = CHANGES_DIR / "config.yaml"
CHANGELOG_PATH = Path("CHANGELOG.md")
RETENTION_DAYS = 30

DEFAULT_SECTION_HEADINGS = {
    "schema_data_changes": "Schema/Data Change",
    "new_features": "Feature Update",
    "bug_fixes": "Bug Fix",
    "dependencies": "Dependency Updates",
    "under_the_hood": "Under the Hood",
    "contributors": "Contributors",
}

VERSION_HEADER_RE = re.compile(r"^#+\s.*\bv\d+(\.\d+)*\b")


def load_config() -> dict:
    """Load .changes/config.yaml (package, repo_url, section headings).

    Falls back to GITHUB_REPOSITORY and the default headings above when the
    file is missing or a field is unset, so this still works before a repo
    has added its own config.
    """
    config = yaml.safe_load(CONFIG_PATH.read_text()) if CONFIG_PATH.exists() else {}
    config = config or {}

    repo_env = os.environ.get("GITHUB_REPOSITORY", "fivetran/dbt_package_automations")
    config.setdefault("package", repo_env.split("/")[-1])
    config.setdefault("repo_url", f"https://github.com/{repo_env}")

    headings = dict(DEFAULT_SECTION_HEADINGS)
    for section in config.get("sections") or []:
        key, heading = section.get("key"), section.get("heading")
        if key and heading:
            headings[key] = heading
    config["headings"] = headings

    return config


def render_bullets(items: list) -> list[str]:
    """Render a list of changelog items as bullets, with optional nested sub-bullets.

    Each item is either a plain string, or an object with:
      description (required): the bullet text
      title (optional): bolded lead-in, e.g. "- **Title**: description"
      details (optional): a list of strings rendered as indented sub-bullets
    """
    lines = []
    for item in items:
        if isinstance(item, str):
            item = {"description": item}
        title = item.get("title")
        description = item.get("description", "")
        lines.append(f"- **{title}**: {description}" if title else f"- {description}")
        for detail in item.get("details") or []:
            lines.append(f"  - {detail}")
    return lines


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
        if f"v{version}" not in changelog_text:
            return path
    return None


def normalize_dependency(item) -> dict:
    """A dependency is either a plain string, or a structured bump record:
    {package, old_version, new_version, description, is_breaking, hide_from_docs}.
    Structured records render as "Bumps `package` from X to Y — description".
    """
    if isinstance(item, str):
        return {"description": item}

    package = item.get("package")
    old_version = item.get("old_version")
    new_version = item.get("new_version")
    description = item.get("description", "")

    if package and old_version and new_version:
        text = f"Bumps `{package}` from {old_version} to {new_version}"
        if description:
            text += f" — {description}"
    else:
        text = description

    return {"description": text, "details": item.get("details")}


def render_contributor_bullets(contributors: list, pr_number, repo_url: str) -> list[str]:
    """A contributor is either a bare GitHub handle, or a structured record:
    {name, github_handle, is_fivetran, contribution, hide_from_docs}.
    """
    lines = []
    for contributor in contributors:
        if isinstance(contributor, str):
            contributor = {"github_handle": contributor}

        handle = (contributor.get("github_handle") or "").lstrip("@")
        line = f"- [@{handle}](https://github.com/{handle})" if handle else "-"
        if pr_number:
            line += f" ([PR #{pr_number}]({repo_url}/pull/{pr_number}))"

        suffix = ": ".join(part for part in [contributor.get("name"), contributor.get("contribution")] if part)
        if suffix:
            line += f" — {suffix}"

        lines.append(line)
    return lines


def render_markdown(entry: dict, config: dict) -> str:
    version = entry.get("version", "0.0.0")
    pr_number = (entry.get("pr") or {}).get("number")
    headings = config["headings"]
    repo_url = config["repo_url"]

    lines = [f"# {config['package']} v{version}", ""]
    if pr_number:
        lines.append(f"[PR #{pr_number}]({repo_url}/pull/{pr_number}) includes the following updates:")
        lines.append("")

    schema_entries = (entry.get("schema_data_changes") or {}).get("entries") or []
    if schema_entries:
        header = f"## {headings['schema_data_changes']}"
        if entry.get("is_breaking"):
            header += " (--full-refresh required after upgrading)"
        lines.append(header)

        breaking_count = sum(1 for item in schema_entries if item.get("is_breaking"))
        change_word = "change" if len(schema_entries) == 1 else "changes"
        breaking_word = "change" if breaking_count == 1 else "changes"
        lines.append(f"**{len(schema_entries)} total {change_word} • {breaking_count} possible breaking {breaking_word}**")
        lines.append("")
        lines.append("| Data Model(s) | Change type | Old | New | Notes |")
        lines.append("| ------------- | ----------- | --- | --- | ----- |")

        # Breaking changes must be listed first.
        for item in sorted(schema_entries, key=lambda e: not e.get("is_breaking")):
            models = ", ".join(m.get("name", "") for m in item.get("models") or [])
            if item.get("is_breaking"):
                models = f"{models} (Breaking)" if models else "Breaking"
            lines.append(
                f"| {models} | {item.get('change_type', '')} | {item.get('old') or ''} "
                f"| {item.get('new') or ''} | {item.get('notes') or ''} |"
            )
        lines.append("")

    new_features = entry.get("new_features") or []
    if new_features:
        lines.append(f"## {headings['new_features']}")
        lines.extend(render_bullets(new_features))
        lines.append("")

    bug_fixes = entry.get("bug_fixes") or []
    if bug_fixes:
        lines.append(f"## {headings['bug_fixes']}")
        lines.extend(render_bullets(bug_fixes))
        lines.append("")

    dependencies = entry.get("dependencies") or []
    if dependencies:
        lines.append(f"## {headings['dependencies']}")
        lines.extend(render_bullets([normalize_dependency(item) for item in dependencies]))
        lines.append("")

    under_the_hood = entry.get("under_the_hood") or []
    if under_the_hood:
        lines.append(f"## {headings['under_the_hood']}")
        lines.extend(render_bullets(under_the_hood))
        lines.append("")

    contributors = entry.get("contributors") or []
    if contributors:
        lines.append(f"## {headings['contributors']}")
        lines.extend(render_contributor_bullets(contributors, pr_number, repo_url))
        lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def prepend_to_changelog(rendered: str) -> None:
    existing = CHANGELOG_PATH.read_text() if CHANGELOG_PATH.exists() else ""
    lines = existing.splitlines(keepends=True)

    # Skip past a genuine document title (a leading '#' line with no version
    # number, e.g. "# Package Changelog") and any blank lines after it, but
    # stop immediately at the first line that looks like a release header
    # (e.g. "# dbt_amazon_ads v1.3.1" or "## v1.0.2 [date]") so the new entry
    # lands above it rather than inside it.
    insert_at = 0
    while insert_at < len(lines) and lines[insert_at].startswith("#") and not VERSION_HEADER_RE.match(lines[insert_at]):
        insert_at += 1
    while insert_at < len(lines) and lines[insert_at].strip() == "":
        insert_at += 1

    new_lines = lines[:insert_at] + [rendered, "\n"] + lines[insert_at:]
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

    rendered = render_markdown(entry, load_config())
    prepend_to_changelog(rendered)

    enforce_retention()


if __name__ == "__main__":
    main()
