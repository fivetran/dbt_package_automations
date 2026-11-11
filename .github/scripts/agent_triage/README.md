# Agent triage (POC)

When a maintainer adds the `agent:triage` label to a PR, an agent gives it a first-pass
verdict: ready to go, minor revisions (posted as one-click suggestions where possible), or full human review.
[RULES.md](RULES.md) says how it decides.

## How it works

1. The `analyze` job reads the PR through the GitHub API with a read-only token. It never
   checks out or runs the PR's code.
2. Large or sensitive PRs skip Claude and get `agent:skipped`. When Claude reviews a PR
   and recommends a person look at it, the label is `agent:human-review` instead.
3. Claude gets the PR as text, with no tools, and must return JSON in a fixed format.
4. The script builds the comment from a template, strips links, HTML, and @mentions, and
   can only make Claude's verdict more cautious.
5. The `post` job, as the Fivetran bot, skips everything if new commits arrived during the
   review. Otherwise it:
   - points a fork PR that targets `main` at a new branch `external/pr-<number>` off `main`
   - posts the comment and one verdict label
   - posts minor revisions as one-click suggestions where it can
6. A new push removes the verdict label, since it no longer applies.

Only someone with write access can start a run. The job summary is public on public
repos, so it holds only the verdict and Claude's raw answer, nothing sensitive.

## Setup for a package repo

1. Make two secrets available to the repo: `PKG_REVIEW_TOKEN` (the Anthropic API key,
   ideally a dedicated key with a spend limit) and `GH_TOKEN` (the Fivetran bot token).
2. Add `.github/workflows/agent-triage.yml`. Pin `uses:` and `automations_ref` to the same
   release tag or commit:

   ```yaml
   on:
     pull_request_target:
       types: [labeled, synchronize]
   permissions:
     contents: read
     pull-requests: read
   jobs:
     triage:
       if: github.event.action == 'synchronize' || github.event.label.name == 'agent:triage'
       uses: fivetran/dbt_package_automations/.github/workflows/agent-triage.yml@<tag>
       with:
         automations_ref: <tag>
       secrets:
         PKG_REVIEW_TOKEN: ${{ secrets.PKG_REVIEW_TOKEN }}
         GH_TOKEN: ${{ secrets.GH_TOKEN }}
   ```

## Run it locally

Needs Python 3.10 or later, `gh` signed in, and `ANTHROPIC_API_KEY` set. It posts nothing.

```bash
pip install anthropic pydantic
python .github/scripts/agent_triage/triage.py --repo fivetran/dbt_amazon_ads --pr 60 --out-dir /tmp/triage
```

Set `TRIAGE_MODEL` to try another model.

## Test it

[evals/cases.yml](evals/cases.yml) holds mock PRs grouped by customer impact, each with
the verdicts that count as a pass. Run them after any change to RULES.md, the script, or
the model:

```bash
python .github/scripts/agent_triage/evals/run_evals.py --repeat 3
```

- **Wrong approvals** must be 0: the bot said ready to go on something it shouldn't.
- **Low-impact PRs approved** shows how often it approves the ones it should.
- `--offline` runs only the free checks (comment safety, suggestion rules, scope gate).
  A full run with `--repeat 3` costs about $0.65 on Sonnet.

To add a case, copy a block in `cases.yml` and set `allow` (or `gate: true`).
