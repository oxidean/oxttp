# ADR-0048 — Import engines verified against ported upstream test vectors

- Status: accepted
- Date: 2026-11-28
- Work item: WI-0019 (M4c)

## Context

The import engines replicate ~4600 lines of upstream Go with dense
edge-case behavior (template expansion budgets, scope merging,
warning dedup, never-overwrite suffixing, dotenv quoting). ADR-0007
(differential verification) and the corpus-fidelity contract demand
behavioral evidence, not just compilation.

## Decision

1. Unit tests live beside each engine
   (`core/importing/{result,write,layers,openapi,postman,bruno}_test.oxl`)
   and port the *assertions* of upstream `*_test.go` /
   `probe_test.go` / `write_test.go` / `environment_test.go` /
   `scope_roundtrip_test.go` — same inputs, same expected
   requests/warnings/errors — rather than inventing new cases.
2. Multi-file fixtures (Postman collection+env, Bruno
   bruno.json/collection.bru/folder.bru/request.bru/environments/,
   OpenAPI JSON+YAML docs) are committed under
   `core/importing/testdata/` mirroring upstream `testdata/` layout.
3. CLI-level coverage extends `tui/cli_test.oxl` for the arg-parsing,
   exit-code, and stdout/stderr contract (Out fields), including the
   S2/S3 fidelity fixes.
4. Where an upstream test asserts behavior our recorded deviations
   (ADR-0045) change — e.g. YAML anchors, number lexemes — the test
   asserts the *deviated* behavior with a comment citing the ADR, so
   the gap stays visible.

## Consequences

- Test count grows large; keep fixtures small and assertions on
  warnings/errors/paths, not full-file golden dumps except where
  upstream itself golden-tests.
- Deviations remain greppable via ADR citations in tests.
