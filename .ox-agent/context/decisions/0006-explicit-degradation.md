# 0006 — Parse everything, degrade explicitly

Status: proposed (2026-11-17, WI-0001 brainstorm — confirm at specification)

Every corpus surface parses and validates even when the behavior behind
it is unsupported in this build — TLS-related flags (`--verify`,
`--cert`, …), `https://` URLs, HTTP/2/3 requests, and any Posting config
key without a backing feature.

Unsupported behavior produces diagnostics in the target app's own error
shape ("unsupported in this build" class), never silent no-ops and never
unknown-flag/parser errors. Silent degradation of security-relevant
flags would make oxttp lie where xh/posting are honest.

Consequence: the parser is corpus-complete from the start; behavior
lands behind it incrementally. Specs tag each deferred surface with the
reason (e.g. decision 0001) and the unblocking condition (oxl std TLS).
