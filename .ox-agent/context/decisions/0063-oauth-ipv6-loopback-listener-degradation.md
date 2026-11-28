# ADR-0063 — OAuth IPv6 loopback listener degradation

- Status: accepted
- Date: 2026-11-28
- Work item: WI-0022 (M4f OAuth2 authorization flow)

## Context

Upstream accepts an OAuth redirect URI whose host is any loopback IP,
including IPv6 `::1`, and binds a callback listener on that exact host. oxl
0.26.0's `std/net.listen` uses IPv4 sockets and binds `INADDR_ANY`; it has no
IPv6 listener surface. The specification-stage review found that accepting
IPv6 configuration silently and then serving IPv4 would violate the redirect
URI and Host validation contract.

## Decision

Validate IPv6 loopback redirect syntax according to upstream semantics, but
treat an IPv6 loopback redirect as an execution-time unsupported-platform
error when opening the browser flow unless the implementation can actually
bind that IPv6 loopback address. The error must be explicit and must not
silently fall back to IPv4, a wildcard v6 listener, or a hostname rewrite.

IPv4 loopback redirect URIs remain supported within the constraints of
ADR-0061 (`INADDR_ANY` binding, strict Host/state/path checks, short
lifetime).

## Consequences

- `http://127.0.0.1:<port>/<path>` and other IPv4-loopback redirects provide
  the supported oxttp path.
- A user configuring `http://[::1]:<port>/<path>` receives a clear failure
  rather than insecure or incorrect behavior; this is an intentional
  documented deviation from upstream.
- Future oxl IPv6 listener support can remove the degradation without
  changing configuration parsing or OAuth protocol semantics.
