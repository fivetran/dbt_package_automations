#!/usr/bin/env python3

"""
Stale bot script for marking and closing inactive GitHub issues and PRs.

Expected environment variables (passed from auto-stale.yml workflow):
  GITHUB_TOKEN     - GitHub API token (required)
  STALE_DAYS       - Days of inactivity before marking stale
  CLOSE_DAYS       - Days after stale before auto-closing issues
  STALE_MESSAGE    - Message template for stale notifications (required)
  CLOSE_MESSAGE    - Message template for close notifications (required)
  TEAM_MENTION     - Team to mention in messages (required)
  STALE_LABEL      - Label to apply to stale items (required)
  PINNED_LABEL     - Label that prevents stale marking (required)

Message templates support placeholders:
  {stale_days}     - Replaced with STALE_DAYS value
  {close_days}     - Replaced with CLOSE_DAYS value
  {pinned_label}   - Replaced with PINNED_LABEL value
"""

import json
import os
import sys
import time
from datetime import datetime, timedelta, timezone
import requests

OWNER = "fivetran"

# Labels and team mention are now required from environment variables

API = "https://api.github.com"

STALE_MARKER = "<!-- stale-bot:comment -->"
CLOSE_MARKER = "<!-- stale-bot:closed -->"

# Configuration constants
RATE_LIMIT_DELAY = 0.15  # seconds between API calls
MAX_ERROR_MSG_LENGTH = 300
DEFAULT_MAX_PAGES = 10
REQUEST_TIMEOUT = 30
PER_PAGE = 100

# Default message templates - these should match the YAML defaults
DEFAULT_STALE_MESSAGE = (
    "This has been automatically marked **stale** because there hasn't been activity for "
    "**{stale_days} days**.\n\n"
    "If this is still relevant, please add an update or apply **{pinned_label}**."
)

DEFAULT_CLOSE_MESSAGE = (
    "Closing this issue because it has been marked **stale** for "
    "**{close_days} days** with no activity.\n\n"
    "If this should stay open, please re-open and apply **{pinned_label}**."
)


# Get required environment variable or exit with error
def require_env(name):
    value = os.getenv(name)
    if not value:
        print(f"Missing required env var: {name}", file=sys.stderr)
        sys.exit(2)
    return value


# Get environment variable as integer or exit with error
def parse_int_env(name):
    value = require_env(name)
    try:
        return int(value)
    except Exception:
        print(f"Env var {name} must be an integer, got: {value}", file=sys.stderr)
        sys.exit(2)


# Parse ISO timestamp string into datetime object with UTC timezone
def parse_iso_timestamp(value):
    # Example: "2026-01-02T12:34:56Z"
    return datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)


# Extract and validate repository name from GITHUB_REPOSITORY environment variable
def get_repo_name():
    full = os.getenv("GITHUB_REPOSITORY")  # "owner/repo"
    if not full or "/" not in full:
        print("Missing or invalid GITHUB_REPOSITORY (expected 'owner/repo')", file=sys.stderr)
        sys.exit(2)

    owner, repo = full.split("/", 1)
    if owner.lower() != OWNER:
        print(f"This script only supports owner '{OWNER}' (got '{owner}')", file=sys.stderr)
        sys.exit(2)

    return repo


# Make HTTP request to GitHub API with proper authentication and error handling
def github_request(method, url, token, params=None, json_body=None):
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "mark-stale-bot",
    }

    resp = requests.request(
        method,
        url,
        headers=headers,
        params=params,
        json=json_body,
        timeout=REQUEST_TIMEOUT,
    )

    if not resp.ok:
        msg = ""
        try:
            msg = resp.json().get("message", "")
        except Exception:
            msg = (resp.text or "")[:MAX_ERROR_MSG_LENGTH]
        raise RuntimeError(f"{method} {url} -> {resp.status_code}: {msg}")

    if resp.status_code == 204:
        return None

    # Some endpoints can return an empty body
    if not resp.text or not resp.text.strip():
        return None

    return resp.json()


# Extract label names from GitHub issue/PR item into a set
def get_label_names(item):
    names = []
    for l in item.get("labels", []):
        if isinstance(l, dict) and l.get("name"):
            names.append(l["name"])
    return set(names)


# Fetch all open issues and PRs from the repository using pagination
def list_open_items(repo, token):
    # GET /issues returns both issues and PRs; PRs include "pull_request" key
    items = []
    page = 1
    while True:
        batch = github_request(
            "GET",
            f"{API}/repos/{OWNER}/{repo}/issues",
            token,
            params={
                "state": "open",
                "per_page": PER_PAGE,
                "page": page,
                "sort": "updated",
                "direction": "asc",
            },
        )
        if not batch:
            break

        items.extend(batch)
        page += 1
        time.sleep(RATE_LIMIT_DELAY)

    return items


# Fetch comments for a specific issue/PR using pagination with max page limit
def list_comments(repo, token, number, max_pages=DEFAULT_MAX_PAGES):
    comments = []
    page = 1
    while True:
        batch = github_request(
            "GET",
            f"{API}/repos/{OWNER}/{repo}/issues/{number}/comments",
            token,
            params={"per_page": PER_PAGE, "page": page},
        )
        if not batch:
            break

        comments.extend(batch)
        page += 1
        time.sleep(RATE_LIMIT_DELAY)

        if page > max_pages:
            break

    return comments


# Find the first comment containing the specified marker text
def find_marker_comment(comments, marker):
    for c in comments:
        body = c.get("body") or ""
        if marker in body:
            return c
    return None


# Add a label to an issue or PR
def add_label(repo, token, number, label):
    github_request(
        "POST",
        f"{API}/repos/{OWNER}/{repo}/issues/{number}/labels",
        token,
        json_body=[label],
    )


# Post a comment to an issue or PR
def post_comment(repo, token, number, body):
    github_request(
        "POST",
        f"{API}/repos/{OWNER}/{repo}/issues/{number}/comments",
        token,
        json_body={"body": body},
    )


# Close an issue or PR
def close_issue(repo, token, number):
    github_request(
        "PATCH",
        f"{API}/repos/{OWNER}/{repo}/issues/{number}",
        token,
        json_body={"state": "closed"},
    )


# Get @mention string for the author of an issue/PR
def get_author_mention(item):
    user = item.get("user") or {}
    login = user.get("login")
    if login:
        return f"@{login}"
    return ""


# Build mentions string for author and team
def build_mentions(item):
    mentions = []
    author = get_author_mention(item)
    if author:
        mentions.append(author)
    mentions.append(get_team_mention())
    return " ".join(mentions)


# Get required stale message template from environment
def get_stale_message_template():
    return require_env("STALE_MESSAGE")


# Get required close message template from environment
def get_close_message_template():
    return require_env("CLOSE_MESSAGE")


# Get required team mention from environment
def get_team_mention():
    return require_env("TEAM_MENTION")


# Get required stale label from environment
def get_stale_label():
    return require_env("STALE_LABEL")


# Get required pinned label from environment
def get_pinned_label():
    return require_env("PINNED_LABEL")


# Build the message text for marking an item as stale
def build_stale_message(item, stale_days):
    mentions = build_mentions(item)
    template = get_stale_message_template()

    header = f"{STALE_MARKER}\n"
    if mentions:
        header += f"{mentions}\n\n"

    # Use safe string replacement to prevent format string injection
    message_body = template.replace("{stale_days}", str(stale_days)).replace("{pinned_label}", get_pinned_label())
    return f"{header}{message_body}"


# Build the message text for closing a stale item
def build_close_message(item, close_days):
    mentions = build_mentions(item)
    template = get_close_message_template()

    header = f"{CLOSE_MARKER}\n"
    if mentions:
        header += f"{mentions}\n\n"

    # Use safe string replacement to prevent format string injection
    message_body = template.replace("{close_days}", str(close_days)).replace("{pinned_label}", get_pinned_label())
    return f"{header}{message_body}"


# Mark items as stale that haven't been updated recently
def mark_items_stale(items, repo, token, stale_cutoff, stale_days):
    stale_candidates = []
    for item in items:
        updated_at = parse_iso_timestamp(item["updated_at"])
        if updated_at < stale_cutoff:
            stale_candidates.append(item)

    print(f"{OWNER}/{repo}: {len(stale_candidates)} stale candidates / {len(items)} open items")

    for item in stale_candidates:
        number = item["number"]
        title = item.get("title", "")
        labels = get_label_names(item)

        if get_pinned_label() in labels:
            continue

        try:
            if get_stale_label() not in labels:
                add_label(repo, token, number, get_stale_label())

            comments = list_comments(repo, token, number)
            if not find_marker_comment(comments, STALE_MARKER):
                post_comment(repo, token, number, build_stale_message(item, stale_days))

        except Exception as e:
            print(f"Error marking stale on #{number} ({title}): {e}", file=sys.stderr)

        time.sleep(RATE_LIMIT_DELAY)


# Close issues that have been stale for too long
def close_stale_items(items, repo, token, close_cutoff, close_days):
    for item in items:
        number = item["number"]
        title = item.get("title", "")
        labels = get_label_names(item)

        # Issues only (not PRs)
        if "pull_request" in item:
            continue

        if get_pinned_label() in labels:
            continue

        if get_stale_label() not in labels:
            continue

        try:
            comments = list_comments(repo, token, number)
            stale_comment = find_marker_comment(comments, STALE_MARKER)

            # If it's labeled stale but missing our marker, don't auto-close it.
            if not stale_comment:
                continue

            stale_marked_at = parse_iso_timestamp(stale_comment["created_at"])
            if stale_marked_at < close_cutoff:
                if not find_marker_comment(comments, CLOSE_MARKER):
                    post_comment(repo, token, number, build_close_message(item, close_days))
                close_issue(repo, token, number)

        except Exception as e:
            print(f"Error auto-closing #{number} ({title}): {e}", file=sys.stderr)

        time.sleep(RATE_LIMIT_DELAY)


# Main function that orchestrates the stale bot workflow
def main():
    token = require_env("GITHUB_TOKEN")
    stale_days = parse_int_env("STALE_DAYS")
    close_days = parse_int_env("CLOSE_DAYS")

    repo = get_repo_name()

    now = datetime.now(timezone.utc)
    stale_cutoff = now - timedelta(days=stale_days)
    close_cutoff = now - timedelta(days=close_days)

    items = list_open_items(repo, token)

    # Phase 1: mark stale (issues + PRs)
    mark_items_stale(items, repo, token, stale_cutoff, stale_days)

    # Phase 2: auto-close (issues only)
    close_stale_items(items, repo, token, close_cutoff, close_days)

    return 0


if __name__ == "__main__":
    sys.exit(main())
