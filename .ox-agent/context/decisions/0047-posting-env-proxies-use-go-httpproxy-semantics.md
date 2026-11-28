# ADR-0047 — Posting env proxies use Go `httpproxy` semantics

- Status: accepted
- Date: 2026-11-28
- Work item: WI-0017 (M4a)
- Supersedes: the env-var selection portions of ADR-0044 and ADR-0046

## Context

WI-0017 initially reused the xh/reqwest proxy model for posting's TUI:
capture both cases of `HTTP_PROXY`/`HTTPS_PROXY` plus `ALL_PROXY`, skip
`HTTP_PROXY` under CGI, and feed the transport's reqwest-style matcher.
That was the wrong upstream contract. Posting is a Go application; its
environment proxy behavior comes from `golang.org/x/net/http/httpproxy`
and `net/http`'s `ProxyFromEnvironment` shape:

- only `HTTP_PROXY`/`HTTPS_PROXY`/`NO_PROXY` exist — there is no
  `ALL_PROXY` in Go `httpproxy`;
- `getEnvAny` prefers uppercase when both cases are present and
  non-empty, with lowercase as fallback;
- schemeless proxy values are retried as `http://host[:port]`; unusable
  values are dropped rather than surfaced as parse errors;
- any raw non-empty `REQUEST_METHOD` (including whitespace) marks CGI.
  Go does not silently delete `HTTP_PROXY`; it errors before using it
  for an `http:` hop, ahead of `NO_PROXY` bypass;
- localhost/loopback bypass even an empty `NO_PROXY`, entries are
  port-aware, CIDRs match, and leading-dot/`*` forms are
  subdomain-only;
- `options.proxy_url` participates in the same scoped environment
  substitution as URL/headers before use.

CodeRabbit also flagged that the xh/reqwest matcher lacked IPv4 CIDR
support. Reqwest's documented `NO_PROXY` format does support subnet
masks, so that matcher needs CIDR support independently of the Go
split.

## Decision

1. `model.Req` carries `proxy_go` and `cgi`. `proxy_go` selects the
   transport's Go `httpproxy` resolver; false keeps the reqwest-style
   resolver used by the xh CLI.
2. `collection.proxy_pick` canonicalizes TUI/posting env capture to
   lowercase `https_proxy=`/`http_proxy=` pairs using uppercase-first
   precedence, normalizes schemeless values to `http://`, ignores
   `ALL_PROXY`, passes `NO_PROXY` through, and sets `cgi` from the raw
   `REQUEST_METHOD` value. `plan_req` substitutes `options.proxy_url`
   before calling it.
3. `core/http` implements `pick_proxy_go`/`no_proxy_match_go` as the
   Go-mode resolver, including the CGI send-time error and per-hop
   host:port matching.
4. The existing reqwest-style `no_proxy_match` gains IPv4 CIDR support
   for the xh CLI path without adopting Go-only behaviors (loopback
   bypass remains a Go-mode difference).

## Consequences

- TUI/posting proxy behavior now follows the correct upstream runtime;
  xh CLI behavior stays on its own corpus contract.
- `ALL_PROXY` remains xh-only. This is a deliberate divergence from the
  first WI-0017 spec draft and is reflected in the amended spec.
- The transport surface gained two booleans; all `model.Req` literal
  constructions must name them.
- IPv6 proxy matching remains out of scope because the transport does
  not yet support IPv6 dialing.
