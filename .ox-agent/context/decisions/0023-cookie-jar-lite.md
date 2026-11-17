# 0023 — cookie handling is jar-lite (name-keyed, host-scoped)

Status: accepted (2026-11-17, WI-0006 specification)

Upstream's reqwest cookie jar is always on and applies full RFC
6265 matching (domain suffix, path prefix, expiry, secure) across
redirect hops and into session persist. v0.1 implements jar-lite:

- a name-keyed cookie map carried on the request, updated from
  every response hop's `Set-Cookie` (last write wins);
- session-file cookies seed it; the emitted `Cookie:` header is
  the map in insertion order;
- matching is host-only — path/domain/expires/secure attributes
  are stored for session persist but not consulted when emitting.

Deviation vs upstream: a cookie set for path /a could be sent on a
/request to /b, and an expired or foreign-domain cookie could be
replayed — paths upstream's jar rejects. Single-host redirect
chains (the corpus surface) are unaffected; the gap is recorded in
the spec and a golden case pins the supported behavior.

Consequence: sessions round-trip cookies correctly on same-host
flows; exotic cookie scoping stays a declared gap for S7+.
