# Corpus fidelity contract

The compatibility surface of each ported app is pinned as a source-cited
corpus under `docs/corpus/`:

- `corpus-xh.md` — xh v0.26.3 @ commit 8b21cc0: 58 flags, 10 request-item
  operators, 14 env vars.
- `corpus-posting.md` — Posting 3 `v3.0.0-beta.1` @ commit 32c4566 (the
  Go rewrite on Terma is canonical; the Python `src/` tree is Posting 2
  legacy): 13 flags + 5 subcommands, ~114 keybindings, 40 config keys,
  full `.posting.yaml` schema.

Rules:

- Implementations must match the corpus one-to-one — flags, operators,
  env vars, keybindings, config keys, defaults, exit behavior.
- Every corpus claim carries a source citation; trust it, but re-check
  upstream when a behavior is ambiguous (pin commits, not branches).
- Deviations (e.g. HTTPS deferred until oxl std has TLS) are recorded in
  specs and ADRs — never silent gaps.
- When upstream ships a new release, corpus refresh is its own work item.
