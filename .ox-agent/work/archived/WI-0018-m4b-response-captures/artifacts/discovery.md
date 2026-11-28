# WI-0018 discovery — M4b response captures

Pin: oxl **0.26.0**. Corpus: docs/corpus/corpus-posting.md §1.4 (run
exit codes), §5.2 (`captures` schema row), §6.4 (response captures),
§7 intro (Posting-3-only list). Upstream pinned commit
`32c45669032342cf9b95d5758af47a0d93de0ad7` — `internal/model/captures.go`,
`internal/model/captures_test.go`, `internal/ui/environments.go`
(`captureResponse`), `cmd/posting/run.go` (`runRequest`),
`internal/collection/format.go` (ValidateCaptures at parse+marshal),
`docs/guide/environments.md` "Response captures".

## Verified upstream semantics (read first-hand)

- `model.CaptureValues(captures, body)` (internal/model/captures.go):
  - empty map → nil, no JSON requirement (non-JSON bodies pass when no
    captures declared).
  - `ValidateCaptures` first: every name must satisfy `isIdentifier`
    (`[A-Za-z_][A-Za-z0-9_]*`, internal/model/variables.go:107) and every
    path must parse via `capturePath`.
  - `capturePath`: TrimSpace; empty → error; `$`-prefixed parsed as-is;
    `[`-prefixed gets `$` prepended; identifier-start (letter/`_`/non-ASCII)
    gets `$.` prepended; anything else → `invalid path %q: start with $,
    [ or a member name`. Then full RFC 9535 parse via
    `github.com/theory/jsonpath` — no shorthand fallback.
  - Body must be `json.Valid`; decoded with `UseNumber` (number lexemes
    preserved — `9007199254740993`, `1e400` survive).
  - Each capture must match **exactly one** node; error:
    `capture %s: path %q matched %d values; expected exactly one`.
    Iteration order = sorted variable names (deterministic first-error).
  - Value encoding: string → raw text (unquoted); everything else →
    compact `json.Marshal` (numbers keep lexeme, objects/arrays compact,
    `null`/`true`/`false` literal). All-or-nothing: any error → no values.
- TUI (internal/ui/app.go:682 → environments.go:137):
  `captureResponse(req, resp)` runs on **every completed response
  regardless of HTTP status** (docs/guide/environments.md: "after a
  complete response, regardless of its HTTP status"), using the request
  snapshot — cancelled/replaced requests never publish. Failure →
  toastWarning "Couldn't capture response: err", response stays,
  all existing session values unchanged (atomic). Success → merge
  into `sessionVars` map (session layer = highest precedence); variables
  screen refreshes if open.
- `run` (cmd/posting/run.go:320-341): captures run only when the
  outcome is neither error-class nor warning-class (GraphQL errors /
  stream error); redirect outcomes DO capture. Transport error → no
  captures. Failure → result.Error, outcome failed; captures
  merge as a session-sourced layer for later requests, discarded at end.
- Decode-time validation: internal/collection/format.go:119 —
  ValidateCaptures runs inside request parse, so a bad name/path makes
  the file malformed (TUI placeholder row / run abort). Marshal
  (line 221) validates too.

## JSONPath engine surface (theory/jsonpath = RFC 9535)

Selectors: name shorthand (`.foo`, ident runes `[A-Za-z0-9_]` +
non-ASCII >=0x80, first char not digit), `*`/`.*`, bracket names
(`['a']`, `["a"]`, escapes incl `\uXXXX`), index ints (range
+/-(2^53-1), `-0` rejected), slices `[start:end:step]` (nil
start/end default by step sign; negative step supported), unions via
`,`, filter `?(expr)`, descendant `..name`/`..*`/`..[selectors]`.
Blank space allowed between segments.

Filter grammar: `||` of `&&` of basic-exprs; basic = literal /
singular-or-full path (`@`,`$`) with optional comparison / existence
test / `!path` non-existence / `!(or-expr)` / `!func()` / function call.
Comparison ops `==` `!=` `<` `<=` `>` `>=`. Literals: string, integer,
number, true/false/null. Functions (registry): `length`, `count`,
`value` (FuncValue), `match`, `search` (FuncLogical; `match` anchors
fully, `search` unanchored, `.` rewritten to `[^\n\r]`).

Comparison semantics (spec/op.go): numbers compare as float64;
string `<` byte-lexicographic; ordered comparisons require sameType
(both numeric or same JSON type); `==`/`!=` numeric-vs-numeric →
float64 equality else structural deep-equal; missing path in singular
query → nil.

## Repo state today

- `core/collection` decodes `captures` into `PRequest.captures:
  []model.KV` (ordered) and marshals them back (L1443+). No validation —
  gap vs upstream parse-time ValidateCaptures.
- `tui/coll.oxl draft_to_request` carries `a.preq.captures` (L594);
  `install_resp` (L1099) is the post-response hook; `session_set`
  (cfg.oxl L1613) is the session-var upsert + rebuild path.
- `tui/cli.oxl` headless `run` exists — WI-0019 owns
  import/run/remote completion; the engine must live in `core/` so both
  consumers share it.
- `std/encoding/json` `jparse` coerces numbers through `atoi`/`atof` —
  cannot preserve big/precise lexemes. Capture engine needs its own JSON
  reader keeping raw number text.

## Constraints / risks

- oxl 0.26.0: no str-keyed std maps; ordered `[]KV`; `own` tree nodes;
  multi-return last type `err`; `substr(s,start,end)` END index.
- `std/regexp` exists — check dialect vs Go RE2 for `match()`/`search()`.
- Unicode ident runes >=0x80: UTF-8 continuation bytes are all >=0x80,
  so a byte-wise >=0x80 check is equivalent for shorthand-name validity.
- Filter over object members: upstream iterates Go map order
  (non-deterministic); our DOM preserves document order — deterministic,
  same "exactly one" contract. Document in spec.
