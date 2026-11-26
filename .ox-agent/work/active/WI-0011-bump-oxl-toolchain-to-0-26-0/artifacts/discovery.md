# WI-0011 discovery — bump oxl 0.23.2 → 0.26.0

## Intent
Move `.oxl-version` to 0.26.0 so WI-0013 (protocol flags) and later stages
can consume: `Request.http_version` ("2", "2-prior-knowledge" → h2/h2c),
`tls.Config{min_ver,max_ver,client_cert}` + `load_cert_pem` (TLS 1.2 pins +
mTLS), `connect_proxy`/`Request.proxy` (HTTPS-over-proxy CONNECT),
`net/websocket`, `net/grpc`. Release: oxl v0.26.0 (2026-11-25), PR
oxidean/oxl#227. Issues it resolves for us: #218 (h2), #220 (ws),
#221 (mTLS), #222 (CONNECT), #223 (gRPC), #224 (TLS 1.2).

## Reality check (run on this branch, pin flipped)
- `oxl build ./cli`, `oxl build ./tui`: clean, zero source changes.
- Full per-dir `oxl test` loop (cli, core/{collection,http,item,model,
  session,term}, shared/args): all green, incl. live-socket h1 suite and
  the 13-case golden harness via `cli/golden_test.oxl`.
- `oxttp --version` / `--help` smoke: xh-faithful output unchanged.
- `oxl build` now *enforces* single-package arg ("takes a single
  package") — was silently first-arg-only before (same class as #131).
  CI already invokes per-app (`./cli`, `./tui` separately): no change needed.
- CI installs toolchain via `curl .../v$(cat .oxl-version)/...` — reads
  the pin dynamically; the one-line diff covers CI automatically
  (AGENTS.md: "bump the pin and CI together" = same file).

## Note — h3 NOT consumable
oxidean/oxl#219 ("HTTP/3 over QUIC") is closed COMPLETED but the shipped
toolchain has no `http3`/`quic` package and `client.oxl` only special-
cases `http_version` "2"/"2-prior-knowledge". `--http-version 3*` stays
`oxl-blocked` in the parity matrix — flag to Jesse/upstream, do not
claim h3 parity.

## Constraints
- Zero code changes required — compat surface is source-stable
  0.23.2→0.26.0 for everything we use (net.Conn, tls.Config fields we
  set, os/term, os/signal, testing).
- Keep diff minimal: `.oxl-version` only. Any compat fix that appears
  lands as its own commit with the finding.
- Sibling agents hold oxttp-wt-s9 (WI-0012) — this worktree is
  self-contained; stage explicit paths only.
