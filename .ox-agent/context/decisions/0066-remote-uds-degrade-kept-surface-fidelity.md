# ADR-0066 — `remote` keeps the UDS degrade; surface fidelity is still owed

- Status: accepted
- Date: 2026-11-28
- Work item: WI-0019 (M4c)

## Context

Upstream `posting remote` drives a running instance over a Unix-domain
socket (`internal/remote`, `paths.SocketDir`). oxl 0.26.0 `std/net`
exposes TCP `dial(host,port)`/`listen(port)` only — no AF_UNIX, no
`socketpair`. ADR-0036 already degraded instance commands to
`no running Posting found (unix sockets unsupported in this build)`.
This WI must decide whether to (a) keep degrading, (b) invent a TCP
transport, or (c) implement the protocol anyway.

## Decision

Keep the degrade. Rationale:

- A TCP remote protocol is a *larger* deviation than the documented
  degrade — it invents a surface upstream doesn't have (firewall
  exposure, auth model) rather than approximating an existing one.
- The protocol JSON shapes (`protocol.go`) are still worth pinning in
  tests so a future oxl AF_UNIX lands cleanly; the client-side
  request/response structs get ported as types + unit tests, unused
  by live code paths (cheap, keeps the contract warm). — NOTE: only
  if cost stays trivial; otherwise deferred to the AF_UNIX WI.
- Surface fidelity IS owed and lands in this WI: strict upstream
  flag grammar (`parseRemoteOptions` port: `--json --none --name
  --curl --yaml --instance`, `--x=v`, `--` terminator, per-command
  positional rules, cross-flag constraints), the exact command set
  `list requests show open send response env save skill` (**`new` and
  `focus` removed** — they are not upstream commands), verbatim
  `remoteUsage`/`runUsage`-style help text, vendored
  `skills/using-posting/SKILL.md` (131 lines, ADR-0041 vendoring
  precedent — generated const, not runtime file read), `list`
  empty-instance → stderr `No Posting is running.` exit 0 /
  `--json` → `[]`, and exit codes 0/1/2 matching upstream.
- An oxl upstream issue for AF_UNIX `net.DialUnix`/`ListenUnix` is
  filed (or confirmed existing) so the degrade has a tracked exit.

## Consequences

- `remote` behaves corpus-faithfully for everything reachable
  headlessly (`skill`, `list`, parse errors, usage); instance commands
  keep the recorded degrade until oxl grows AF_UNIX.
- `new`/`focus` removal is a (corrective) deviation from our own S11
  scaffolding toward upstream truth.
