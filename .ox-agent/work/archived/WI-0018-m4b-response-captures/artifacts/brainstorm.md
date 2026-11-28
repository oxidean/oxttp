# WI-0018 brainstorm — M4b response captures

Discovery: artifacts/discovery.md. Upstream semantics are fully pinned;
the open questions are packaging, JSONPath engine scope, and where
decode-time validation hooks in.

## Q1 — where does the capture engine live?

- **A. New `core/capture` package** (recommended). Self-contained:
  JSON reader (lexeme-preserving), RFC 9535 parser/evaluator,
  `capture_values` + `validate` entry points. `core/collection` already
  imports `core/model` only; adding a `core/capture` dep keeps the
  schema package clean and gives `tui` and the future `run` (cli.oxl /
  WI-0019) one import. Matches ADR-0016 per-concept package layout.
- **B. Inside `core/collection`.** Rejected: collection is the
  `.posting.yaml` schema codec; a JSONPath engine is a different
  concept, and run.go-equivalent code in cli would import collection
  for send planning anyway — but captures operate on *responses*,
  not requests. Model-adjacent but too big for `core/model` (131
  lines, transport types only).
- **C. Inside `core/model`.** Rejected for size; model stays the
  transport-agnostic wire/domain vocabulary.

**Recommendation: A — `core/capture`.**

## Q2 — JSON representation for evaluation

- **A. Own linked-list DOM mirroring `std/json.Json` shape**
  (`kind`, `s`=string-or-number-lexeme, `b`, `key`, `child`, `next`),
  with kind=2 numbers storing the raw lexeme. Proven navigation
  pattern (jpretty_at), no ownership puzzles, document order kept.
  (recommended)
- **B. Reuse `std/encoding/json.Json`.** Rejected: `jparse_num`
  routes through `atoi`/`atof` — loses `9007199254740993` and `1e400`
  (corpus-pinned: "Captured numbers keep their original precision").
- **C. Path-encoded matches only (no node refs).** Matches are
  represented as step lists from the root; values re-resolved by
  walking. Avoids `[]own`/shared-ownership questions entirely — this
  is the *representation* choice inside option A's evaluator, not a
  separate package option. Adopted: selectors yield `[]JPath`
  (`{is_idx, name|idx}` steps); `@`/`$` sub-queries evaluate against
  paths.

## Q3 — JSONPath feature scope

- **A. Full RFC 9535 as theory/jsonpath implements it**: all selector
  kinds, unions, descendant, slices (incl. negative step), filters
  with `&&`/`||`/`!`/parens, literals, singular+full path operands,
  functions length/count/value/match/search, blank-space tolerance.
  (recommended — corpus pins "JSONPath … same parser", upstream tests
  exercise filters/descendants/slices/negative indexes.)
- **B. Common subset** (names, index, wildcard, simple `?.field == lit`
  filters). Rejected: silent deviation from corpus; upstream accepts
  the full grammar and rejects nothing we could cheaply reject later.
- Cost note: filter AST needs a compact encoding — flat `FExpr` struct
  with `own` child/sibling links (Json child/next pattern), operands
  normalized to path-query / literal(JVal) / function / logical kinds.

## Q4 — decode-time validation hook

- **A. `collection.decode` calls `capture.validate_captures` after
  reading the `captures` block** (recommended). Upstream validates in
  ParseRequest → malformed file. Decode is the single funnel for
  load_file/scan/marshal-adjacent paths; TUI already renders decode
  errors as placeholder rows, `run` aborts — both correct for free.
- **B. Validate only at send.** Rejected: upstream rejects the file at
  load; a bad path would send-then-warn instead of placeholder.
- Marshal side: upstream also validates on MarshalRequest; our
  `collection.encode` writes captures verbatim from an already-valid
  PRequest — add the same check for defense (cheap: same function).

## Q5 — TUI publish semantics

- **A. Mirror `captureResponse` exactly**: after `install_resp`
  succeeds (any status class), evaluate `pending_preq.captures`;
  error → `toast(?, "Couldn't capture response: "+err)` warning-level,
  session untouched; success → `session_set` per capture (upsert +
  rebuild_env + var_rows_build — batch the rebuild: set all vars then
  rebuild once). (recommended)
- Ordering: captures evaluated against `resp.body` raw text (prettify
  doesn't matter — we parse the raw body, not the display text).
- History entries keep `req_yaml` which already carries captures —
  replaying history does NOT re-capture (upstream: "don't run when
  loading history" — our hist_open only renders, never sends → free).

## Preserved disagreement / open questions

- Object-member filter iteration order: upstream Go map order
  (nondeterministic); ours is document order. Same match *set*, only
  ordering of multi-match errors could differ in message text —
  acceptable, documented in spec.
- `std/regexp` dialect vs Go RE2 for `match()`/`search()`: verify at
  implementation; `.`→`[^\n\r]` rewrite replicated. If dialect gaps
  appear (e.g. backreferences — RE2 lacks them anyway), document.
- Slice step=0: upstream `Slice()` defaults + `Bounds` returns (0,0)
  for step==0 — i.e. `[:]` variants with explicit 0 step select
  nothing rather than error? Verify against parser: `parseSlice`
  accepts integer 0; Bounds step==0 → (0,0) → empty selection →
  "matched 0 values" capture error, not parse error. Replicate.
