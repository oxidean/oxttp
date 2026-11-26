# ADR-0031 — `--native-tls` on a single-stack build: warn on https, inert on cleartext

- Status: accepted
- Date: 2026-11-26
- Work item: WI-0013 (brainstorming)
- Supersedes: the `--native-tls` arm of ADR-0024's degrade table

## Context

xh's `--native-tls` selects an *alternate* TLS backend. On the corpus
reference build (`+native-tls +rustls`) it is functional — warnings
catalog entries ("Custom CA bundles with native-tls are broken",
"Client certificates are not supported for native-tls") and the
additional-message hint "Try running without the --native-tls flag."
only make sense when a second backend exists. On any single-backend
xh build the flag is a **silent no-op**.

oxl 0.26.0 closed the upstream mTLS gap (oxl#221) that our current
`--native-tls && https` exit-1 defer cites — the defer is stale.

## Decision

`--native-tls` asks for something a one-stack build cannot honor, but
honoring-vs-ignoring it is **not output-visible on cleartext** (TLS
never engages on `http://` in any build). So, per ADR-0024:

- `http://` → inert-fidelity (byte-identical; no warning).
- `https://` → warning-degrade via `plan().warn`:
  `{prog}: warning: --native-tls selects an alternate TLS backend;
  this build ships one TLS stack (oxl std/net/tls) — using it`.
  The request still runs — same result a single-backend xh produces.
- `--curl` → `Warning: Ignored --native-tls` (corpus §5 lists it).

## Alternatives considered

- **Full inert**: literal single-backend parity, but silent about an
  unhonorable ask on the reference config — against ADR-0006's
  say-so spirit.
- **Keep error-degrade**: safe but needlessly breaks harmless uses;
  xh never errors here on single-backend builds.

## Consequences

- The stale `#221` error defer retires; corpus §4.5 `--native-tls`
  row can move to `done` (warning-degrade).
- If a second TLS backend ever lands, this ADR is revisited —
  the flag becomes functional, not warned.
