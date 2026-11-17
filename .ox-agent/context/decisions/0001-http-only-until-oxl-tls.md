# 0001 — HTTP-only until oxl std gains TLS

Status: decided (owner: Jesse, 2026-11-17)

oxl `std/net/http` is HTTP/1.1 only — no TLS, "HTTPS stays parked"
upstream. Options weighed:

- A: FFI TLS shim inside oxttp `shared/` — unblocks HTTPS now but adds a
  C FFI boundary the language doesn't cleanly support yet.
- B: Drive TLS into oxl std first — right home long-term but serializes
  the project behind language milestones.
- C: HTTP-only v0 — chosen. HTTPS support is a deferred non-goal; when
  oxl std lands TLS, a follow-up milestone adds it without re-architecting
  (transports already sit behind `core/http`).

Consequence: specs and corpora mark every HTTPS-adjacent surface
(`--https`-style flags, TLS config keys, `https://` URL handling) as
deferred with an explicit reason rather than dropping it silently.
