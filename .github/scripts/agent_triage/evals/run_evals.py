"""Repeatable tests for the agent triage verdict.

Runs the mock PRs in cases.yml through the same scope gate, Claude call, and verdict rules
as the real workflow, without touching GitHub. Also checks that the comment renderer
neutralizes hostile model output (no API calls for that part).

  python run_evals.py                 # all cases, once each
  python run_evals.py --repeat 3      # run each Claude case 3 times to check consistency
  python run_evals.py --only out-join-type
  python run_evals.py --offline       # renderer checks only, free

Needs ANTHROPIC_API_KEY unless --offline. Exits 1 on any wrong approval or failed check.
"""

import argparse
import re
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import yaml

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE.parent))
import triage  # noqa: E402

READY = "ready_to_go"


def to_pr(case: dict, repo_paths: list) -> dict:
    files = []
    for f in case["files"]:
        patch = f.get("patch")
        lines = sum(1 for l in (patch or "").splitlines() if l[:1] in "+-" and not l.startswith(("+++", "---")))
        files.append({"path": f["path"], "old_path": f.get("old_path"), "status": f.get("status", "modified"),
                      "lines": lines, "patch": patch, "text": f.get("text")})
    body = case.get("body", "")
    return {"repo": "eval/mock", "number": 0, "sha": "0" * 40, "title": case["title"], "body": body,
            "author": "contributor", "files": files, "lines": sum(f["lines"] for f in files),
            "gate": triage.scope_gate(files, body), "repo_paths": repo_paths}


def run_case(case: dict, repo_paths: list, repeat: int) -> dict:
    pr = to_pr(case, repo_paths)
    if case.get("gate"):
        ok = bool(pr["gate"]) and triage.label(pr, {}) == triage.SKIPPED_LABEL
        return {"id": case["id"], "impact": "gate", "expected": "skip Claude",
                "got": ["skipped" if ok else "Claude would run"], "ok": ok, "wrong_approval": False,
                "note": "; ".join(pr["gate"])[:90], "tokens": (0, 0)}
    if pr["gate"]:
        return {"id": case["id"], "impact": case.get("impact"), "expected": "/".join(case["allow"]),
                "got": ["skipped by gate"], "ok": False, "wrong_approval": False,
                "note": "fixture unexpectedly gated: " + "; ".join(pr["gate"])[:70], "tokens": (0, 0)}

    got, notes, tin, tout, suggested = [], [], 0, 0, 0
    for _ in range(repeat):
        result = triage.ask_claude(pr)
        got.append(triage.verdict(pr, result))
        suggested += bool(triage.suggestions(pr, result))
        if result.get("error"):
            notes.append(result["error"])
        if result.get("usage"):
            a, b = re.findall(r"\d+", result["usage"])[:2]
            tin, tout = tin + int(a), tout + int(b)
        r = result.get("review")
        if r and r["verdict"] != got[-1]:
            notes.append(f"Claude said {r['verdict']}")
        if r and r["possible_prompt_injection"]:
            notes.append("flagged injection")
    allow = case["allow"]
    errored = any(n.startswith(("Claude API error", "No API key", "No verdict")) for n in notes)
    if suggested:
        notes.insert(0, f"suggestion posted in {suggested} of {repeat}")
    missing_suggestion = case.get("expect_suggestion") and suggested < repeat
    if missing_suggestion:
        notes.insert(0, "expected a one-click suggestion")
    return {"id": case["id"], "impact": case.get("impact"), "expected": "/".join(allow),
            "got": ["error"] * repeat if errored else got,
            "ok": not errored and not missing_suggestion and all(v in allow for v in got),
            "wrong_approval": READY not in allow and READY in got,
            "note": "; ".join(dict.fromkeys(notes))[:90], "tokens": (tin, tout)}


# --- Renderer checks (no API) ------------------------------------------------

HOSTILE = [
    "see [here](https://evil.example) and [a\\]b](//evil.example)",
    "visit www.evil.example or HTTPS://evil.example or <https://evil.example>",
    "cc @fivetran/everyone and @someone",
    "closes owner/repo#5 and #12",
    "<img src=x onerror=alert(1)> <!-- hidden --> ![x](https://evil.example/p.png)",
    "```\nbreak out of code\n``` **bold** | table |",
]
UNSAFE = {
    "live link": re.compile(r"(?i)https?://|www\."),
    "live @mention": re.compile(r"@[A-Za-z0-9]"),
    "markdown link or image": re.compile(r"(?<!\\)\]\("),
    "raw HTML": re.compile(r"(?<!\\)<[A-Za-z!/]"),
    "issue reference": re.compile(r"#\d"),
    "code fence": re.compile(r"```"),
}


def renderer_checks() -> list:
    pr = to_pr({"title": "t", "files": [{"path": "models/a.yml", "patch": "+x", "text": "x"}]}, [])
    failures = []
    for text in HOSTILE:
        for verdict in ("ready_to_go", "minor_revisions"):
            review = {"summary": text, "risk_tier": "docs_only", "verdict": verdict, "verdict_reason": text,
                      "minor_revisions": [{"file": "models/../.github/x` @evil", "line": 1, "end_line": None,
                                           "change": text, "suggestion": ""}],
                      "recommended_version_bump": "patch", "possible_prompt_injection": False,
                      "injection_note": ""}
            body = triage.comment(pr, {"review": review}).split("\n", 1)[1]  # skip our own marker line
            body = body.replace("<sub>", "").replace("</sub>", "")  # our own commit footer
            for name, pattern in UNSAFE.items():
                if pattern.search(body):
                    failures.append(f"{name} survived in {verdict} comment from input {text[:40]!r}")

    # Suggestions: only small, on-diff, and unable to break out of their code block
    pr = to_pr({"title": "t", "files": [{"path": "models/a.yml", "patch": "@@ -1,2 +1,2 @@\n a\n-b\n+c\n",
                                         "text": "a\nc\n"}]}, [])
    def revision(**kw):
        return {"file": "models/a.yml", "line": 2, "end_line": None, "change": "fix", "suggestion": "d", **kw}
    def posted(rev):
        review = {"summary": "s", "risk_tier": "docs_only", "verdict": "minor_revisions", "verdict_reason": "r",
                  "minor_revisions": [rev], "recommended_version_bump": "patch",
                  "possible_prompt_injection": False, "injection_note": ""}
        return triage.suggestions(pr, {"review": review})
    checks = {
        "valid suggestion is posted": (revision(), True),
        "suggestion that closes its code block is dropped": (revision(suggestion="x\n```\n@evil"), False),
        "suggestion off the diff is dropped": (revision(line=9), False),
        "suggestion on a file outside the PR is dropped": (revision(file="models/b.yml"), False),
        "suggestion over 10 lines is dropped": (revision(suggestion="x\n" * 11), False),
        "empty suggestion is not posted": (revision(suggestion=""), False),
    }
    for name, (rev, expect) in checks.items():
        if bool(posted(rev)) != expect:
            failures.append(f"failed: {name}")
    return failures


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--repeat", type=int, default=1)
    p.add_argument("--only")
    p.add_argument("--offline", action="store_true")
    args = p.parse_args()

    failed = False
    render_failures = renderer_checks()
    print(f"Renderer checks: {'PASS' if not render_failures else 'FAIL'} "
          f"({len(HOSTILE) * 2} hostile comments and 6 suggestion rules checked)")
    for f in render_failures:
        print("  -", f)
    failed |= bool(render_failures)

    data = yaml.safe_load((HERE / "cases.yml").read_text())
    cases = [c for c in data["cases"] if not args.only or c["id"] == args.only]
    if args.offline:
        cases = [c for c in cases if c.get("gate")]

    with ThreadPoolExecutor(max_workers=6) as pool:
        results = list(pool.map(lambda c: run_case(c, data["repo_paths"], args.repeat), cases))

    print(f"\nModel: {triage.MODEL}   repeat: {args.repeat}\n")
    print(f"{'':2}{'case':28}{'impact':18}{'expected':40}got")
    for r in results:
        mark = "✅" if r["ok"] else ("🚨" if r["wrong_approval"] else "❌")
        print(f"{mark} {r['id']:28}{str(r['impact']):18}{r['expected']:40}{', '.join(r['got'])}"
              + (f"   ({r['note']})" if r["note"] else ""))

    wrong = [r for r in results if r["wrong_approval"]]
    should_ready = [r for r in results if r["expected"].startswith(READY) and r["impact"] != "gate"]
    approved = sum(r["got"].count(READY) for r in should_ready)
    tin = sum(r["tokens"][0] for r in results)
    tout = sum(r["tokens"][1] for r in results)
    print(f"\nWrong approvals: {len(wrong)} (must be 0)")
    if should_ready:
        print(f"Low-impact PRs approved: {approved} of {len(should_ready) * args.repeat} runs")
    print(f"Passed: {sum(r['ok'] for r in results)} of {len(results)} cases")
    print(f"Tokens: {tin} in / {tout} out")
    failed |= bool(wrong) or any(not r["ok"] and (r["impact"] == "gate" or "error" in r["got"]) for r in results)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
