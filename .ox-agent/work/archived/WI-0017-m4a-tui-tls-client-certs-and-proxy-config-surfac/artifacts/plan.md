# WI-0017 plan — M4a TUI TLS client certs and proxy config surface

Spec: `artifacts/spec.md`. ADRs: 0044/0045/0046. Small surface WI —
three code stages + matrix/docs, single branch, per-stage commits.
Each gate = `oxl build` on touched leaf dirs + `oxl test` on touched
dirs green.

| Stage | Work | Depends | Gate |
|---|---|---|---|
| **P1 proxy_pick + plan_req wiring** | `core/collection`: `ProxyPick` struct + pure `proxy_pick(proxy_url, pairs)` (explicit `"all:"+trim` vs env scan: scheme/lowercase names, httpoxy REQUEST_METHOD guard, NO_PROXY precedence, empty-skip); `collect_proxy_env()` getenv shim (9 names); `plan_req` replaces warn branch (~L2097) with `proxy_pick(proxy, collect_proxy_env())` → `rq.proxies/proxy_env/no_proxy`. New `proxy_test.oxl` (or extend collection_test) covering every spec-S1 bullet. | — | `oxl build ./core/collection`-equivalent leaf + `oxl test` collection dirs green |
| **P2 mTLS degrade honesty** | `tui/coll.oxl`: reword ssl.password toast; `exec_send_t` captures `had_cert` pre-nil, toasts W2-parity warning on `resp.tls_ver==tls.V12 && had_cert` (+`std/net/tls` import). `tui/cli.oxl`: ssl.password+cert → one stderr warning pre-loop; per-request TLS1.2-cert stderr note post-send (+tls import). Tests: coll_test/send_test fake-transport TLS1.2 matrix (V12+cert→toast, V13→none, cleartext→none, no-cert→none); cli_test warning assertions; password-toast text pin. | P1 (same files region, keep diffs clean) | tui dirs green |
| **P3 matrix + docs + full verify** | parity-matrix.md: posting §7.1 client certs `next`→`done` (DevD notes D1/D2), §7.1 HTTP proxy note → `done`; spec DevDs already recorded — mirror row text. Full per-dir `oxl test` loop over `git ls-files '*.oxl'` dirs; `oxl build` both binaries; git clean. | P1, P2 | whole-tree green |

## Order rationale

- P1 first: it's the only core/ change and unblocks nothing else —
  but it IS the bulk of new logic (pure helper + env shim + plan
  wiring + its own tests).
- P2 second: tui-only edits, depends on nothing in P1 mechanically
  but shares the send path narrative; sequenced to keep review clean.
- P3 last: matrix rows cite final behavior; full loop is the ship gate.

## Risks / calls to resolve in-stage

- **oxl slice literal**: `rq.proxies` is `[]str` (not `own`) — assign
  via `pk.proxies[:]` or push-loop; verify syntax compiles (mkslice
  quirk noted in repo rules).
- **`collect_proxy_env` placement**: inside collection.oxl vs new
  `proxy.oxl` sibling — pick whichever keeps file sizes sane;
  package is flat.
- **toast level for TLS1.2-cert warning**: spec says level 1 (info) —
  matches warns-toast convention; confirm toast signature.
- **cli.oxl `rep.stderr`**: verify it's appendable post-loop-start
  (string concat pattern already used at L424).
- **test env hygiene**: proxy_pick tests are pure (synthetic pairs);
  plan_req delegation test must not depend on ambient proxy env —
  assert field consistency, not absence.

## Commit plan

- `feat(core): plan_req proxy_url + env proxy capture (WI-0017 P1)`
- `feat(tui): mTLS degrade honesty — ssl.password wording + TLS1.2 cert warning (WI-0017 P2)`
- `docs(agent): WI-0017 parity matrix rows` (or fold into P3 verify
  commit `chore(agent): ...` matching repo convention — check
  WI-0016's matrix commit style at stage time)
