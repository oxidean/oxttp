# WI-0018 plan — M4b response captures

Spec: artifacts/spec.md. ADRs 0050-0053.

## Stages

1. **core/capture — JSON DOM + reader** (`capture.oxl` part 1)
   - `JVal` struct (kind/s/b/key/child/next), kinds 0-5.
   - `jparse(text) -> [own JVal, err]` strict JSON, raw number
     lexemes, `\uXXXX`+surrogate pairs, depth cap 256, trailing-garbage
     rejection, duplicate keys last-wins on lookup.
   - Emit: `jemit` compact (numbers raw, strings escaped, no spaces).
   - Tests: parse/emit round-trips, lexeme preservation, errors.

2. **core/capture — JSONPath parser** (`capture.oxl` part 2)
   - `capture_path` shorthand normalize; `parse_path` → JPQuery AST
     (JPSel kinds name/wild/index/slice/filter; JPSeg desc flag).
   - Slice parse incl. negative step; index range ±(2^53−1), `-0` err;
     blank-space tolerance; union selectors; string escapes.
   - FExpr parser: or/and/not/cmp/test/ntest/func/operand wrappers per
     spec grammar.
   - Tests: upstream invalid-path table + valid grammar coverage.

3. **core/capture — evaluator + public API** (`capture.oxl` part 3)
   - Path-encoded matches `[]JPath`; segment select (name last-wins,
     index neg-from-end, wild doc-order, slice Bounds port, filter,
     descendant recursive).
   - PVal operand eval; comparison ops per spec/op.go; functions
     length/count/value/match/search via std/regexp.
   - `validate`, `capture_values` (sorted-name order, exact error
     strings, compact emit).
   - Tests: full upstream captures_test.go twin set + extras.

4. **core/collection — decode/encode validation**
   - decode: validate captures after str_map; encode: validate before
     emit. Import core/capture.
   - Tests in load_test.oxl: bad name/path rejected at decode;
     encode rejects invalid; valid round-trip unchanged.

5. **tui — publish hook** (`coll.oxl`, maybe `cfg.oxl` helper)
   - `install_resp`: evaluate captures on raw resp.body for any
     status; err → warning toast; ok → batch session upsert +
     single rebuild_env + var_rows_build.
   - send_test.oxl: fake transport JSON body → session_vars; bad
     path → toast + unchanged; non-JSON → warn.

6. **Verify**: `oxl build`/`oxl test` per leaf dir
   (core/capture, core/collection, tui); fix cycles ≤3.

## Risks

- oxl ownership/`own`-in-struct friction → path-encoded matches
  (ADR-0050) already de-risks; iterate on compile errors.
- Filter AST encoding complexity → flat FExpr with own links.
- `substr` END-index + byte-wise strings: UTF-8 names handled
  byte-wise (>=0x80 bytes all qualify — equivalent validity).
