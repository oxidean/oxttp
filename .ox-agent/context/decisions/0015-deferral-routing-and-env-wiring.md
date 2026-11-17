# 0015 — S4 deferral routing and env-var wiring levels

Status: accepted (2026-11-17, WI-0005 specification)

With the full 58-flag surface parsing at S4 but execution landing at
S5+, a fully valid parse needs an honest end state (decision 0006).
The spec pins a small routing table instead of ad-hoc errors:

- `--generate` → `{prog}: error: --generate is unsupported in this
  build` (exit 1).
- Any `--unstable-m-sig-*` present → upstream's exact `This binary
  was built without message signature support. Enable the
  'http-message-signatures' feature.` (exit 1).
- `--http-version=3-prior-knowledge` → `This binary was built
  without support for HTTP/3. Enable the 'http3' feature.` (exit 1).
- Constructed URL with a non-http scheme (incl. `--https` /
  https-bin-name results) → `<scheme> URLs are unsupported in this
  build (TLS is not available)` (exit 1).
- Otherwise → `request execution is unsupported in this build`
  (exit 1). S5 replaces this arm with the real request path; the
  other arms persist.

Env vars split by where they act, not by when they're read:
parse-level wiring now (XH_CONFIG_DIR, XH_HTTPIE_COMPAT_MODE,
REQUESTS_CA_BUNDLE, CURL_CA_BUNDLE, NO_COLOR, TERM, and the four
proxy vars captured-but-inert until S3's transport); execution-side
reads deferred to the stages that own the behavior (NETRC,
RUST_LOG, RUST_BACKTRACE, SOURCE_DATE_EPOCH) — each tagged in the
spec's coverage list rather than silently absent.
