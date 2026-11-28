# ADR-0045 — mTLS degrade honesty: `ssl.password` unsupported, TLS1.2 cert warning

- Status: accepted
- Date: 2026-11-27
- Work item: WI-0017 (M4a)

## Context

Corpus posting §2.2 defines four `ssl.*` leaves: `ca_bundle`,
`certificate_path`, `key_file` ("else read from certificate_path"),
`password` ("Password for PKCS#8 / `Proc-Type: 4,ENCRYPTED` keys").
§7.1: "Client-cert/password problems are reported at send time."

oxl 0.26.0 `std/crypto/x509.parse_key_pem` rejects
`ENCRYPTED PRIVATE KEY` ("x509: encrypted private keys unsupported")
and exposes no password parameter; legacy `Proc-Type: 4,ENCRYPTED`
PEM isn't decoded. PKCS#8 PBES2 decryption is a crypto port — out of
scope for a surface WI. Separately, oxl client certs are TLS 1.3-only
(`tls.Config.client_cert` doc): a TLS 1.2 negotiation answers
CertificateRequest with an empty certificate_list — the peer sees no
client cert even though one is configured. The CLI surfaces this as
warning W2 (WI-0013); posting/Go would present the cert on 1.2.

## Decision

1. `ssl.password` remains a degrade. The toast text is reworded —
   the old "encrypted keys land with mTLS M4" promise is void (this IS
   M4a) — to state the build limitation plainly. DevD entry in spec.
   Not an oxl bug (missing feature); no upstream issue filed.
2. Client-cert problems stay send-time: file reads happen in the send
   plan (existing), PEM parse/key-mismatch errors surface from the
   transport as send failures. No `net/tls` import is added to
   `core/collection` — layering keeps plan free of transport details.
3. When a client cert is configured AND the response negotiated
   TLS 1.2 (`resp.tls_ver == tls.V12`), the TUI toasts a warning
   mirroring CLI W2's meaning ("client certificate was not
   presented: TLS 1.2 sends an empty certificate list in this
   build"); headless `run` prints a `warning:` stderr line. Corpus is
   silent — explicit-degradation ADR-0006 applies.
4. TLS version pins (`--ssl tls1.2` CLI surface) have NO posting
   equivalent: corpus §2.2/§5.2 define no such keys. Nothing is
   invented; the transport's `[V12,V13]` default (ADR-0032) stands.
   Recorded as a documented absence, not a DevD.

## Consequences

- `ssl.certificate_path`/`key_file`/`ca_bundle` behavior is unchanged
  (already folded at send time in both paths); this ADR only fixes
  the password degrade wording and adds the 1.2-cert warning.
- `ssl.key_file` without `certificate_path` stays ignored — upstream
  semantics make a bare key meaningless (no cert to pair).
