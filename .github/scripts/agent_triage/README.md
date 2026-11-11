# Agent triage (POC)

An agent does a first-pass review of a PR when a maintainer adds the `agent:run` label.
It reads the PR as text, asks Claude for a structured review, and drafts a comment.
A maintainer approves the draft before it is posted. See [RULES.md](RULES.md) for what
the agent checks.

## How it works

1. A maintainer adds `agent:run` to a PR.
2. The `analyze` job reads the PR through the GitHub API with a read-only token. It never
   checks out or runs the PR's code.
3. The script applies the scope gate. Large or sensitive PRs skip the model and are labeled
   `needs-human-review`.
4. Claude reviews the PR text. It has no tools and must return JSON that matches a fixed
   schema.
5. The script builds the comment from a template. It strips links, HTML, and @mentions
   from the model's text.
6. The draft appears in the run's job summary and, if configured, in Slack.
7. The `post` job waits for a maintainer to approve the `agent-triage-approval`
   environment. It then posts the comment and applies labels from an allowlist.

The contributor sees a one-line summary and one verdict: ready to merge, a short list of
up to three small updates, or a note that a maintainer will review it directly. Version bump
recommendations and internal notes appear only in the job summary and Slack.

## Setup for a package repo

1. **Secret `PKG_REVIEW_TOKEN`.** This holds the Anthropic API key. Store it as an
   organization secret shared with the package repos, or as a repository secret for the
   pilot. Use a dedicated key in its own Anthropic workspace with a spend limit.
2. **Optional secret `AGENT_TRIAGE_SLACK_WEBHOOK_URL`.** A Slack incoming webhook for the
   channel that should get the "draft ready" ping.
3. **Environment `agent-triage-approval`.** In the repo's Settings > Environments, create
   it and add the maintainers as required reviewers. Without required reviewers, the
   comment posts without waiting.
4. **Caller workflow.** Add `.github/workflows/agent-triage.yml`:

   ```yaml
   on:
     pull_request_target:
       types: [labeled]
   permissions:
     contents: read
     pull-requests: write
     issues: write
   jobs:
     triage:
       if: github.event.label.name == 'agent:run'
       uses: fivetran/dbt_package_automations/.github/workflows/agent-triage.yml@main
       secrets: inherit
   ```

5. **Actions setting.** In Settings > Actions > General, require approval for workflows
   from outside contributors.

## Run it locally

Use Python 3.10 or later.

```bash
pip install anthropic pydantic
export ANTHROPIC_API_KEY=...   # never commit this
python .github/scripts/agent_triage/triage.py local --repo fivetran/dbt_amazon_ads --pr 53 --out-dir /tmp/triage
```

This prints the maintainer summary and writes `comment.md`, `labels.txt`, and
`slack.json` to the output folder. It posts nothing.
