# 0016 — h1 sends Connection: close; no pooling in v0.1

Status: accepted (2026-11-17, WI-0004 specification)

xh (reqwest) sends `connection: keep-alive` and pools connections.
The v0.1 h1 transport performs one request per connection and
synthesizes `Connection: close` — a recorded corpus deviation on the
wire bytes, not a hidden one.

Rationale: a response carrying neither Content-Length nor
Transfer-Encoding is delimited by connection close (RFC 7230 §3.3.3);
asking the peer to keep the connection alive makes that unframed case
undecidable without a timeout. Closing also keeps every error path
leak-free with no idle-conn bookkeeping. Callers may still pass any
Connection header explicitly (explicit always wins, ADR-0015).

Consequence: a close-honoring server may echo `connection: close` in
response headers — a one-token difference the S5 differential harness
can see; the fixture/harness servers answer per what they receive.
Restoring `keep-alive` becomes meaningful when connection pooling
lands (post-v0.1); the change is confined to the synthesized
default plus body-framing tests.
