# 0015 — wire encoding lives in core/http, not the apps

Status: accepted (2026-11-17, WI-0004 brainstorm)

`model.Req` is the domain request; its `Body` enum carries typed
variants (Empty/Raw/Json/Form/Multipart/FileBody). Rendering those
variants to bytes — JSON serialization, form url-encoding, multipart
boundary assembly, file reads — is wire knowledge, so it lives in
`core/http` (the transport), not in `cli`/`tui` callers and not in a
pre-flattened model field.

The transport also synthesizes the wire-only headers the domain does
not model: `Host` (from the URL authority, incl. non-default port),
`Content-Length` (from rendered bytes), `Accept-Encoding` (default
per ADR-0014), and `Connection`. Explicitly supplied headers always
win over synthesized ones — a caller that sets Content-Length takes
responsibility for it.

Consequence: `send()` accepts any well-formed `model.Req` — S5/S6
assemble domain data, never bytes — and apps stay socket-free per
ADR-0003. Request serialization is exercised through fixture-server
assertions (what actually reached the wire), keeping encodings
testable end-to-end.
