# cocreiamo/.github

What the cocreiamo repositories share, written once: reusable workflows and the canonical copy of the shared rules.
Managed by cocreiamo/infrastructure (`tofu/github`).

## Reusable workflows

| Workflow | What it checks | Call it |
|---|---|---|
| `pr-title.yml` | the PR title (the squash commit on main) is a Conventional Commit and not a `test:` | `jobs: {title: {uses: cocreiamo/.github/.github/workflows/pr-title.yml@<sha>}}` on `pull_request` `[opened, edited, synchronize, reopened]` |
| `shared-rules.yml` | `CLAUDE.md` carries, byte for byte, the section `## Working with the founder` of `shared/working-with-the-founder.md`, and every script the repository declares in `.github/shared-scripts` is a copy of the canonical one in `shared/scripts/` (content and executable bit) | `jobs: {rules: {permissions: {contents: read}, uses: cocreiamo/.github/.github/workflows/shared-rules.yml@<sha>}}` on `pull_request` `[opened, synchronize, reopened]` |

`bash tests/claude-telemetry.sh` proves that `.claude/settings.json` sends Claude Code telemetry to `otel.cocreiamo.com` (this repository sets it like the others).

Callers pin a commit SHA; Renovate proposes the bumps (see «Renovate»). `hooks/check-conflict-markers` (the pre-commit hook, set as `core.hooksPath` by mise, and a step of `check`) refuses a line starting with `<<<<<<<` or `>>>>>>>`; `bash tests/conflict-markers.sh` proves it on conflicted and clean files. `bash tests/pr-title.sh` proves the title check on good and bad titles, `bash tests/shared-rules.sh` the shared-rules check on a canonical, a diverged and a missing section.

## Shared rules

`shared/working-with-the-founder.md` is the one canonical copy of the section `## Working with the founder`, present in the `CLAUDE.md` of infrastructure, deploy and cocreiamo. A caller's token cannot read this private repository's files, so `shared-rules.yml` embeds the text and `tests/shared-rules.sh` keeps the embedded copy equal to the file. To change the rule: edit both here (the test fails otherwise), merge, then in each repository bump the pin of `shared-rules.yml` and carry the new text into its `CLAUDE.md`: until it does, its `rules / check` is red and the merge is blocked. Every caller must grant its job the permission the workflow needs (`pr-title.yml`: `pull-requests: read`; `shared-rules.yml`: `contents: read`), or the run is a `startup_failure`; each repository's checks require it.

## Shared scripts

Scripts that more than one repository needs have one canonical copy in `shared/scripts/` (flat names). Each repository keeps a vendored copy at its own path (it must work offline and the CI never fetches at runtime) and declares it in `.github/shared-scripts`, one `canonical-name local-path` per line (`#` comments; a script a repository deliberately does not share is listed there as a comment with the reason). `shared-rules.yml` carries the whole directory as a base64 gzipped tar (a caller's token cannot read this repository's files) and its check fails, printing the diff, when a declared copy differs, is missing or lost its executable bit, or when the manifest is absent, empty or names a script that is not canonical.

To change a script: edit `shared/scripts/<name>`, run `tools/embed-scripts.sh` (`tests/shared-scripts.sh` fails until the bundle matches), merge, then bump the pin in each repository: the Renovate postUpgradeTask (`renovate/sync-founder-section.sh`, the one command every caller allows) overwrites the declared copies with the canonical ones, so the bump PR is complete. `eol_check.py` is the end-of-life check every repository runs in its own scheduled CI (`mise run check:eol`: pinned mise tools, charts, image tags and FROM lines against endoflife.date, failing within 60 days of an end of life; run through `uv`, pyyaml pinned in the script); `bash tests/eol-check.sh` tests it. `bash tests/shared-scripts.sh` proves the check on identical, diverged, missing, non-executable and undeclared copies; `bash tests/sync-founder-section.sh` proves the sync.

## Renovate

Dependency updates are one self-hosted Renovate per repository: a nightly `renovate.yml` on the `[self-hosted, cocreiamo-ci]` runners, authenticated as the existing GitHub App `cocreiamo-claude-code-pr` (repository variable `CLAUDE_CODE_PR_APP_ID`, repository secret `CLAUDE_CODE_PR_APP_PRIVATE_KEY`; the key is in the SOPS file of cocreiamo/infrastructure as `CLAUDE_CODE_PR_APP_PRIVATE_KEY` and in the offline seed). Each repository's `renovate.json` extends `github>cocreiamo/.github//renovate/default` and names its managers.

`renovate/default.json` is the shared preset: `config:recommended`, action digests pinned, semantic commit titles that pass `pr-title.yml` (`ci(deps)` actions, `build(deps)` providers and mise tools, `chore(deps)` the rest), platform automerge of minor, patch and digest updates once the required checks are green, the dependency dashboard, and one group each for actions, providers and mise tools. A bump of the pin of `shared-rules.yml` merges by itself, and its `postUpgradeTasks` runs `renovate/sync-founder-section.sh` (fetched at the new pin) to rewrite the repository's `CLAUDE.md` founder section to the canonical text, so `rules / check` passes on the bump PR. The only command a Renovate run may execute is the one in `renovate/allowed-commands.regex`, set as `RENOVATE_ALLOWED_COMMANDS` in each `renovate.yml`. `bash tests/renovate-config.sh` validates the configs strictly (`renovate-config-validator`, pinned in `mise.toml`) and proves an invalid one is refused; `bash tests/sync-founder-section.sh` proves the sync.
