# WI-0003 implementation plan - S2 core domain model + grammar

Spec: `artifacts/spec.md` (contracts + acceptance criteria).
Layout: ADR-0016. Grammar: `context/references/xh-request-item-grammar.md`.

## Stages

1. **Test-first grammar matrix** (tdd skill)
   - `core/item/item_test.oxl` — full REQUEST_ITEM matrix per spec AC2:
     12 syntax forms, longest-match ordering, escapes, `key;` quirks,
     part-params right-scan, error shapes. Plus `unescape` cases.
   - Compile-checked type usage tests for model/collection/session/term
     (construct every type, exercise field sets — they are the API
     surface tests since there is no IO to behaviorally verify).
   - Gate: tests compile, all grammar cases fail on missing impl
     (red), matrix written before implementation.

2. **Implement `core/model` + `core/item`**
   - `model/model.oxl`: Header, KV, Part, Body enum, Req, Resp, Trace,
     `status_class`. No imports beyond nothing.
   - `item/item.oxl`: `Item` enum, `parse`, `split`, `unescape`,
     `parse_part_params`, `rfind` helper. Imports `std/encoding/json`
     (`:=` eager validation), `std/strings`, `std/errors`.
   - Gate: grammar matrix green.

3. **Implement `core/session`, `core/collection`, `core/term`**
   - Types verbatim per spec; `session_path` pure fn + tests
     (`<host>[_<port>]/name.json`, reject `.`/`..`/empty).
   - `term`: Key enum + Named_* consts + mod bitset + Screen iface.
   - Gate: per-dir `oxl test` green.

4. **Transport port in `core/http`**
   - `interface Transport { send(...) }`; replace stub `request.oxl`
     (its `Req` is superseded by `model.Req` — check nothing imports
     it: only `cli/main.oxl` stub, update if needed).
   - Gate: `oxl build` all dirs; `cli`/`tui`/`shared` still build.

5. **Verify + wrap-up**
   - `oxl fmt` every touched file; `oxl build`+`oxl test` real output
     captured; corpus edge cases re-checked against matrix;
     findings list deviations (none expected) + upstream gaps.
   - Commit(s) `feat(core): domain model and request-item grammar`,
     push branch, PR, watch checks.

## Dependencies

- `item` → `std/{strings,errors,encoding/json}` only (self-contained;
  model not needed — items are the parse-side AST).
- `http` → `model`. `session` → `model` (Header). `collection`,
  `term`, `model` → nothing internal.
- WI-0002 (S1, shared/args) is parallel — no shared/ imports needed.

## Risks

- oxl enum/match/interface semantics may differ from sketch — mitigate
  by compiling each package as written (stage 2 first since it carries
  the gate); language tests in `oxidean-org/language/tests/` are the
  reference for working syntax.
- `own` fields inside enum payloads: verified pattern exists
  (`ExprKind.Bin{l: own Expr}`); `own json.Json` same shape.
- `oxl test` multi-dir quirk → run `oxl test` per package dir.
