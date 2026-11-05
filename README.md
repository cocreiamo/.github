# cocreiamo/.github

What the cocreiamo repositories share, written once: reusable workflows and the canonical copy of the shared rules.
Managed by cocreiamo/infrastructure (`tofu/github`).

## Reusable workflows

| Workflow | What it checks | Call it |
|---|---|---|
| `pr-title.yml` | the PR title (the squash commit on main) is a Conventional Commit and not a `test:` | `jobs: {title: {uses: cocreiamo/.github/.github/workflows/pr-title.yml@<sha>}}` on `pull_request` `[opened, edited, synchronize, reopened]` |

Callers pin a commit SHA; Renovate proposes the bumps. `bash tests/pr-title.sh` proves the check on good and bad titles.
