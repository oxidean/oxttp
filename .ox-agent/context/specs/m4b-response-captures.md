# WI-0018 spec — M4b response captures

Direction: ADR-0050 (core/capture engine), ADR-0051 (TUI publish),
ADR-0052 (document-order object iteration). Contract:
corpus-posting.md §1.4, §5.2 `captures` row, §6.4, §7 intro;
upstream `internal/model/captures.go`, `internal/ui/environments.go`,
`cmd/posting/run.go`, `internal/collection/format.go`,
`docs/guide/environments.md#response-captures` @ 32c4566.

**Scope: capture engine + decode-time validation + TUI publish.**
The thin headless-run capture wiring already present in `run_exec`
(per-request FAILED on capture error, run-scoped session-layer merge
across later requests) is included because it is part of the same
capture publication contract and is covered here; broader WI-0019
run/import/remote behavior remains out of scope. GraphQL/gRPC/WS
response kinds land in later M4 WIs; captures operate on `resp.body`
bytes regardless of kind (upstream captures "decoded gRPC JSON" /
final retained body — same rule applies when those transports arrive).

## New package `core/capture`

### JSON DOM (`JVal`)

```
struct JVal { kind:int, s:str, b:bool, key:str, child:own JVal, next:own JVal }
```

kind: 0=null, 1=bool(`b`), 2=number(`s`=raw lexeme), 3=string(`s`=
decoded), 4=object(children carry `key`), 5=array. Same shape as
`std/json.Json` (ADR-0050). `jparse(text) -> [own JVal, err]`:
strict JSON (whitespace, literals, number grammar `-?(0|[1-9]\d*)(\.\d+)?
([eE][+-]?\d+)?`, strings with `\" \\ \/ \b \f \n \r \t \uXXXX`
including surrogate pairs), trailing garbage = error, depth cap like
std (256). Duplicate object keys: last wins on lookup (Go map decode
semantics); document order retained for iteration.

### Path-encoded matches

A match is `JPath{steps: []JStep}`; `JStep{is_idx:bool, name:str,
idx:int}` — root-relative. Selectors never share node references;
values resolve by walking `JVal` children (name = last-wins member
lookup, index = array position with negative-from-end).

### JSONPath (RFC 9535, theory/jsonpath feature set)

`parse_path(text) -> [own JPQuery, err]` where
`JPQuery{root:bool, segs: []JPSeg}`; `JPSeg{desc:bool, sels:[]JPSel}`;
`JPSel{kind:int, name:str, idx:int, s_start/s_end/s_step:int +
has_start/has_end/has_step:bool, filt:own FExpr}`.
Kinds: 0 name, 1 wildcard, 2 index, 3 slice, 4 filter.

- Shorthand normalization happens in `capture_path` (below), NOT in
  the parser: `$`-prefix as-is; `[`-prefix → prepend `$`; identifier-
  start (`[A-Za-z_]` or byte >=0x80) → prepend `$.`; else error
  `invalid path %q: start with $, [ or a member name`. TrimSpace first;
  empty → `empty path`.
- Segments: `.name` / `['name']` / `["name"]` (string escapes as in
  JSONPath lexer: `\'` `\"` `\\` `\/` `\b` `\f` `\n` `\r` `\t`
  `\uXXXX`), `.*` / `[*]`, `[int]` (±(2^53−1) range, `-0` rejected),
  `[s:e:t]` slices (nil bounds default per step sign; step 0 → empty
  selection per upstream `Bounds`, NOT a parse error — verified
  `SliceSelector.Bounds` returns (0,0)), unions `[a,b,...]` mixing
  selector kinds, `?(expr)` filters, `..` descendant over
  name/wildcard/bracket-selector-lists.
- Blank space permitted between segments (`  $.a .b  ` valid).
- Name shorthand idents: `[A-Za-z0-9_]` + bytes >=0x80, first char not
  digit; `true`/`false`/`null` also valid member names in shorthand
  (upstream lexes them as name tokens in selector position).
- Trailing garbage after the query = parse error.

### Filter expressions (`FExpr`)

Flat struct, `own` links only:
`FExpr{kind, next:own FExpr, l:own FExpr, r:own FExpr,
q:own JPQuery, lit:own JVal, fn:int, cmp:int}`.

Kinds: OR (l=AND-chain head, `next` links alternatives),
AND (l=basic head, `next` links basics), NOT (l=child),
CMP (l/r operands, cmp op), TEST (existence, q), NTEST,
FUNC (fn id + args via l/`next` chain), operand wrappers:
QRY (path query in q), LIT (literal JVal), LOG (logical or-expr).

Grammar (mirroring theory/jsonpath parser): or = and (`||` and)*;
and = basic (`&&` basic)*; basic = `!`(`(`or`)` | func-call |
path-query) | `(`or`)` | literal [cmp literal] | path-query
[cmp comparable] | func-call. Comparable operands: literal,
singular query (`@`/`$` + name/index-only segments), or
FuncValue function. `!func()` = NOT(FUNC); `!(or)` = NOT(or-expr).

Functions (ids): length, count, value (FuncValue); match, search
(FuncLogical). Args are literals / queries / nested functions /
logical exprs. `match(a,b)`: both strings → compile `\A`+rewritten(b)+`\z`
and `matchstr` (full match); `search`: `matchstr` on rewritten(b)
(unanchored contains-match — Span.s>=0, empty matches count, matching
Go `MatchString`). `.`→`[^\n\r]` rewrite applies to unescaped dots
outside char classes (upstream does it AST-level; text rewrite is
equivalent for our grammar). Regex compile failure → false (upstream
same). std/regexp is a Pike-VM NFA (linear-time, RE2-class: no
backreferences/lookaround) but it does not yet implement RFC 9485
Unicode category escapes (`\p{L}`, `\P{N}`, …). That is a documented
upstream-limited deviation, not silent parity: those patterns compile
upstream but currently fail compilation here and therefore evaluate
false; full category support belongs in oxl std/regexp. `length`: string→rune... — **byte
length? NO**: upstream uses `utf8.RuneCountInString` — implement
rune count; array→len; object→member count; else nil.
`count(x)`: node-list length. `value(x)`: single node → value, else
nil.

### Filter evaluation semantics (spec/op.go parity)

- Operands evaluate to PVal{kind: NODES|VALUE|LOGICAL, ...}.
- `==`/`!=`: numeric-vs-numeric → float64 equality (body numbers parse
  lexeme→float; literal ints→float, decimals→float; unparseable
  lexeme like `1e400` → non-numeric, falls to structural compare on
  raw lexeme); else structural deep-equal (kind + payload; numbers
  compare by float when both parse, else lexeme equality).
- `<` `<=` `>` `>=`: RFC 9535 ordering. Strict ordering exists only
  for numbers (float64) and strings (byte-lexicographic); containers
  and booleans never order. `>` is operand-swapped `<`; equality
  implies the inclusive forms, including two missing operands. Mixed
  or non-orderable types are false except that structurally equal
  operands still satisfy `<=`/`>=`.
- Existence TEST: sub-query selects ≥1 node. NTEST: 0 nodes.
- Singular query operand missing → missing value: two missing operands compare equal; missing vs explicit `null` does not.
- Filter selector applies to array elements and object member values
  (document order — ADR-0052), collecting matches per element.
- Descendant `..`: select from node and all descendants recursively
  (containers only descend; scalars yield nothing).

### Public API

```
fn validate(captures []model.KV) -> err          // nil ok
fn capture_values(captures []model.KV, body []byte)
    -> [][2]str? -> use []model.KV out, err       // name/value pairs, sorted-name order
fn capture_path(path str) -> [own JPQuery, err]  // shorthand normalize + parse (internal ok)
```

`capture_values` algorithm (CaptureValues parity):
1. len(captures)==0 → return empty, nil (body never inspected).
2. validate all (names isIdentifier + paths parse) — collect in
   **sorted-name order** for deterministic first-error (upstream sorts
   map keys; our []KV order is file order — sort a copy by name).
3. `jparse(body)`; error → `captures require a valid JSON response
   body` — wait: upstream checks `json.Valid` first with that message,
   then Decode errors propagate raw. Match: invalid JSON →
   "captures require a valid JSON response body"; valid-JSON-but-
   trailing-garbage edge → our jparse error text.
   (Note: upstream `json.Valid` accepts any JSON value incl. scalars;
   `{"a":1} {}` fails json.Valid → same message. Our jparse must
   likewise reject trailing content with that message.)
4. For each capture in sorted-name order: select; len(matches)!=1 →
   `capture NAME: path "PATH" matched N values; expected exactly one`
   (PATH = the *original* trimmed shorthand text? — upstream prints
   `path %q` = the map value as written. Use the raw capture value
   string, not normalized.)
5. Encode value: string → text; else compact JSON emit (numbers raw
   lexeme; strings escaped per JSON; objects/arrays compact no
   spaces). All-or-nothing.

Validation errors (ValidateCaptures parity):
- bad name → `capture "NAME": invalid variable name`
- bad path → `capture NAME: <parse error>` — upstream wraps
  `capturePath` err which for shorthand violation is
  `invalid path "X": start with $, [ or a member name`; parse errors
  propagate the jsonpath error text (our own messages — close
  enough, spec notes text isn't byte-pinned upstream since it's the
  library's; we mirror the stable prefixes).

## `core/collection` changes

- `decode`: after `str_map` for `captures`, run `capture.validate`;
  error → decode error (malformed file path — TUI placeholder, run
  abort, save-load reject — all free).
- `encode`: validate before writing `captures` (upstream
  MarshalRequest parity); PRequests built in-memory with bad captures
  → encode error.
- Import `github.com/oxidean/oxttp/core/capture`.

## `tui/coll.oxl` changes (ADR-0051)

- `install_resp`: after history/focus block (order irrelevant but keep
  at end), if `a.pending_preq != nil && len(a.pending_preq.captures)>0`
  — wait: `a.pending_preq` is cleared at L1213 before our hook; capture
  evaluation must read captures BEFORE clearing, or stash. Evaluate
  `capture.capture_values(captures, resp.body-as-str)`:
  - err → `a.toast(1, "Couldn't capture response: "+msg)` (warning =
    level 1? check toast levels: 0 info,1 ?,2 error — upstream
    toastWarning; use the level the codebase uses for warnings —
    verify `a.toast` signature; send warns use toast(0) "info",
    errors toast(2). Pick the warn level used elsewhere e.g.
    "proxy unsupported" warn → match that).
  - ok → for each pair `session_set_capture`-style upsert into
    `a.session_vars` WITHOUT per-item rebuild; then one
    `rebuild_env(a)` + `var_rows_build(a)`; toast(0/1,
    "captured NAME" style? — upstream shows no per-capture toast;
    only failure warns. Match: no success toast.)
- Raw body bytes → str: `resp.body as str` (install_resp already does
  `text := resp.body as str`).
- `send_failed`: untouched (no response → no captures).
- `draft_to_request` already carries captures; `hist_open` doesn't
  send → no re-capture (free).

## Tests (`core/capture/capture_test.oxl`, `fn test_*`)

Mirror upstream `captures_test.go` cases:
- Full-capture map test (ID/ITEM/EMPTY/BOOL/NULL/ARRAY/OBJECT incl.
  `${literal}$cash`, big int `9007199254740993`, quoted keys, root
  array `[1].id`/`$[1].id`, `$` root string).
- JSONPath table: filters (`role == "admin"`, `active == true &&
  id > 20`, `match(@.role,"admin")`), `[-1]`, `[1:2]`, `[*]` single-
  match, `$..token`, `nested..token`, `.*`, `['unusual.key']['']`,
  unicode `日本語.id`, whitespace-padded path, big-number array
  compact-emit `[12345678901234567890,1.234567890123456789,1e400]`.
- Failure table: missing path, nested-through-scalar, index OOB,
  index-into-object, multi-match `[*]`/`?()`, union duplicate
  `['id','id']`, trailing-garbage body, non-JSON, empty body → all
  error with NO partial values; nil captures + non-JSON body → ok.
- Validation: bad paths list (`""`, `" "`, `data.`, `data.[0]`,
  `data[0]id`, `$data`, `$.data[`, `data[01]`, `data[?(@.id ==)]`,
  `.data`, `..id`, `@.id`, `*`, `1id`, `data["bad\x"]`, huge index) and
  bad names (`""`, `1ID`, `bad-name`, `$uuid`).
- Extra: slice negative step `[2:0:-1]`/`[::-1]`, union `[0,'a']`,
  `length()`/`count()`/`value()`/`search()` functions, `!(...)`,
  `!@.path`, existence `@.x`, string `<` ordering, `!=` on missing.
- `core/collection` tests: decode rejects bad capture name/path;
  encode rejects invalid PRequest captures; valid round-trips.
- `tui` send_test: staged PRequest with captures + fake transport
  returning JSON body → session_vars updated; bad path → toast +
  vars unchanged; non-JSON body + captures → warn toast.

## Acceptance criteria

- `oxl build ./core ./tui` … (per-dir loop) clean; `oxl test` green
  per leaf dir touched (`core/capture`, `core/collection`, `tui`).
- Every upstream `captures_test.go` case has an oxtlp twin passing.
- Corpus §6.4 behaviors: exactly-one-match, all-or-nothing, session
  layer highest, literal strings, number precision, status-agnostic
  TUI publish, no publish on transport failure.
- Deviations documented: object filter order (ADR-0052); RFC 9485
  Unicode category escapes are unsupported by oxl std/regexp until the
  upstream regex gap is closed (oxidean/oxl#233); filter literal `1e400`-style overflow →
  our parse error vs upstream NumError text (message text not
  byte-pinned). The narrow run-path capture wiring is in scope here;
  the rest of run/import/remote remains WI-0019.
