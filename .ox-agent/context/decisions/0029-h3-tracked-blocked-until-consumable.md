# ADR-0029: `--http-version 3*` stays `oxl-blocked` until a consumable surface exists

Status: accepted (2026-11-25, WI-0011)

## Context
oxidean/oxl#219 ("HTTP/3 client over QUIC") closed COMPLETED and the
v0.26.0 release notes list "protocol backlog", but the shipped toolchain
contains no `http3`/`quic` package and `client.oxl` only branches on
`http_version` "2"/"2-prior-knowledge". There is no API for oxttp to
call.

## Decision
Parity claims require a callable surface, not a closed issue. Keep
`--http-version 3*` and Posting h3 rows `oxl-blocked` citing #219's
missing surface; flip only when `std` ships a package oxttp can bind to.
Same rule applies to any future "closed but unshipped" upstream item.

## Consequences
- Honest corpus reporting (ADR-0024 spirit): we never claim parity on
  paper.
- When upstream exposes h3, the flags WI needs only the transport wiring
  — no spec rework, the corpus row is already enumerated.
