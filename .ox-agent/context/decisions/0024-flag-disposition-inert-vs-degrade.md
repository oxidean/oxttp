# 0024 — flag disposition: inert only when output-identical, else degrade

Status: accepted (2026-11-17, WI-0006 specification)

S5 executes a subset of the 58 parsed flags. The disposition rule
for the rest (decision 0006 sharpened):

- **inert** is allowed ONLY where upstream's own output is
  byte-identical under our constraints: TLS knobs on cleartext
  (--verify/--cert/--cert-key/--ssl/--native-tls — unused on
  http://), --ipv4 (v4-only anyway), --stream and the
  display-only flags whose processing requires formatting/color
  we never reach on a non-TTY stream (--response-charset,
  --response-mime, --style, --history-print's value honored
  separately). Inert here is fidelity, not absence.
- **error degrade** (`{prog}: error: <flag> is unsupported in
  this build`, exit 1) for connection-affecting flags where
  proceeding silently could send a different request than asked:
  --proxy/proxy-env, --resolve, --interface, --ipv6,
  --unix-socket, --http-version 2/2-prior-knowledge, --curl,
  plus --pretty!=none and --format-options — upstream honors
  these on pipes (colors/format applied to redirected output), so
  ignoring them would diverge visibly.
- **warning degrade** (`{prog}: warning: <msg>`, -qq hides) for
  flags whose contract is output shape, not request semantics:
  --debug this stage.

Consequence: every parsed flag lands exactly one of {executed,
inert-fidelity, warning-degrade, error-degrade}; the spec's
sem-G table is the canonical list and the golden harness's
degrade cases pin the texts.
