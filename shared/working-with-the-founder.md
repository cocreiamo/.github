## Working with the founder

This section has one canonical copy: `shared/working-with-the-founder.md` in cocreiamo/.github. Change it there; the `rules / check` of every repository fails until its `CLAUDE.md` carries the same text at the pinned ref of that workflow.

- Answer first, then act. Every failure report has four parts in plain words: facts, root cause (why it was possible), how the class is closed (the check, proven red), what remains open. After every agent report: a critical read and corrective recommendations. Every 4-5 replies: a short recap (in progress, what is missing in order, known debt).
- A spoken yes is enough: act yourself (applies, playbooks, cleanups, dashboards through Claude in Chrome, accepting permission updates of our own GitHub Apps) and report the outcome; never hand the founder a command you can run. A rebuild-from-scratch drill runs only when the founder asks for it.
- A rule that depends on someone remembering it becomes a default or a check that fails. Before building any mechanism (script, check, controller, workflow), search for an existing free, maintained tool or a native feature of what we already run, and name it in the proposal; build our own only when none fits, and say why. The same applies to services: free tier or open source first.
- The founder is the bottleneck: design checks and gates that need no click from him (an automatic gate from a protected `main`, not a manual approval) and ask only for an irreversible or external action not yet authorized.
- Everything is greenfield: no user or customer depends on an old resource, so a cleanup he authorizes (packages, zones, groups, projects that stay recoverable for a period) is yours to run; only what the rules forbid you stays with him (typing passwords, verification codes and cards, creating accounts, deleting data that cannot come back).
- Read a file before editing it; never put an action (apply, push, bootstrap, cluster write) in the same parallel batch as the edits it depends on; cluster changes go through tasks or PRs, and you say beforehand what an action will touch.
- Agents: briefs ask for foreground commands (an agent's background waits wake the coordinator for nothing). Never `pkill -f` or `pgrep -f` on a pattern contained in your own command line (the shell matches itself): stop background tasks by their ID or by exact PIDs.
- Done means seen working on the real path: after an apply, a rollout, a merge or a fix, watch one real consumer succeed (a CI job on the changed runner, a probe, a request, the next run on `main`) before saying it works. An exit code or `failed=0` is not that proof.
- Change shared state (a mount, a cache, a config that running jobs or pods read) only with its consumers drained, or versioned so that old and new never share it. Every rollout has a canary and a rollback path, decided before it starts.
- Facts before claims: a statement about live state (a cause, a count, what a tool is used for, whether something is applied) comes from a primary source read now (a log, an API, a metric, the file at `origin/main`), or is marked unverified. An agent's finding is unverified until spot-checked, and a blocker is spot-checked before it is acted on or reported. A wrong claim is corrected openly in the next reply.
- Read a red before rerunning it: a rerun is fine only once the cause is named. A check that blocks valid work is fixed at its root with a fixture of that history, never bypassed.
- Count before launching: agents in flight are counted against the limits before every launch, and a red PR gets an owner in the same reply that finds it.
- Spend CI and time only where they buy information:
  - one PR per repository per block of work, several commits inside; a separate PR only for an incident rollback;
  - push a branch once, after running locally every check its change touches (not only the fast lint): a CI red that a local run would have found is a wasted round of every required check, the queue update and the post-merge verification;
  - CI runs what the change touches and the nightly runs everything; the pre-push hook runs only the fast checks;
  - a `test:` commit before `fix:` is for defects in logic, policies and scripts; a pure value change (a version bump, a config value, a workflow wiring) is proven by the live check after the merge, not by a new test;
  - before adding a check, search the existing checks and extend the one that already covers the area: two checks of one rule are waste;
  - verify once per batch, not per change: batch the changes, run each check once at the end of the batch and bisect only when it is red; the full pre-push run happens once per batch, by one agent;
  - a fix's red proof reuses what already exists (the previous build, the old binary, the failing check itself), never an extra build;
  - a base that another branch is integrating is frozen; agents on one integration work in sequence on its branch, not on topic branches merged afterwards;
  - build directories and caches persist between runs;
  - waits run beside work: start the wait, prepare the next block meanwhile, never sit idle on CI;
  - verify a brief's premise from a primary source before delegating, and name the existing checks and tools the agent must read first, so the agent does not come back for another round.
