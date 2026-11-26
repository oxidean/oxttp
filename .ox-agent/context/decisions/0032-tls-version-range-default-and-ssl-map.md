# ADR-0032 — default TLS range moves to [V12,V13]; `--ssl` maps to min_ver/max_ver

- Status: accepted
- Date: 2026-11-26
- Work item: WI-0013 (brainstorming)

## Context

oxl's `tls.Config` zero value is deliberately TLS 1.3-only ("a
zero-valued Config intentionally means TLS 1.3 only"); the 1.2
fallback (ECDHE-GCM suites) engages only when `min_ver<=V12<=max_ver`.

xh's default TLS behavior under rustls offers 1.2+1.3 — a 1.2-only
server succeeds in stock xh today and fails in oxttp. `--ssl`
"forces min=max" upstream; `auto`/`ssl2.3` means let the backend
choose.

## Decision

1. The default (no `--ssl`) TLS config becomes `min=V12, max=V13` —
   the rustls-default analog and the corpus-faithful choice.
2. `--ssl` table: `tls1.3` → min=max=V13; `tls1.2` → min=max=V12;
   `auto`/`ssl2.3` → the new default [V12,V13].
3. `tls1`/`tls1.1` (inexpressible — `client_tmo` rejects `minv<V12`)
   → warning-degrade: corpus's first clause verbatim, consequence
   adapted honestly (no native-tls to enable):
   `{prog}: warning: rustls does not support older TLS versions.
   This build's TLS stack requires TLS >= 1.2 — falling back to
   TLS 1.2+.` then proceed at [V12,V13].
4. mTLS caveat wired with it: `--cert` configured + negotiated `V12`
   → one-time warning that the client certificate was not presented
   (upstream: 1.2 answers CertificateRequest with empty
   certificate_list).
5. `--curl` emits `--tlsv1.2 --tls-max 1.2` shapes per corpus §5.

## Consequences

- Cleartext unaffected; all `--ssl` values are inert-fidelity on
  `http://` as before.
- A TLS 1.2-only peer works by default — closes a real parity gap.
- The fallback's narrowness (ECDHE-GCM only, no CBC/RSA-kx/
  resumption/renegotiation) is upstream's documented scope, not
  ours to extend.
