# WI-0006 ship readiness — S5 CLI request path + golden harness

## What ships

PR #8 — `feat(cli): request execution path and golden test harness`.
The `oxttp` binary sends real HTTP/1.1 requests: all body kinds,
header merge order, basic/bearer/netrc/digest auth, sessions,
redirects + hop history, download, check-status exits, offline.

## Evidence

- verification verdict `pass_with_notes` (artifacts/verify.md):
  12-dir `oxl test` loop green, 136 cli test fns, 13 golden cases
  differential vs real xh, live socket fixtures.
- CI legs on PR #8: commit-lint pass; oxl-build runs the same
  per-dir test loop + toolchain build + --version smoke.
- Review gate: CodeRabbit manual review triggered on the PR.

## Rollout / rollback

Merge-order independent: touches cli/, core/{http,model}, scripts/,
tests/, .ox-agent work+context. Rollback = revert the squash commit;
no shared interfaces change shape (h1 Transport port untouched —
additive core/model fields only).

## Outstanding gate

shipping → shipped is human-approved (policy.yaml). Escalating;
fires on PR #8 merge.
