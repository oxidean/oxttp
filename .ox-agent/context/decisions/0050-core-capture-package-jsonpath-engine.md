# ADR-0050 — `core/capture` owns the response-capture engine

- Status: accepted
- Date: 2026-11-28
- Work item: WI-0018 (M4b response captures)

## Context

Corpus §6.4 pins `captures: {VAR: jsonpath}` semantics verbatim from
Posting 3 (`internal/model/captures.go` @ 32c4566): RFC 9535 JSONPath
via `github.com/theory/jsonpath`, exactly-one-match rule, lexeme-
precise numbers, all-or-nothing publish. Two consumers need it: the
TUI send path (`tui/coll.oxl install_resp`) now, and `posting run`
(WI-0019, per ADR-0038's deferred per-request FAILED degrade).

`std/encoding/json.jparse` coerces numbers through `atoi`/`atof`,
which cannot preserve `9007199254740993` or `1e400` — a corpus-pinned
fidelity requirement ("Captured numbers keep their original
precision"). No JSONPath facility exists in repo or std.

## Decision

1. New package `core/capture` (ADR-0016 per-concept layout) containing:
   - `JVal` — own linked-list JSON DOM mirroring `std/json.Json`'s
     proven shape (`kind/s/b/key/child/next`); kind=2 numbers store the
     **raw lexeme** in `s`.
   - A JSON reader (`jparse`) preserving number lexemes and document
     order; duplicate object keys resolve last-wins like Go's map
     decode.
   - An RFC 9535 parser + evaluator covering the full selector set
     theory/jsonpath implements: name/wildcard/index/slice (incl.
     negative step)/union/filter/descendant, blank-space tolerance,
     filter expressions (`||`,`&&`,`!`,parens,literals,singular+full
     path operands) and functions `length`/`count`/`value`/`match`/
     `search`.
   - `validate(captures []model.KV)` and
     `capture_values(captures []model.KV, body []byte) -> [][name,value], err`
     mirroring `ValidateCaptures`/`CaptureValues` error text.
2. Matches are represented as **paths** (step lists from the root),
   never shared node references — sidesteps `own`-in-slice ownership
   questions; values re-resolve by walking. Filter `@`/`$` operands
   evaluate sub-queries against the same path machinery.
3. `core/collection.decode` validates `captures` (bad name/path →
   decode error = malformed file, matching upstream ParseRequest);
   `encode` validates too (upstream MarshalRequest does).

## Consequences

- `tui` imports `core/capture` for the publish hook; WI-0019's run
  loop reuses `capture_values` for per-request capture + session-layer
  merge, retiring ADR-0038's FAILED degrade note.
- Number-lexeme fidelity is exact for capture *values*; numeric
  *comparisons inside filters* use float64 per upstream/docs.
- Deviations recorded in the WI spec: object-member filter iteration
  is document order (upstream Go map order is nondeterministic — same
  match set); `std/regexp` dialect verified against RE2 at
  implementation.
